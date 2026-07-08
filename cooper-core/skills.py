"""
COOPER Skills — governed SKILL.md subsystem (Step 10).

Hermes/Claude-compatible skill format under COOPER governance: a skill
directory (Skills/<category>/<name>/ containing SKILL.md with YAML
frontmatter) is INERT until an entry in Config/skills_registry.yaml
approves it, pinned by a content hash taken at approval time. Hash
mismatch = skill disabled until re-approved. All failures fail closed.

Spec: Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md §3.
"""
import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

import yaml

_REPO_ROOT    = Path(__file__).resolve().parent.parent
SKILLS_DIR    = _REPO_ROOT / "Skills"
MANIFEST_PATH = _REPO_ROOT / "Config" / "skills_registry.yaml"

_MAX_BODY_CHARS = 20_000  # ≈5,000 tokens at the repo's chars/4 estimate
_RESERVED_DIRS  = {"_drafts", "_incoming"}  # never loadable


class SkillError(Exception):
    pass


@dataclass
class Skill:
    id: str
    name: str
    description: str
    body: str
    workshop: str
    permission_level: int
    path: Path
    has_scripts: bool
    truncated: bool = False


_FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n?(.*)\Z", re.DOTALL)


def parse_skill_md(text: str) -> Tuple[dict, str]:
    """Split SKILL.md into (frontmatter dict, markdown body). Raises SkillError."""
    m = _FRONTMATTER_RE.match(text)
    if not m:
        raise SkillError("SKILL.md has no YAML frontmatter block")
    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as exc:
        raise SkillError(f"malformed frontmatter: {exc}")
    if not isinstance(meta, dict) or not meta.get("name") or not meta.get("description"):
        raise SkillError("frontmatter must define both 'name' and 'description'")
    return meta, m.group(2).strip()


def compute_content_hash(skill_dir: Path) -> str:
    """SHA-256 over every file in sorted relative-path order (path + contents),
    so the digest is deterministic across platforms (spec §3)."""
    h = hashlib.sha256()
    for f in sorted(p for p in skill_dir.rglob("*") if p.is_file()):
        h.update(f.relative_to(skill_dir).as_posix().encode("utf-8"))
        h.update(b"\0")
        h.update(f.read_bytes())
        h.update(b"\0")
    return h.hexdigest()
