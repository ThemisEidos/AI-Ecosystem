"""
COOPER Quartermaster — tool registry reader, OpenAI-schema renderer, and arg
validator (Step 15a).

Loads the workshop-scoped tool registry YAML and answers:

  1. "what tools are available?"        -> list_tools(workshop) / format_tool_list(workshop)
  2. "what does the model see as tool schemas?" -> render_workshop_tools(workshop)
  3. "is this tool_call's args valid?"  -> validate_args(tool, args)

Registry files live at Config/general_tool_registry.yaml (open) and
Config/private_tool_registry.yaml (private), per CLAUDE.md's directory map.
Files are re-read whenever their mtime changes, so editing the YAML takes
effect immediately under `--reload` without a server restart.

This module only reads, renders, and validates. It does not execute
anything — the approval gate (approval.py) and execution gateway
(executor.py) are separate.
"""
import json
import re
from pathlib import Path
from typing import Dict, List, Optional

import yaml

_REPO_ROOT = Path(__file__).resolve().parent.parent
_REGISTRY_PATHS: Dict[str, Path] = {
    "open":    _REPO_ROOT / "Config" / "general_tool_registry.yaml",
    "private": _REPO_ROOT / "Config" / "private_tool_registry.yaml",
}

_cache: Dict[str, dict] = {}  # workshop -> {"mtime": float, "tools": [...]}


class RegistryError(Exception):
    pass


def _registry_path(workshop: str) -> Path:
    path = _REGISTRY_PATHS.get(workshop)
    if path is None:
        raise RegistryError(f"unknown workshop: {workshop!r}")
    return path


def _load(workshop: str) -> List[dict]:
    path = _registry_path(workshop)
    if not path.exists():
        raise RegistryError(f"registry file not found for '{workshop}' workshop: {path}")

    mtime = path.stat().st_mtime
    cached = _cache.get(workshop)
    if cached and cached["mtime"] == mtime:
        return cached["tools"]

    try:
        with path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except yaml.YAMLError as exc:
        raise RegistryError(f"malformed YAML in '{workshop}' registry ({path}): {exc}")

    tools = [t for t in data.get("tools", []) if t.get("enabled", True)]
    _cache[workshop] = {"mtime": mtime, "tools": tools}
    return tools


def list_tools(workshop: str) -> List[dict]:
    """Return the enabled tool entries for a workshop, as loaded from disk."""
    return _load(workshop)


def get_tool(workshop: str, tool_id: str) -> Optional[dict]:
    """Look up a single tool by id within a workshop's registry."""
    for t in list_tools(workshop):
        if t.get("id") == tool_id:
            return t
    return None


def format_tool_list(workshop: str) -> str:
    """Human-readable registry listing, used for direct chat replies."""
    try:
        tools = list_tools(workshop)
    except RegistryError as exc:
        return f"Quartermaster error: {exc}"

    if not tools:
        return f"No tools registered for the {workshop} workshop."

    label = "Private Workshop" if workshop == "private" else "Open Workshop"
    lines = [f"{label} tool registry — {len(tools)} tool(s):", ""]
    for t in sorted(tools, key=lambda t: (t.get("permission_level", 0), t.get("name", ""))):
        approval = "approval required" if t.get("approval_required") else "auto-run"
        lines.append(
            f"- {t.get('name', t.get('id'))} "
            f"[{t.get('drawer', 'Uncategorized')}, L{t.get('permission_level', '?')}, {approval}] "
            f"— {t.get('description', '').strip()}"
        )
    return "\n".join(lines)


# ── Registry-query detection ────────────────────────────────────────────────
_REGISTRY_QUERY_RE = re.compile(
    r"\b(what|which|list|show)\b.{0,20}\btools?\b"
    r"|\btools?\b.{0,25}\b(available|do you have|can you use|registered)\b"
    r"|\btool\s+registry\b|\bquartermaster\b",
    re.IGNORECASE,
)


def is_registry_query(message: str) -> bool:
    """Heuristic: does this message ask what tools/capabilities exist?"""
    return bool(_REGISTRY_QUERY_RE.search(message))


# ── OpenAI-format tool schema rendering (Step 15a) ──────────────────────────
def render_tool_schema(tool: dict) -> dict:
    """One tool entry -> an OpenAI function-calling `tools` array element."""
    parameters = tool.get("parameters") or {
        "type": "object", "properties": {}, "additionalProperties": False,
    }
    return {
        "type": "function",
        "function": {
            "name": tool.get("id"),
            "description": tool.get("description", ""),
            "parameters": parameters,
        },
    }


def render_workshop_tools(workshop: str) -> List[dict]:
    """Every enabled tool for a workshop, rendered as OpenAI tool schemas —
    attached to the persona model on every turn (spec §2, step 1)."""
    return [render_tool_schema(t) for t in list_tools(workshop)]


# ── Arg validation (Step 15a) ───────────────────────────────────────────────
# Hand-rolled subset of JSON Schema (no jsonschema dependency — stdlib-first
# is the repo convention, spec §4). Covers what the registry's `parameters`
# blocks actually use: object/string/array-of-string/array-of-object,
# required keys, unknown-key rejection, and a custom `no_path_separators`
# flag (declared per-property in the YAML) so a bare-filename argument can
# be refused pre-approval rather than only sanitized at execution time.
def validate_args(tool: dict, args: dict) -> List[str]:
    """Validate a proposed tool_call's args against tool['parameters'].
    Returns a list of human-readable violation strings; empty = valid."""
    schema = tool.get("parameters") or {
        "type": "object", "properties": {}, "additionalProperties": False,
    }
    properties = schema.get("properties") or {}
    required = schema.get("required") or []
    violations: List[str] = []

    if not isinstance(args, dict):
        return [f"expected an object of arguments, got {type(args).__name__}"]

    for key in required:
        if key not in args:
            violations.append(f"missing required argument '{key}'")

    for key, value in args.items():
        if key not in properties:
            violations.append(f"unknown argument '{key}'")
            continue
        prop = properties[key]
        expected_type = prop.get("type")
        if expected_type == "string":
            if not isinstance(value, str):
                violations.append(f"argument '{key}' must be a string")
            elif prop.get("no_path_separators") and ("/" in value or "\\" in value):
                violations.append(
                    f"argument '{key}' must be a bare filename with no directory separators"
                )
        elif expected_type == "array":
            if not isinstance(value, list):
                violations.append(f"argument '{key}' must be an array")
            else:
                item_type = (prop.get("items") or {}).get("type")
                if item_type == "string" and not all(isinstance(v, str) for v in value):
                    violations.append(f"argument '{key}' must be an array of strings")
        elif expected_type == "object" and not isinstance(value, dict):
            violations.append(f"argument '{key}' must be an object")

    return violations
