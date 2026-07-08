# Step 10 — Governed Skills Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** COOPER loads Hermes/Claude-compatible `SKILL.md` skills from `Skills/`, but only when a hash-pinned entry in `Config/skills_registry.yaml` approves them; matched knowledge skills inject into the turn's system prompt, and community skills import through the approval gate.

**Architecture:** New `cooper-core/skills.py` module (mirrors `registry.py`'s patterns: mtime cache, fail-closed loading, keyword selection). `main.py` wires three touchpoints: skill-catalog chat queries, per-turn knowledge injection, and an approval-gated `import_skill` tool whose halt message shows the full SKILL.md under review. Spec: `Docs/superpowers/specs/2026-07-08-cooper-hermes-merge-design.md` §3.

**Tech Stack:** Python 3.11+, FastAPI, PyYAML, pytest — all already in `cooper-core/requirements.txt`. No new dependencies.

## Global Constraints

- Branch from `step-9-dockerize` (e.g. `step-10-skills`); `main` does NOT have the v2 code.
- Stdlib + existing deps only (`fastapi`, `httpx`, `pydantic`, `yaml`, `pytest`). No new pip installs.
- **Every failure mode fails closed**: unreadable manifest ⇒ zero skills load; any skill validation failure ⇒ that skill disabled with a printed `[!!]` warning.
- Skill body cap: `_MAX_BODY_CHARS = 20_000` (≈5,000 tokens at the repo's chars/4 estimate).
- `Skills/_drafts/` and `Skills/_incoming/` are NEVER loadable, regardless of manifest content.
- Tap URLs: `https://` only in production (tests widen the scheme allowlist via monkeypatch).
- Run tests from `cooper-core/`: `cd cooper-core && python3 -m pytest test_skills.py -v`.
- Match existing cooper-core style: module docstring explaining the role, `[!!]`-prefixed warnings via `print`, `_UPPER` module constants.
- Do not touch `.env`, `PDA-Logs/`, `PDA-Runtime/data/`, or anything in CLAUDE.md's DO-NOT-TOUCH list.

---

### Task 1: skills.py core — SKILL.md parsing + content hash

**Files:**
- Create: `cooper-core/skills.py`
- Test: `cooper-core/test_skills.py`

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces: `SkillError(Exception)`; `Skill` dataclass (`id, name, description, body, workshop, permission_level, path, has_scripts, truncated`); `parse_skill_md(text: str) -> tuple[dict, str]`; `compute_content_hash(skill_dir: Path) -> str`.

- [ ] **Step 1: Write the failing tests**

```python
# cooper-core/test_skills.py
"""Tests for the governed skills subsystem (Step 10)."""
from pathlib import Path

import pytest

import skills


VALID_SKILL_MD = """\
---
name: hello-cooper
description: Greets the operator with COOPER's status conventions.
---

## When to use
When the operator asks for a demonstration skill.

## Procedure
Reply with a one-line status greeting.
"""


def make_skill_dir(root: Path, name: str = "hello-cooper", body: str = VALID_SKILL_MD) -> Path:
    d = root / "Skills" / "examples" / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(body, encoding="utf-8")
    return d


def test_parse_skill_md_returns_meta_and_body():
    meta, body = skills.parse_skill_md(VALID_SKILL_MD)
    assert meta["name"] == "hello-cooper"
    assert meta["description"].startswith("Greets")
    assert body.startswith("## When to use")


def test_parse_skill_md_rejects_missing_frontmatter():
    with pytest.raises(skills.SkillError):
        skills.parse_skill_md("# just markdown, no frontmatter")


def test_parse_skill_md_rejects_missing_required_fields():
    with pytest.raises(skills.SkillError):
        skills.parse_skill_md("---\nname: x\n---\nbody")  # no description


def test_content_hash_is_deterministic_and_tamper_sensitive(tmp_path):
    d = make_skill_dir(tmp_path)
    h1 = skills.compute_content_hash(d)
    h2 = skills.compute_content_hash(d)
    assert h1 == h2 and len(h1) == 64
    (d / "SKILL.md").write_text(VALID_SKILL_MD + "\ninjected", encoding="utf-8")
    assert skills.compute_content_hash(d) != h1


def test_content_hash_covers_nested_files(tmp_path):
    d = make_skill_dir(tmp_path)
    h1 = skills.compute_content_hash(d)
    (d / "scripts").mkdir()
    (d / "scripts" / "run.ps1").write_text("Write-Output hi", encoding="utf-8")
    assert skills.compute_content_hash(d) != h1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: FAIL / ERROR with `ModuleNotFoundError: No module named 'skills'`.

- [ ] **Step 3: Write the implementation**

```python
# cooper-core/skills.py
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/test_skills.py
git commit -m "feat(step-10): SKILL.md parsing + deterministic content hash"
```

---

### Task 2: Manifest loading — fail-closed, hash-pinned, workshop-scoped

**Files:**
- Modify: `cooper-core/skills.py` (append)
- Test: `cooper-core/test_skills.py` (append)

**Interfaces:**
- Consumes: Task 1's `parse_skill_md`, `compute_content_hash`, `Skill`, `SkillError`.
- Produces: `load_manifest(manifest_path: Optional[Path] = None) -> list[dict]`; `skill_status(entry: dict, repo_root: Optional[Path] = None) -> str` (returns `"ok" | "draft_path" | "outside_skills_dir" | "missing" | "hash_mismatch"`); `list_skills(workshop: str, *, manifest_path: Optional[Path] = None, repo_root: Optional[Path] = None) -> list[Skill]`. All path params default to the real repo locations; tests pass `tmp_path`-based roots.

- [ ] **Step 1: Write the failing tests (append to test_skills.py)**

```python
def write_manifest(root: Path, entries: list) -> Path:
    cfg = root / "Config"
    cfg.mkdir(exist_ok=True)
    p = cfg / "skills_registry.yaml"
    import yaml as _yaml
    p.write_text(_yaml.safe_dump({"skills": entries}), encoding="utf-8")
    return p


def approved_entry(root: Path, d: Path, **over) -> dict:
    entry = {
        "id": d.name,
        "path": str(d.relative_to(root)),
        "workshop": "open",
        "permission_level": 1,
        "approval_required": False,
        "content_hash": skills.compute_content_hash(d),
    }
    entry.update(over)
    return entry


def test_unregistered_skill_is_inert(tmp_path):
    make_skill_dir(tmp_path)
    manifest = write_manifest(tmp_path, [])  # skill on disk, not in manifest
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_registered_skill_loads(tmp_path):
    d = make_skill_dir(tmp_path)
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert len(loaded) == 1
    assert loaded[0].name == "hello-cooper"
    assert loaded[0].has_scripts is False


def test_hash_mismatch_disables_skill(tmp_path, capsys):
    d = make_skill_dir(tmp_path)
    entry = approved_entry(tmp_path, d)
    (d / "SKILL.md").write_text(VALID_SKILL_MD + "\ninjected", encoding="utf-8")
    manifest = write_manifest(tmp_path, [entry])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []
    assert "hash_mismatch" in capsys.readouterr().out


def test_drafts_never_load_even_if_registered(tmp_path):
    d = tmp_path / "Skills" / "_drafts" / "sneaky"
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(VALID_SKILL_MD.replace("hello-cooper", "sneaky"), encoding="utf-8")
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_path_outside_skills_dir_rejected(tmp_path):
    d = tmp_path / "Scripts"
    d.mkdir()
    (d / "SKILL.md").write_text(VALID_SKILL_MD, encoding="utf-8")
    entry = {
        "id": "escape", "path": "Scripts", "workshop": "open",
        "permission_level": 1, "content_hash": skills.compute_content_hash(d),
    }
    manifest = write_manifest(tmp_path, [entry])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_workshop_scoping(tmp_path):
    d = make_skill_dir(tmp_path)
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d, workshop="private")])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []
    assert len(skills.list_skills("private", manifest_path=manifest, repo_root=tmp_path)) == 1


