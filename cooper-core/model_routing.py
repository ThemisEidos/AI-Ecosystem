"""COOPER's per-role model routing map (Step 15c). Implements
Scripts/PDA_ModelRouting.json — repo rule: no new policy files, implement the existing
one. Pure lookup: (role, workshop) -> the model alias that role's call site should pass
to its backend."""
import json
from pathlib import Path
from typing import List, Optional

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


def council_roster(workshop: str, routing: Optional[dict] = None) -> List[str]:
    """Resolve the council member roster for `workshop` ('private' or 'open')."""
    routing = routing if routing is not None else load_routing()
    rosters = routing.get("council_roster", {})
    if workshop not in rosters:
        raise ModelRoutingError(
            f"no council_roster mapping for workshop '{workshop}'"
        )
    return list(rosters[workshop])


def load_specialists(routing: Optional[dict] = None) -> dict:
    """The governed specialist roster (owner-directed 2026-09-07).

    name -> {alias, description}. The foreman (brain) picks BY NAME from this
    map; the llm_api executor refuses anything off it, and a registry drift
    guard keeps the YAML enum the brain sees equal to this map. Adding a
    specialist is a JSON edit to PDA_ModelRouting.json, not a code change.
    Malformed entries are dropped loudly rather than served half-formed.
    """
    data = routing if routing is not None else load_routing()
    out = {}
    for name, spec in (data.get("specialists") or {}).items():
        if not isinstance(spec, dict):
            print(f"  [!!] specialist '{name}' is not an object — dropped")
            continue
        alias = str(spec.get("alias") or "").strip()
        desc = str(spec.get("description") or "").strip()
        if not alias or not desc:
            print(f"  [!!] specialist '{name}' missing alias/description — dropped")
            continue
        out[str(name)] = {"alias": alias, "description": desc}
    return out
