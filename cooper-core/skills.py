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


_manifest_cache: dict = {}


def load_manifest(manifest_path: Optional[Path] = None) -> list:
    """Read Config/skills_registry.yaml (mtime-cached, matching registry.py's
    pattern). FAIL CLOSED: any read/parse error returns [] — zero skills load."""
    p = manifest_path or MANIFEST_PATH
    if not p.exists():
        return []
    try:
        mtime = p.stat().st_mtime
        if _manifest_cache.get("key") == (str(p), mtime):
            return _manifest_cache["entries"]
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        entries = data.get("skills") or []
        if not isinstance(entries, list):
            raise SkillError("'skills' key must be a list")
        _manifest_cache.update({"key": (str(p), mtime), "entries": entries})
        return entries
    except Exception as exc:
        print(f"  [!!] skills manifest unreadable — zero skills loaded (fail closed): {exc}")
        return []


def _entry_dir(entry: dict, repo_root: Path) -> Path:
    return (repo_root / str(entry.get("path", ""))).resolve()


def skill_status(entry: dict, repo_root: Optional[Path] = None) -> str:
    """Governance check for one manifest entry. Anything but 'ok' means disabled."""
    root = repo_root or _REPO_ROOT
    skills_dir = (root / "Skills").resolve()
    skill_dir = _entry_dir(entry, root)
    try:
        rel = skill_dir.relative_to(skills_dir)
    except ValueError:
        return "outside_skills_dir"
    if _RESERVED_DIRS & set(rel.parts):
        return "draft_path"
    if not (skill_dir / "SKILL.md").exists():
        return "missing"
    if compute_content_hash(skill_dir) != entry.get("content_hash"):
        return "hash_mismatch"
    return "ok"


def _load_skill(entry: dict, repo_root: Path) -> Optional[Skill]:
    try:
        status = skill_status(entry, repo_root)
        if status != "ok":
            print(f"  [!!] skill '{entry.get('id')}' disabled ({status}) — re-approve to enable")
            return None
        skill_dir = _entry_dir(entry, repo_root)
        try:
            meta, body = parse_skill_md((skill_dir / "SKILL.md").read_text(encoding="utf-8"))
        except (OSError, SkillError) as exc:
            print(f"  [!!] skill '{entry.get('id')}' unreadable — disabled: {exc}")
            return None
        if meta["name"] != skill_dir.name:
            print(f"  [!!] skill '{entry.get('id')}' frontmatter name != directory name — disabled")
            return None
        has_scripts = (skill_dir / "scripts").is_dir()
        permission_level = int(entry.get("permission_level", 1))
        if has_scripts and permission_level < 2:
            # Spec §3: script-bearing skills are Level 2+ by definition. Fail closed.
            print(f"  [!!] skill '{entry.get('id')}' is script-bearing but registered "
                  f"at L{permission_level} — disabled (script-bearing requires L2+)")
            return None
        truncated = len(body) > _MAX_BODY_CHARS
        if truncated:
            print(f"  [!!] skill '{entry.get('id')}' body exceeds {_MAX_BODY_CHARS} chars — truncated")
        return Skill(
            id=str(entry.get("id", meta["name"])),
            name=meta["name"],
            description=str(meta["description"]),
            body=body[:_MAX_BODY_CHARS],
            workshop=str(entry.get("workshop", "open")),
            permission_level=permission_level,
            path=skill_dir,
            has_scripts=has_scripts,
            truncated=truncated,
        )
    except Exception as exc:
        print(f"  [!!] skill '{entry.get('id')}' failed to load — isolated and skipped: {exc}")
        return None


def list_skills(
    workshop: str,
    *,
    manifest_path: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> list:
    """All loadable (approved, hash-valid) skills for a workshop."""
    root = repo_root or _REPO_ROOT
    out = []
    for entry in load_manifest(manifest_path):
        if str(entry.get("workshop", "open")).lower() != workshop.lower():
            continue
        s = _load_skill(entry, root)
        if s is not None:
            out.append(s)
    return out


# ── Selection (mirrors registry.select_tool's keyword-overlap approach) ─────
_STOPWORDS = {
    "the", "a", "an", "of", "to", "for", "and", "or", "in", "on", "at",
    "is", "are", "please", "can", "you", "me", "my", "it", "this", "that",
}

_SKILL_QUERY_RE = re.compile(
    r"\b(what|which|list|show)\b.{0,20}\bskills?\b"
    r"|\bskills?\b.{0,25}\b(available|do you have|learned|registered)\b",
    re.IGNORECASE,
)


def is_skill_query(message: str) -> bool:
    """Heuristic: does this message ask what skills exist?"""
    return bool(_SKILL_QUERY_RE.search(message))


def select_skill(
    workshop: str,
    message: str,
    *,
    manifest_path: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> Optional[Skill]:
    """Best keyword-overlap match against name/description. None if no overlap."""
    loadable = list_skills(workshop, manifest_path=manifest_path, repo_root=repo_root)
    words = {w for w in re.findall(r"[a-z]+", message.lower()) if w not in _STOPWORDS}
    if not loadable or not words:
        return None
    best, best_score = None, 0
    for s in loadable:
        hay = set(re.findall(r"[a-z]+", f"{s.name} {s.description}".lower()))
        score = len(words & hay)
        if score > best_score:
            best, best_score = s, score
    return best


def format_skill_context(skill: Skill) -> str:
    """System-prompt block for an activated knowledge skill (approved content)."""
    return (
        f"Activated skill: {skill.name} — {skill.description}\n"
        f"Follow this approved procedure where it applies:\n{skill.body}"
    )


def skill_context_for(
    workshop: str,
    message: str,
    *,
    manifest_path: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> str:
    """The one call main.py makes per turn. '' when nothing matches or on any error."""
    try:
        s = select_skill(workshop, message, manifest_path=manifest_path, repo_root=repo_root)
        return format_skill_context(s) if s is not None else ""
    except Exception as exc:
        print(f"  [!!] skill selection/formatting failed (non-fatal): {exc}")
        return ""


def format_skill_list(
    workshop: str,
    *,
    manifest_path: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> str:
    """Human-readable catalog including DISABLED entries with their reason."""
    root = repo_root or _REPO_ROOT
    entries = [
        e for e in load_manifest(manifest_path)
        if str(e.get("workshop", "open")).lower() == workshop.lower()
    ]
    if not entries:
        return f"No skills registered for the {workshop} workshop."
    lines = [f"{workshop.capitalize()} workshop skill registry — {len(entries)} skill(s):", ""]
    for e in sorted(entries, key=lambda e: str(e.get("id", ""))):
        status = skill_status(e, root)
        if status == "ok":
            s = _load_skill(e, root)
            desc = s.description if s else ""
            kind = "script-bearing" if (s and s.has_scripts) else "knowledge"
            lines.append(f"- {e.get('id')} [L{e.get('permission_level', '?')}, {kind}] — {desc}")
        else:
            lines.append(f"- {e.get('id')} [DISABLED: {status}] — re-approve to enable")
    return "\n".join(lines)