def test_malformed_manifest_loads_zero_skills(tmp_path, capsys):
    make_skill_dir(tmp_path)
    cfg = tmp_path / "Config"
    cfg.mkdir()
    p = cfg / "skills_registry.yaml"
    p.write_text("skills: {not: [valid", encoding="utf-8")
    assert skills.list_skills("open", manifest_path=p, repo_root=tmp_path) == []
    assert "fail closed" in capsys.readouterr().out


def test_name_directory_mismatch_disables(tmp_path):
    d = make_skill_dir(tmp_path, name="wrong-dir-name")
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_oversize_body_truncated(tmp_path):
    big = VALID_SKILL_MD + ("x" * 30_000)
    d = make_skill_dir(tmp_path, body=big)
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert loaded[0].truncated is True
    assert len(loaded[0].body) == skills._MAX_BODY_CHARS


def test_script_bearing_skill_requires_level_2(tmp_path, capsys):
    d = make_skill_dir(tmp_path)
    (d / "scripts").mkdir()
    (d / "scripts" / "run.ps1").write_text("Write-Output hi", encoding="utf-8")
    # registered at L1 — spec §3: script-bearing skills are Level 2+ by definition
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d, permission_level=1)])
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []
    assert "script-bearing" in capsys.readouterr().out
    # at L2 it loads
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d, permission_level=2)])
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert loaded[0].has_scripts is True
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: Task 1 tests pass; new tests FAIL with `AttributeError: module 'skills' has no attribute 'list_skills'`.

