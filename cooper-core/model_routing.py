"""COOPER's per-role model routing map (Step 15c). Implements
Scripts/PDA_ModelRouting.json — repo rule: no new policy files, implement the existing
one. Pure lookup: (role, workshop) -> the model alias that role's call site should pass
to its backend."""
import json
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent
_ROUTING_PATH = _REPO_ROOT / "Scripts" / "PDA_ModelRouting.json"


class ModelRoutingError(Exception):
    pass


def load_routing(path: Optional[Path] = None) -> dict:
    with open(path or _ROUTING_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def model_for(role: str, workshop: str, routing: Optional[dict] = None) -> str:
    """Resolve the model alias for `role` on `workshop` ('private' or 'open')."""
    routing = routing if routing is not None else load_routing()
    roles = routing.get("roles", {})
    if role not in roles:
        raise ModelRoutingError(f"unknown role '{role}' — not in {_ROUTING_PATH}")
    entry = roles[role]
    if workshop not in entry:
        raise ModelRoutingError(
            f"role '{role}' has no mapping for workshop '{workshop}'"
        )
    return entry[workshop]
