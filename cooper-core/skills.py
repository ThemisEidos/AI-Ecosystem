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
import shutil
import subprocess
import time
import uuid
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


# ── Tap importer (approval-gated via the import_skill registry tool) ─────────
_ALLOWED_SCHEMES  = ("https://",)
_IMPORT_RE        = re.compile(
    r"import\s+skill\s+([a-z0-9][a-z0-9-]*)\s+from\s+(\S+)", re.IGNORECASE
)
_SAFE_NAME_RE     = re.compile(r"\A[a-z0-9][a-z0-9-]*\Z")
_CLONE_TIMEOUT    = 60
_PREVIEW_MAX      = 3_500
_MAX_TAP_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB — generous for a skill dir, caps disk use
_MAX_CLONE_SIZE_BYTES = 50 * 1024 * 1024  # bounds the whole clone (incl. .git), not just skills/<name>
_STALE_STAGING_SECONDS = 3600  # _incoming/ orphans (denied/expired tickets) older than this get swept


def parse_import_request(message: str) -> Tuple[str, str]:
    """Extract (skill_name, url) from 'import skill <name> from <url>'."""
    m = _IMPORT_RE.search(message)
    if not m:
        raise SkillError(
            'could not parse import request — use: import skill <name> from <https url>'
        )
    return m.group(1).lower(), m.group(2)


def _reject_symlinks(src: Path) -> None:
    """Fail closed if any entry under src is a symlink (spec: no symlink dereference
    exfiltration via shutil.copytree). Rejects the whole import — never sanitizes."""
    for p in src.rglob("*"):
        if p.is_symlink():
            raise SkillError(
                f"tap contains a symlink ('{p.relative_to(src)}') — rejected for safety"
            )


def _dir_size_bytes(src: Path) -> int:
    return sum(f.stat().st_size for f in src.rglob("*") if f.is_file())


def _sweep_stale_staging(incoming: Path) -> None:
    """Remove _incoming/ entries older than the staleness window — orphans left
    by tickets that expired without ever being approved or denied."""
    now = time.time()
    for child in incoming.iterdir():
        try:
            if child.is_dir() and now - child.stat().st_mtime > _STALE_STAGING_SECONDS:
                shutil.rmtree(child, ignore_errors=True)
        except OSError:
            pass


def discard_staged(message: str, *, repo_root: Optional[Path] = None) -> bool:
    """Denied import: drop the staged _incoming/<name> dir. Silent no-op (False)
    when nothing is staged or the message isn't an import request."""
    try:
        name, _url = parse_import_request(message)
    except SkillError:
        return False
    staged = (repo_root or _REPO_ROOT) / "Skills" / "_incoming" / name
    if not staged.is_dir():
        return False
    shutil.rmtree(staged, ignore_errors=True)
    return True