- [ ] **Step 3: Write the implementation (append to skills.py)**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: 15 passed.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/test_skills.py
git commit -m "feat(step-10): fail-closed hash-pinned skills manifest loading"
```

---

### Task 3: Selection + catalog formatting

**Files:**
- Modify: `cooper-core/skills.py` (append)
- Test: `cooper-core/test_skills.py` (append)

**Interfaces:**
- Consumes: Task 2's `list_skills`, `load_manifest`, `skill_status`.
- Produces: `select_skill(workshop: str, message: str, *, manifest_path=None, repo_root=None) -> Optional[Skill]`; `is_skill_query(message: str) -> bool`; `format_skill_list(workshop: str, *, manifest_path=None, repo_root=None) -> str`; `format_skill_context(skill: Skill) -> str`; `skill_context_for(workshop: str, message: str) -> str` (the single call main.py makes per turn — returns `""` when nothing matches).

- [ ] **Step 1: Write the failing tests (append)**

```python
def test_select_skill_keyword_match(tmp_path):
    d = make_skill_dir(tmp_path)
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    got = skills.select_skill("open", "greet the operator please",
                              manifest_path=manifest, repo_root=tmp_path)
    assert got is not None and got.name == "hello-cooper"
    assert skills.select_skill("open", "zzz qqq unrelated",
                               manifest_path=manifest, repo_root=tmp_path) is None


def test_is_skill_query():
    assert skills.is_skill_query("what skills do you have?")
    assert skills.is_skill_query("list your skills")
    assert not skills.is_skill_query("how skilled are you at chess?")


def test_format_skill_list_shows_disabled_with_reason(tmp_path):
    d = make_skill_dir(tmp_path)
    entry = approved_entry(tmp_path, d)
    (d / "SKILL.md").write_text(VALID_SKILL_MD + "\ntampered", encoding="utf-8")
    manifest = write_manifest(tmp_path, [entry])
    listing = skills.format_skill_list("open", manifest_path=manifest, repo_root=tmp_path)
    assert "DISABLED" in listing and "hash_mismatch" in listing


def test_skill_context_for_returns_empty_on_no_match(tmp_path):
    manifest = write_manifest(tmp_path, [])
    assert skills.skill_context_for("open", "anything",
                                    manifest_path=manifest, repo_root=tmp_path) == ""
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: new tests FAIL with `AttributeError` on the missing functions.

- [ ] **Step 3: Write the implementation (append to skills.py)**

```python
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
    except Exception as exc:
        print(f"  [!!] skill selection failed (non-fatal): {exc}")
        return ""
    return format_skill_context(s) if s is not None else ""


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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: 19 passed.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/test_skills.py
git commit -m "feat(step-10): skill selection, catalog formatting, turn context"
```

---

### Task 4: main.py wiring — catalog queries, knowledge injection, GET /skills

**Files:**
- Modify: `cooper-core/main.py` (see exact anchor lines below; re-locate by content, the file may have drifted)
- Create: `cooper-core/test_main_skills.py`
- Create: `Skills/examples/hello-cooper/SKILL.md` (seed skill)
- Create: `Config/skills_registry.yaml` (seed manifest)

**Interfaces:**
- Consumes: Task 3's `skills.is_skill_query`, `skills.format_skill_list`, `skills.skill_context_for`, `skills.list_skills`, `skills.load_manifest`, `skills.skill_status`.
- Produces: `GET /skills` endpoint; skill-query short-circuit in `POST /chat`, `POST /v1/chat/completions`, and `_stream_sse`; skill context injected in `_generate` and `_stream_sse`.

