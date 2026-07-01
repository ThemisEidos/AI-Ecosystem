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
from dataclasses import dataclass
from typing import Dict, Optional

_TICKET_TTL_SECONDS = 600  # 10 minutes


@dataclass
class ApprovalTicket:
    id: str
    workshop: str
    tool: dict
    message: str
    created_at: float


_pending: Dict[str, ApprovalTicket] = {}  # workshop -> ticket


def needs_approval(tool: dict) -> bool:
    """Level 2+ always gates, regardless of the registry flag (defense in depth)."""
    return bool(tool.get("approval_required")) or tool.get("permission_level", 0) >= 2


def request(workshop: str, tool: dict, message: str) -> ApprovalTicket:
    """Open a pending ticket for this workshop, replacing any prior pending ticket."""
    ticket = ApprovalTicket(
        id=uuid.uuid4().hex[:8],
        workshop=workshop,
        tool=tool,
        message=message,
        created_at=time.time(),
    )
    _pending[workshop] = ticket
    return ticket


def _get_live(workshop: str) -> Optional[ApprovalTicket]:
    ticket = _pending.get(workshop)
    if ticket is None:
        return None
    if time.time() - ticket.created_at > _TICKET_TTL_SECONDS:
        _pending.pop(workshop, None)
        return None
    return ticket


def has_pending(workshop: str) -> bool:
    return _get_live(workshop) is not None


def peek(workshop: str) -> Optional[ApprovalTicket]:
    """Read the pending ticket without consuming it (used by GET /pending)."""
    return _get_live(workshop)


_APPROVE_RE = re.compile(r"^\s*(yes|y|approve[d]?|confirm(ed)?|go ahead|do it|proceed)\b", re.IGNORECASE)
_DENY_RE    = re.compile(r"^\s*(no|n|deny|denied|cancel|stop|don'?t|abort)\b", re.IGNORECASE)


def is_response(message: str) -> bool:
    stripped = message.strip()
    return bool(_APPROVE_RE.match(stripped) or _DENY_RE.match(stripped))


def consume(workshop: str) -> Optional[ApprovalTicket]:
    """
    Consume and return the live ticket for this workshop, or None if none exists.
    Used by main.py to get the approved (tool, message) pair for execution.
    """
    ticket = _get_live(workshop)
    _pending.pop(workshop, None)
    return ticket


def is_approved(message: str) -> bool:
    return bool(_APPROVE_RE.match(message.strip()))


def is_denied(message: str) -> bool:
    return bool(_DENY_RE.match(message.strip()))
