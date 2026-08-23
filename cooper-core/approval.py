"""
COOPER Safety Officer — approval gate for the permission ladder (Step 4).

Levels 0/1 auto-run. Level 2+ (or any tool with approval_required: true in the
registry) halts: this module opens a pending ticket and returns a question.
The *next* message is checked against that ticket for an approve/deny
response before anything is reported as proceeding.

No remembered permissions: every action needs its own approval (Phase 1
rule from PRD/CLAUDE.md), so a ticket is single-use and expires.

State is in-memory, one pending ticket per workshop.
"""
import re
import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, Optional

_TICKET_TTL_SECONDS = 600  # 10 minutes


@dataclass
class ApprovalTicket:
    id: str
    workshop: str
    tool: dict
    message: str
    created_at: float
    session_id: str = "local"
    args: dict = field(default_factory=dict)


_pending: Dict[tuple, ApprovalTicket] = {}  # (workshop, session_id) -> ticket


def needs_approval(tool: dict) -> bool:
    """Level 2+ always gates, regardless of the registry flag (defense in depth)."""
    return bool(tool.get("approval_required")) or tool.get("permission_level", 0) >= 2


def request(
    workshop: str,
    tool: dict,
    message: str,
    session_id: str = "local",
    args: Optional[dict] = None,
) -> ApprovalTicket:
    """Open a pending ticket for this (workshop, session), replacing any prior one.
    Session binding (Step 13): only the session that opened a ticket can see or
    consume it — client A can never approve client B's action. `args` carries
    the tool_call's validated arguments through to execution on approve
    (Step 15a) — `main.py` reads `ticket.args` in `_execute`."""
    ticket = ApprovalTicket(
        id=uuid.uuid4().hex[:8],
        workshop=workshop,
        tool=tool,
        message=message,
        created_at=time.time(),
        session_id=session_id,
        args=args or {},
    )
    _pending[(workshop, session_id)] = ticket
    return ticket


def _get_live(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    key = (workshop, session_id)
    ticket = _pending.get(key)
    if ticket is None:
        return None
    if time.time() - ticket.created_at > _TICKET_TTL_SECONDS:
        _pending.pop(key, None)
        return None
    return ticket


def has_pending(workshop: str, session_id: str = "local") -> bool:
    return _get_live(workshop, session_id) is not None


def peek(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    """Read the session's pending ticket without consuming it (GET /pending)."""
    return _get_live(workshop, session_id)


# Full-match only: "yes, but first…" must NOT consume a ticket as approval.
# Chains of approve/deny tokens ("yes, go ahead", "no, cancel that") are allowed —
# only a trailing "that" (deny) is tolerated as filler; any other extra content fails the match.
_APPROVE_TOKEN = r"(?:yes|y|approve[d]?|confirm(?:ed)?|go ahead|do it|proceed)"
_DENY_TOKEN = r"(?:no|n|deny|denied|cancel|stop|don'?t|abort)"
_APPROVE_RE = re.compile(
    rf"^\s*{_APPROVE_TOKEN}(?:\s*,?\s*(?:and\s+)?{_APPROVE_TOKEN})*\s*[.!]*\s*$", re.IGNORECASE
)
_DENY_RE = re.compile(
    rf"^\s*{_DENY_TOKEN}(?:\s*,?\s*(?:and\s+)?{_DENY_TOKEN})*\s*(?:that)?\s*[.!]*\s*$", re.IGNORECASE
)


def is_response(message: str) -> bool:
    stripped = message.strip()
    return bool(_APPROVE_RE.match(stripped) or _DENY_RE.match(stripped))


def consume(workshop: str, session_id: str = "local") -> Optional[ApprovalTicket]:
    """Consume and return this session's live ticket, or None."""
    ticket = _get_live(workshop, session_id)
    _pending.pop((workshop, session_id), None)
    return ticket


def is_approved(message: str) -> bool:
    return bool(_APPROVE_RE.match(message.strip()))


def is_denied(message: str) -> bool:
    return bool(_DENY_RE.match(message.strip()))