- [ ] **Step 1: Write the failing test**

```python
# cooper-core/test_main_skills.py
"""main.py skill wiring: catalog query short-circuit + GET /skills (Step 10)."""
import os

os.environ.setdefault("WORKSHOP", "open")
os.environ.setdefault("COOPER_ALLOW_ANON", "1")
os.environ.pop("COOPER_API_KEY", None)

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402


def test_chat_answers_skill_query_without_llm(monkeypatch):
    monkeypatch.setattr(main.skills, "format_skill_list",
                        lambda workshop: f"SKILL-LIST[{workshop}]")
    with TestClient(main.app) as client:
        resp = client.post("/chat", json={"message": "what skills do you have?"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["reply"] == "SKILL-LIST[open]"
    assert body["decision"] == "answer"


def test_get_skills_endpoint(monkeypatch):
    monkeypatch.setattr(main.skills, "load_manifest", lambda: [
        {"id": "hello-cooper", "path": "Skills/examples/hello-cooper",
         "workshop": "open", "permission_level": 1, "content_hash": "dead"},
    ])
    monkeypatch.setattr(main.skills, "skill_status", lambda e: "hash_mismatch")
    with TestClient(main.app) as client:
        resp = client.get("/skills")
    assert resp.status_code == 200
    data = resp.json()
    assert data["workshop"] == "open"
    assert data["skills"][0]["status"] == "hash_mismatch"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cooper-core && python3 -m pytest test_main_skills.py -v`
Expected: FAIL — `AttributeError: module 'main' has no attribute 'skills'` (not imported yet).

- [ ] **Step 3: Wire main.py**

3a. Add the import after `import archivist` (main.py ~line 36):

```python
import skills
```

3b. In `POST /chat` (`chat()`, ~line 334), add the skill-query branch directly after the registry-query branch:

```python
    if skills.is_skill_query(req.message):
        reply = skills.format_skill_list(WORKSHOP)
        return {"reply": reply, "decision": "answer", "reason": "skill catalog answered directly"}
```

3c. Same branch in `oai_chat()` (~line 413), after its `is_registry_query` branch:

```python
    elif skills.is_skill_query(message):
        reply = skills.format_skill_list(WORKSHOP)
        td = TurnDecision(decision="answer", reason="skill catalog answered directly")
```

(Note: convert the existing `if registry.is_registry_query...` / `elif approval...` chain accordingly — the new branch slots between them as `elif`.)

3d. Same in `_stream_sse()` (~line 453):

```python
        elif skills.is_skill_query(message):
            content_iter = _single_text_chunk(skills.format_skill_list(WORKSHOP))
```

3e. Knowledge injection in `_generate()` (~line 509) — after the recall block, before `_build_messages`:

```python
    skill_ctx = skills.skill_context_for(WORKSHOP, message)
```

and after `msgs = _build_messages(history, message)`:

```python
    if skill_ctx:
        msgs.insert(1, {"role": "system", "content": skill_ctx})
```

3f. Knowledge injection in `_stream_sse()` — inside the existing `try` that builds `system_prompt` (~line 459), after the recall append:

```python
            skill_ctx = skills.skill_context_for(WORKSHOP, message)
            if skill_ctx:
                system_prompt = f"{system_prompt}\n\n{skill_ctx}"
```

3g. New endpoint after `GET /tools` (~line 283):

```python
# ── Skills (Step 10) ─────────────────────────────────────────────────────────
@app.get("/skills", dependencies=[Depends(_require_auth)])
async def list_skill_registry():
    entries = skills.load_manifest()
    report = []
    for e in entries:
        if str(e.get("workshop", "open")).lower() != WORKSHOP:
            continue
        report.append({
            "id":               e.get("id"),
            "path":             e.get("path"),
            "permission_level": e.get("permission_level"),
            "status":           skills.skill_status(e),
        })
    return {"workshop": WORKSHOP, "count": len(report), "skills": report}
```

3h. Seed skill — `Skills/examples/hello-cooper/SKILL.md`:

```markdown
---
name: hello-cooper
description: Demonstration skill — greet the operator with a COOPER status line.
---

## When to use
When the operator asks for a hello, a greeting demo, or a skills smoke test.

## Procedure
Reply with exactly one line: a dry TARS-style greeting that includes the
active workshop name and the word "operational".
```

3i. Seed manifest — `Config/skills_registry.yaml` (compute the real hash first):

