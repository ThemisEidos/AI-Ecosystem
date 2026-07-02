"""
COOPER Quartermaster — tool registry reader + selector (Step 3).

Loads the workshop-scoped tool registry YAML and answers two questions:

  1. "what tools are available?"  -> list_tools(workshop) / format_tool_list(workshop)
  2. "which tool fits this task?" -> select_tool(workshop, message)

Registry files live at Config/general_tool_registry.yaml (open) and
Config/private_tool_registry.yaml (private), per CLAUDE.md's directory map.
Files are re-read whenever their mtime changes, so editing the YAML takes
effect immediately under `--reload` without a server restart.

This module only reads and selects. It does not execute anything — the
approval gate (step 4) and execution gateway (step 5) are not wired yet.
"""
import json
import re
from pathlib import Path
from typing import Dict, List, Optional

import yaml

from decision import _ollama_complete, _openai_complete

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


# ── Capability selection (used on dispatch turns) ───────────────────────────
_STOPWORDS = {
    "the", "a", "an", "of", "to", "for", "and", "or", "in", "on", "at",
    "is", "are", "please", "can", "you", "me", "my", "it", "this", "that",
}


def select_tool(workshop: str, message: str) -> Optional[dict]:
    """
    Pick the best-matching enabled tool for a dispatch message by keyword
    overlap against each tool's name/description/drawer. Returns None if no
    tool scores above zero (nothing dispatches on a non-match).

    This is capability *selection* only — "which tool fits this task, in this
    workshop" (PRD step 3 DoD). It does not execute anything; steps 4/5 add
    the approval gate and execution gateway on top of whatever this returns.
    """
    try:
        tools = list_tools(workshop)
    except RegistryError:
        return None
    if not tools:
        return None

    words = {w for w in re.findall(r"[a-z]+", message.lower()) if w not in _STOPWORDS}
    if not words:
        return None

    best, best_score = None, 0
    for t in tools:
        haystack = " ".join([t.get("name", ""), t.get("description", ""), t.get("drawer", "")]).lower()
        hay_words = set(re.findall(r"[a-z]+", haystack))
        score = len(words & hay_words)
        if score > best_score:
            best, best_score = t, score
    return best


# ── LLM-backed selection (audit F2) ─────────────────────────────────────────
_SELECT_SYSTEM_TMPL = """\
You are COOPER's Quartermaster. Pick the single best tool for the user's task, \
or "none" if no tool fits. Output JSON only — no other text.

{{"tool_id":"<one of the ids below, or 'none'>"}}

Available tools:
{catalog}\
"""


async def select_tool_llm(
    workshop: str,
    message: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
) -> Optional[dict]:
    """Schema-constrained LLM pick from the registry; keyword fallback on any error."""
    try:
        tools = list_tools(workshop)
    except RegistryError:
        return None
    if not tools:
        return None

    ids = [t["id"] for t in tools if t.get("id")]
    catalog = "\n".join(
        f"- {t.get('id')}: {t.get('name', '')} — {t.get('description', '')}"
        for t in tools
    )
    messages = [
        {"role": "system", "content": _SELECT_SYSTEM_TMPL.format(catalog=catalog)},
        {"role": "user", "content": message},
    ]
    schema = {
        "type": "object",
        "properties": {"tool_id": {"type": "string", "enum": ids + ["none"]}},
        "required": ["tool_id"],
    }
    try:
        if backend == "openai":
            raw = await _openai_complete(
                base_url, api_key, model, messages,
                temperature=0,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "tool_selection",
                        "strict": True,
                        "schema": {**schema, "additionalProperties": False},
                    },
                },
            )
        else:
            raw = await _ollama_complete(
                base_url, model, messages,
                options={"temperature": 0},
                fmt=schema,
            )
        tool_id = json.loads(raw).get("tool_id", "none")
        if tool_id == "none":
            return None
        selected = get_tool(workshop, tool_id)
        if selected is None:
            # model named an id outside the registry — fall back to keywords
            return select_tool(workshop, message)
        return selected
    except Exception:
        return select_tool(workshop, message)