def fetch_tap(url: str, skill_name: str, *, repo_root: Optional[Path] = None) -> Path:
    """Clone a tap repo and stage skills/<name>/ under Skills/_incoming/<name>/.
    Staged skills are inert (reserved dir). Returns the staged path."""
    if not _SAFE_NAME_RE.match(skill_name):
        raise SkillError(
            f"unsafe skill name '{skill_name}' — must match [a-z0-9][a-z0-9-]*"
        )
    if not url.startswith(_ALLOWED_SCHEMES):
        raise SkillError(f"tap URL must use https:// — got scheme '{url.split(':', 1)[0]}'")
    root = repo_root or _REPO_ROOT
    incoming = root / "Skills" / "_incoming"
    incoming.mkdir(parents=True, exist_ok=True)
    _sweep_stale_staging(incoming)
    clone_dir = incoming / f"_clone-{uuid.uuid4().hex[:8]}"
    dest = incoming / skill_name
    try:
        try:
            subprocess.run(
                ["git", "clone", "--depth", "1", url, str(clone_dir)],
                check=True, capture_output=True, timeout=_CLONE_TIMEOUT,
            )
        except subprocess.CalledProcessError as exc:
            raise SkillError(f"git clone failed: {exc.stderr.decode(errors='replace')[:300]}")
        except subprocess.TimeoutExpired:
            raise SkillError(f"git clone timed out after {_CLONE_TIMEOUT}s")
        clone_size = _dir_size_bytes(clone_dir)
        if clone_size > _MAX_CLONE_SIZE_BYTES:
            raise SkillError(
                f"tap clone too large ({clone_size} bytes > {_MAX_CLONE_SIZE_BYTES} cap)"
            )
        src = clone_dir / "skills" / skill_name
        if not (src / "SKILL.md").exists():
            raise SkillError(f"tap has no skills/{skill_name}/SKILL.md")
        meta, _body = parse_skill_md((src / "SKILL.md").read_text(encoding="utf-8"))
        if meta["name"] != skill_name:
            raise SkillError(
                f"frontmatter name '{meta['name']}' != requested skill '{skill_name}'"
            )
        _reject_symlinks(src)
        size = _dir_size_bytes(src)
        if size > _MAX_TAP_SIZE_BYTES:
            raise SkillError(
                f"tap skill directory too large ({size} bytes > {_MAX_TAP_SIZE_BYTES} cap)"
            )
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src, dest)
        return dest
    finally:
        shutil.rmtree(clone_dir, ignore_errors=True)


def preview_import(message: str, *, repo_root: Optional[Path] = None) -> str:
    """Fetch + stage the skill, return its SKILL.md text for the approval question."""
    name, url = parse_import_request(message)
    staged = fetch_tap(url, name, repo_root=repo_root)
    text = (staged / "SKILL.md").read_text(encoding="utf-8")
    if len(text) > _PREVIEW_MAX:
        text = text[:_PREVIEW_MAX] + "\n[... preview truncated]"
    return text


def register_import(
    message: str,
    *,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> dict:
    """Post-approval: promote _incoming/<name> to Skills/imported/<name>, hash it,
    append the manifest entry (workshop: open — Private promotion is a separate
    approval, spec §3). Re-fetches if staging is missing (e.g. ticket expired)."""
    name, url = parse_import_request(message)
    root = repo_root or _REPO_ROOT
    staged = root / "Skills" / "_incoming" / name
    if not (staged / "SKILL.md").exists():
        print(f"  [!!] skill '{name}' staged copy missing at registration — re-fetching from {url}")
        staged = fetch_tap(url, name, repo_root=repo_root)
    final = root / "Skills" / "imported" / name
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(staged), str(final))
    entry = {
        "id": name,
        "path": str(final.relative_to(root)).replace("\\", "/"),
        "workshop": "open",
        "permission_level": 1,
        "approval_required": False,
        "content_hash": compute_content_hash(final),
    }
    _append_manifest_entry(entry, manifest_path)
    return entry


# ── Draft promotion (Step 11; approval-gated via the promote_skill tool) ─────
_PROMOTE_RE = re.compile(r"promote\s+skill\s+([a-z0-9][a-z0-9-]*)", re.IGNORECASE)


def parse_promote_request(message: str) -> str:
    m = _PROMOTE_RE.search(message)
    if not m:
        raise SkillError("could not parse — use: promote skill <name>")
    return m.group(1).lower()


def _draft_dir(name: str, repo_root: Optional[Path] = None) -> Path:
    root = repo_root or _REPO_ROOT
    d = root / "Skills" / "_drafts" / name
    if not (d / "SKILL.md").exists():
        raise SkillError(f"no draft named '{name}' in Skills/_drafts/")
    return d