Run: `cd cooper-core && python3 -c "import skills; print(skills.compute_content_hash(skills.SKILLS_DIR / 'examples' / 'hello-cooper'))"`

```yaml
# COOPER skills governance manifest (Step 10).
# A skill directory under Skills/ is INERT until listed here with a valid
# content_hash. Recompute after any approved edit:
#   cd cooper-core && python3 -c "import skills, pathlib; print(skills.compute_content_hash(pathlib.Path('../Skills/<category>/<name>')))"
skills:
  - id: hello-cooper
    path: Skills/examples/hello-cooper
    workshop: open
    permission_level: 1
    approval_required: false
    content_hash: "<paste output of the command above>"
```

- [ ] **Step 4: Run all tests**

Run: `cd cooper-core && python3 -m pytest test_main_skills.py test_skills.py test_main_auth.py test_main_open_routing.py -v`
Expected: all pass (existing auth/routing tests confirm no regression).

- [ ] **Step 5: Commit**

```bash
git add cooper-core/main.py cooper-core/test_main_skills.py "Skills/examples/hello-cooper/SKILL.md" Config/skills_registry.yaml
git commit -m "feat(step-10): wire skills into chat routing, injection, and GET /skills"
```

---

### Task 5: Tap importer — fetch, preview, register

**Files:**
- Modify: `cooper-core/skills.py` (append)
- Test: `cooper-core/test_skills.py` (append)

**Interfaces:**
- Consumes: Tasks 1–2 (`parse_skill_md`, `compute_content_hash`, `load_manifest`, `SkillError`).
- Produces: `parse_import_request(message: str) -> tuple[str, str]` (skill_name, url — raises `SkillError` on no match); `fetch_tap(url: str, skill_name: str, *, repo_root=None) -> Path` (clones, stages under `Skills/_incoming/<name>/`); `preview_import(message: str, *, repo_root=None) -> str` (fetch + return SKILL.md text, capped 3,500 chars); `register_import(message: str, *, repo_root=None, manifest_path=None) -> dict` (promote `_incoming/<name>` → `Skills/imported/<name>`, hash, append manifest entry with `workshop: open`).

- [ ] **Step 1: Write the failing tests (append)**

```python
import subprocess


def make_tap_repo(tmp_path: Path, skill_name: str = "tap-skill") -> str:
    """A local git repo laid out like a Hermes tap: skills/<name>/SKILL.md."""
    repo = tmp_path / "tap-src"
    d = repo / "skills" / skill_name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(
        f"---\nname: {skill_name}\ndescription: Imported test skill.\n---\n\nBody.\n",
        encoding="utf-8",
    )
    for cmd in (
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "seed"],
    ):
        subprocess.run(cmd, cwd=repo, check=True)
    return repo.as_uri()  # file:// URL


def test_parse_import_request():
    name, url = skills.parse_import_request(
        "import skill weekly-review from https://github.com/x/taps"
    )
    assert name == "weekly-review" and url == "https://github.com/x/taps"
    with pytest.raises(skills.SkillError):
        skills.parse_import_request("import something vague")


def test_fetch_tap_rejects_non_https():
    with pytest.raises(skills.SkillError):
        skills.fetch_tap("http://evil.example/repo", "x")
    with pytest.raises(skills.SkillError):
        skills.fetch_tap("file:///tmp/whatever", "x")


def test_import_flow_end_to_end(tmp_path, monkeypatch):
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    manifest = write_manifest(tmp_path, [])
    msg = f"import skill tap-skill from {url}"

    preview = skills.preview_import(msg, repo_root=tmp_path)
    assert "Imported test skill" in preview
    # staged in _incoming — still inert
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []

    entry = skills.register_import(msg, repo_root=tmp_path, manifest_path=manifest)
    assert entry["id"] == "tap-skill"
    assert entry["workshop"] == "open"
    assert (tmp_path / "Skills" / "imported" / "tap-skill" / "SKILL.md").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["tap-skill"]
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: new tests FAIL with `AttributeError` on missing functions.

- [ ] **Step 3: Write the implementation (append to skills.py; add `import shutil, subprocess, uuid` to the module imports)**

```python
# ── Tap importer (approval-gated via the import_skill registry tool) ─────────
_ALLOWED_SCHEMES  = ("https://",)
_IMPORT_RE        = re.compile(
    r"import\s+skill\s+([a-z0-9][a-z0-9-]*)\s+from\s+(\S+)", re.IGNORECASE
)
_CLONE_TIMEOUT    = 60
_PREVIEW_MAX      = 3_500


