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
worth reusing, write it as a skill. Set "reusable" to false when the task was a
test, demo, verification probe, or one-off — those must not become skills.
Output JSON only — no other text.

{"reusable":<true|false>,"name":"<lowercase-hyphen slug, 2-4 words>","description":"<one line: when to use this>","body":"<markdown: '## When to use' and '## Procedure' sections, under 300 words>"}\
"""

_DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "reusable":    {"type": "boolean"},
        "name":        {"type": "string"},
        "description": {"type": "string"},
        "body":        {"type": "string"},
    },
    "required": ["reusable", "name", "description", "body"],
}

# Governance actions on the skill catalog itself never get drafted as skills —
# otherwise approving a promotion/import immediately offers a meta-skill about
# promoting/importing, a self-referential loop the whole-branch review caught
# once Tasks 2 (drafting) and 3 (promote_skill) were combined.
_UNDRAFTABLE_EXECUTOR_TYPES = {"skill_promote", "skill_import"}

# Test/demo probes aren't reusable procedure — Batch 7 curation (2026-08-02)
# found 5 of 7 auto-drafts were residue of exactly these dispatch shapes.
_TEST_DISPATCH_RE = re.compile(
    r"\btest\b|\bdemo\b|\bpayload\b|\bbatch\s*\d+\b"
    r"|\bexample\.(?:com|org|net)\b|\bsay the word\b|\bsanity check\b|\bdry run\b",
    re.IGNORECASE,
)


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
    when skipped (already covered / duplicate / a governance action on the
    skill catalog itself) or on any failure (non-fatal)."""
    if tool.get("executor_type") in _UNDRAFTABLE_EXECUTOR_TYPES:
        return None
    if _TEST_DISPATCH_RE.search(message):
        return None
    extract_fn = extract_fn or _extract_draft
    root = repo_root or _REPO_ROOT
    try:
        draft = await extract_fn(
            message, raw_output,
            base_url=base_url, api_key=api_key, model=model, backend=backend,
        )
        if draft.get("reusable") is False:  # absent (legacy extract) → draftable
            return None
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