def preview_promote(
    message: str,
    *,
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> str:
    """SKILL.md text for the approval question — from the draft, or (fallback,
    matching register_promotion) from an already-registered skill being
    promoted into another workshop."""
    name = parse_promote_request(message)
    root = repo_root or _REPO_ROOT
    try:
        d = _draft_dir(name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == name), None
        )
        if existing is None:
            raise
        d = (root / str(existing["path"])).resolve()
        if not (d / "SKILL.md").exists():
            raise SkillError(f"registered skill '{name}' has no SKILL.md on disk")
    text = (d / "SKILL.md").read_text(encoding="utf-8")
    return text[:_PREVIEW_MAX] + ("\n[... preview truncated]" if len(text) > _PREVIEW_MAX else "")


def register_promotion(
    message: str,
    *,
    workshop: str = "open",
    repo_root: Optional[Path] = None,
    manifest_path: Optional[Path] = None,
) -> dict:
    """Post-approval: move the draft to Skills/learned/<name>, hash, register.
    Fallback (spec §3 'promoting a skill to Private is a second explicit
    approval'): when no draft exists but the skill is already registered for
    another workshop, add an entry for the ACTIVE workshop instead — this is
    how an imported Open skill gets promoted into Private."""
    name = parse_promote_request(message)
    root = repo_root or _REPO_ROOT
    try:
        src = _draft_dir(name, repo_root)
    except SkillError:
        existing = next(
            (e for e in load_manifest(manifest_path) if str(e.get("id")) == name), None
        )
        if existing is None:
            raise
        skill_dir = (root / str(existing["path"])).resolve()
        entry = {
            "id": name,
            "path": existing["path"],
            "workshop": workshop,
            "permission_level": int(existing.get("permission_level", 1)),
            "approval_required": bool(existing.get("approval_required", False)),
            "content_hash": compute_content_hash(skill_dir),
        }
        _append_manifest_entry(entry, manifest_path)
        return entry
    final = root / "Skills" / "learned" / name
    final.parent.mkdir(parents=True, exist_ok=True)
    if final.exists():
        shutil.rmtree(final)
    shutil.move(str(src), str(final))
    entry = {
        "id": name,
        "path": str(final.relative_to(root)).replace("\\", "/"),
        "workshop": workshop,
        "permission_level": 1,
        "approval_required": False,
        "content_hash": compute_content_hash(final),
    }
    _append_manifest_entry(entry, manifest_path)
    return entry


def _append_manifest_entry(entry: dict, manifest_path: Optional[Path] = None) -> None:
    p = manifest_path or MANIFEST_PATH
    data = {}
    if p.exists():
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    # Dedupe by (id, workshop): the same skill may legitimately hold one entry
    # per workshop (Open import later promoted to Private — spec §3).
    entries = [
        e for e in (data.get("skills") or [])
        if not (e.get("id") == entry["id"]
                and str(e.get("workshop", "open")) == str(entry.get("workshop", "open")))
    ]
    entries.append(entry)
    data["skills"] = entries
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
    _manifest_cache.clear()  # force reload on next read


# ── Activation stats (Step 11; stored beside the archivist's tables) ─────────
def record_activation(conn, skill_id: str) -> None:
    """Count one knowledge-skill activation. Non-fatal on any error."""
    from archivist import _DB_LOCK
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    try:
        with _DB_LOCK:
            conn.execute(
                "INSERT INTO skillmd_stats (skill_id, activation_count, last_activated) "
                "VALUES (?, 1, ?) ON CONFLICT(skill_id) DO UPDATE SET "
                "activation_count = activation_count + 1, last_activated = excluded.last_activated",
                (skill_id, now),
            )
            conn.commit()
    except Exception as exc:
        print(f"  [!!] skills.record_activation failed (non-fatal): {exc}")


def get_activation_count(conn, skill_id: str) -> int:
    from archivist import _DB_LOCK
    with _DB_LOCK:
        row = conn.execute(
            "SELECT activation_count FROM skillmd_stats WHERE skill_id = ?", (skill_id,)
        ).fetchone()
    return int(row[0]) if row else 0