def parse_import_request(message: str) -> Tuple[str, str]:
    """Extract (skill_name, url) from 'import skill <name> from <url>'."""
    m = _IMPORT_RE.search(message)
    if not m:
        raise SkillError(
            'could not parse import request — use: import skill <name> from <https url>'
        )
    return m.group(1).lower(), m.group(2)


def fetch_tap(url: str, skill_name: str, *, repo_root: Optional[Path] = None) -> Path:
    """Clone a tap repo and stage skills/<name>/ under Skills/_incoming/<name>/.
    Staged skills are inert (reserved dir). Returns the staged path."""
    if not url.startswith(_ALLOWED_SCHEMES):
        raise SkillError(f"tap URL must use https:// — got scheme '{url.split(':', 1)[0]}'")
    root = repo_root or _REPO_ROOT
    incoming = root / "Skills" / "_incoming"
    incoming.mkdir(parents=True, exist_ok=True)
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
        src = clone_dir / "skills" / skill_name
        if not (src / "SKILL.md").exists():
            raise SkillError(f"tap has no skills/{skill_name}/SKILL.md")
        meta, _body = parse_skill_md((src / "SKILL.md").read_text(encoding="utf-8"))
        if meta["name"] != skill_name:
            raise SkillError(
                f"frontmatter name '{meta['name']}' != requested skill '{skill_name}'"
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && python3 -m pytest test_skills.py -v`
Expected: 22 passed.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/skills.py cooper-core/test_skills.py
git commit -m "feat(step-10): governed tap importer — fetch, preview, register"
```

---

### Task 6: import_skill tool — registry entry, executor, approval preview, live verification

**Files:**
- Modify: `Config/general_tool_registry.yaml` (append tool)
- Modify: `cooper-core/executor.py` (new executor_type)
- Modify: `cooper-core/workshop.py` (classify skill_import as cloud-calling)
- Modify: `cooper-core/main.py` (`_handle_dispatch` preview special-case)
- Test: `cooper-core/test_executor.py` (append), `cooper-core/test_workshop.py` (append)

**Interfaces:**
- Consumes: Task 5's `preview_import`, `register_import`, `SkillError`.
- Produces: dispatchable `import_skill` tool, end-to-end: dispatch → halt with SKILL.md preview → approve → registered.

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_workshop.py`:

```python
def test_skill_import_blocked_in_private():
    tool = {"id": "import_skill", "name": "Import Skill",
            "workshop": "Private Workshop", "executor_type": "skill_import"}
    with pytest.raises(workshop.WorkshopViolation):
        workshop.check_tool(tool, "private")
```

Append to `cooper-core/test_executor.py`:

```python
import skills as skills_mod


@pytest.mark.asyncio
async def test_skill_import_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_import",
        lambda message, **kw: {"id": "tap-skill", "workshop": "open",
                               "content_hash": "ab" * 32},
    )
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = await executor.run(tool, "import skill tap-skill from https://x/y", "open")
    assert "tap-skill" in out and "imported" in out.lower()


@pytest.mark.asyncio
async def test_skill_import_executor_reports_failure(monkeypatch):
    def boom(message, **kw):
        raise skills_mod.SkillError("bad tap")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = await executor.run(tool, "import skill x from https://x/y", "open")
    assert "failed" in out.lower() and "bad tap" in out
