"""
COOPER Signal gateway (Step 12).

Long-polls a local signal-cli-rest-api container for incoming Signal
messages, filters by sender allowlist (fail closed), routes each message
through main._chat_core, and replies via /v2/send.

Open workshop ONLY (spec §5): messages traverse a remotely reachable
channel, so the gateway must never front the Private workshop.
"""
import os
from dataclasses import dataclass, field
from typing import List, Optional, Tuple


@dataclass
class GatewayConfig:
    api_url: str
    number: str
    allowed_senders: frozenset = field(default_factory=frozenset)
    poll_timeout: int = 20


def load_config(env: Optional[dict] = None) -> Optional[GatewayConfig]:
    """None unless api_url, number, AND a non-empty allowlist are configured."""
    e = os.environ if env is None else env
    api_url = (e.get("SIGNAL_API_URL") or "").strip().rstrip("/")
    number  = (e.get("SIGNAL_NUMBER") or "").strip()
    senders = frozenset(
        s.strip() for s in (e.get("SIGNAL_ALLOWED_SENDERS") or "").split(",") if s.strip()
    )
    if not api_url or not number or not senders:
        return None
    return GatewayConfig(api_url=api_url, number=number, allowed_senders=senders)


def parse_envelopes(payload) -> List[Tuple[str, str]]:
    """(sender, text) for every dataMessage in a /v1/receive payload."""
    out: List[Tuple[str, str]] = []
    if not isinstance(payload, list):
        return out
    for item in payload:
        env = item.get("envelope", {}) if isinstance(item, dict) else {}
        text = (env.get("dataMessage") or {}).get("message")
        sender = env.get("source")
        if sender and text:
            out.append((str(sender), str(text)))
    return out


def is_allowed(cfg: GatewayConfig, sender: str) -> bool:
    """Fail closed: empty allowlist admits nobody."""
    return sender in cfg.allowed_senders
