"""
COOPER Proposer — self-improvement loop, draft side (Step 11).

After a successful dispatch→review cycle, draft a candidate SKILL.md into
Skills/_drafts/<slug>/. Drafts are inert (Step 10 reserves _drafts) until
the operator promotes one through the approval gate (promote_skill tool).

Governance: the agent may PROPOSE skills; only an approval can ACTIVATE one.
Spec: Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md §4.
"""
import json
import re
from pathlib import Path
from typing import Awaitable, Callable, Optional

from decision import _ollama_complete, _openai_complete
import skills

_REPO_ROOT = Path(__file__).resolve().parent.parent

_DRAFT_SYSTEM = """\
You are COOPER's Proposer. A dispatched task just succeeded. If the procedure is
worth reusing, write it as a skill. Output JSON only — no other text.

{"name":"<lowercase-hyphen slug, 2-4 words>","description":"<one line: when to use this>","body":"<markdown: '## When to use' and '## Procedure' sections, under 300 words>"}\
"""

_DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "name":        {"type": "string"},
        "description": {"type": "string"},
        "body":        {"type": "string"},
    },
    "required": ["name", "description", "body"],
}


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "unnamed-skill"


async def _extract_draft(
    message: str, raw_output: str, *,
    base_url: str, api_key: str, model: str, backend: str,
) -> dict:
    msgs = [
        {"role": "system", "content": _DRAFT_SYSTEM},
        {"role": "user", "content": f"Request: {message}\n\nResult:\n{raw_output[:2000]}"},
    ]
    if backend == "openai":
        raw = await _openai_complete(
            base_url, api_key, model, msgs, temperature=0,
            response_format={"type": "json_schema", "json_schema": {
                "name": "skill_draft", "strict": True,
                "schema": {**_DRAFT_SCHEMA, "additionalProperties": False},
            }},
        )
    else:
        raw = await _ollama_complete(
            base_url, model, msgs, options={"temperature": 0}, fmt=_DRAFT_SCHEMA,
        )
    return json.loads(raw)


async def draft_skill(
    tool: dict,
    message: str,
    raw_output: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
    extract_fn: Optional[Callable[..., Awaitable[dict]]] = None,
) -> Optional[Path]:
    """Draft a SKILL.md into Skills/_drafts/<slug>/. Returns the dir, or None
    when skipped (already covered / duplicate) or on any failure (non-fatal)."""
    extract_fn = extract_fn or _extract_draft
    root = repo_root or _REPO_ROOT
    try:
        draft = await extract_fn(
            message, raw_output,
            base_url=base_url, api_key=api_key, model=model, backend=backend,
        )
        name = slugify(str(draft.get("name", "")))
        description = str(draft.get("description", "")).strip()
        body = str(draft.get("body", "")).strip()
        if not description or not body:
            return None
        registered = {str(e.get("id", "")) for e in skills.load_manifest(manifest_path)}
        if name in registered:
            return None
        draft_dir = root / "Skills" / "_drafts" / name
        if draft_dir.exists():
            return None
        draft_dir.mkdir(parents=True)
        (draft_dir / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: {description}\n---\n\n{body}\n",
            encoding="utf-8",
        )
        return draft_dir
    except Exception as exc:
        print(f"  [!!] proposer.draft_skill failed (non-fatal): {exc}")
        return None


def offer_line(draft_dir: Optional[Path]) -> str:
    """One-line promotion offer appended to the dispatch reply. '' when no draft."""
    if draft_dir is None:
        return ""
    name = draft_dir.name
    return (
        f"\n\n[Proposer] Drafted skill '{name}' from this run — "
        f'say "promote skill {name}" to review and activate it.'
    )