```

(If `pytest.mark.asyncio` is unavailable, follow whatever async-test pattern `test_executor.py` already uses — match the existing file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && python3 -m pytest test_executor.py test_workshop.py -v`
Expected: new tests FAIL (`skill_import` unhandled → stub text; workshop check passes when it shouldn't... note: the workshop test may already pass via the workshop-mismatch rule if the tool is Open-registered — the point of the change is defense in depth for the executor classification; keep the test with `workshop: "Private Workshop"` as written so it exercises the `_CLOUD_EXECUTORS` branch).

- [ ] **Step 3: Implement**

3a. `workshop.py` — change the frozenset (line 22) and docstring list:

```python
_CLOUD_EXECUTORS = frozenset({"browser", "llm_api", "skill_import"})
```

3b. `executor.py` — add to `run()` after the powershell branch (~line 104):

```python
    if executor_type == "skill_import":
        return await _run_skill_import(message)
```

and the handler (plus `import skills` at the top of executor.py):

```python
async def _run_skill_import(message: str) -> str:
    """Post-approval skill registration. Network + filesystem work off-loop."""
    loop = asyncio.get_running_loop()

    def _sync() -> str:
        entry = skills.register_import(message)
        return (
            f"Skill '{entry['id']}' imported and registered for the "
            f"{entry['workshop']} workshop (hash {entry['content_hash'][:12]}…). "
            f"It is now live. Promote to Private only via a separate approval."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill import failed — {exc}"
```

3c. `main.py` `_handle_dispatch()` — replace the `if approval.needs_approval(tool):` block body so import requests show the SKILL.md under review (spec §3 "present the full SKILL.md content in the approval question"):

```python
    if approval.needs_approval(tool):
        preview = ""
        if tool.get("executor_type") == "skill_import":
            try:
                text = await asyncio.to_thread(skills.preview_import, message)
                preview = f"\n\nSKILL.md under review:\n---\n{text}\n---"
            except skills.SkillError as exc:
                return f"Skill import rejected before approval: {exc}"
        approval.request(WORKSHOP, tool, message)
        return (
            f"Halt — {tool.get('name', tool.get('id'))} "
            f"[{tool.get('drawer', 'Uncategorized')}, permission level {tool.get('permission_level', '?')}] "
            f"requires approval before it can proceed{skill_note}. Reply 'approve' or 'deny'."
            f"{preview}"
        )
```

3d. `Config/general_tool_registry.yaml` — append under `tools:` (match existing entry style exactly):

```yaml
  - id: import_skill
    name: Import Skill
    drawer: Skills
    workshop: Open Workshop
    description: Import a community SKILL.md skill from a tap repository into the Open workshop. Usage — import skill <name> from <https url>. Shows the SKILL.md for review before approval.
    permission_level: 2
    approval_required: true
    executor_type: skill_import
    enabled: true
    inputs:
      - skill_name
      - tap_url
    outputs:
      - manifest_entry
    notes: Fetches stage to Skills/_incoming (inert) at preview time; registration happens only after approval. Open Workshop only — skill_import is classified cloud-calling.
```

- [ ] **Step 4: Run the full suite**

Run: `cd cooper-core && python3 -m pytest -v`
Expected: all tests pass (including all pre-existing files).

- [ ] **Step 5: Live verification (Definition of Done — run, don't describe)**

Start the server (Windows-side, from WSL):
```bash
powershell.exe -Command "cd D:\D_Projects\01_AI_Ecosystem\cooper-core; .\Start-CooperCore.ps1"
```

Then verify each behavior:
```bash
# 1. Catalog: seed skill visible
curl -s -H "Authorization: Bearer cooper-local" http://localhost:8000/skills
# expect: hello-cooper with status "ok"

# 2. Chat catalog query
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "what skills do you have?"}'
# expect: reply listing hello-cooper

# 3. Knowledge injection (greeting matches seed skill keywords)
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "give me the hello greeting demo"}'
# expect: one-line TARS-style greeting naming the workshop — proves body injection

# 4. Tamper → disable
echo "injected" >> "Skills/examples/hello-cooper/SKILL.md"
curl -s -H "Authorization: Bearer cooper-local" http://localhost:8000/skills
# expect: status "hash_mismatch"
git checkout -- "Skills/examples/hello-cooper/SKILL.md"

# 5. Import flow (use a real public tap or a throwaway GitHub repo laid out as skills/<name>/SKILL.md)
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" \
  -d '{"message": "import skill <name> from https://github.com/<you>/<tap-repo>"}'
# expect: Halt + full SKILL.md preview
curl -s -X POST http://localhost:8000/chat -H "Authorization: Bearer cooper-local" \
  -H "Content-Type: application/json" -d '{"message": "approve"}'
# expect: imported + registered confirmation; then GET /skills shows it "ok"
```

Final browser confirmation (mandatory per project verification protocol): open Open WebUI at `http://localhost:3000`, ask "what skills do you have?" — the catalog must render in the UI.

- [ ] **Step 6: Commit**

```bash
git add Config/general_tool_registry.yaml cooper-core/executor.py cooper-core/workshop.py cooper-core/main.py cooper-core/test_executor.py cooper-core/test_workshop.py
git commit -m "feat(step-10): import_skill tool — approval-gated tap imports with SKILL.md preview"
```
