"""Tests for the governed skills subsystem (Step 10)."""
from pathlib import Path

import pytest

import skills

import subprocess


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


def test_malformed_permission_level_isolated_from_sibling(tmp_path, capsys):
    """Prove exception isolation: one bad entry must not crash evaluation of siblings."""
    # Create two skills on disk with correct frontmatter names
    good_md = """\
---
name: skill-good
description: A valid skill for isolation testing.
---

## When to use
Testing.
"""
    bad_md = """\
---
name: skill-bad
description: A skill with malformed permission_level.
---

## When to use
Testing with bad data.
"""
    d_good = make_skill_dir(tmp_path, name="skill-good", body=good_md)
    d_bad = make_skill_dir(tmp_path, name="skill-bad", body=bad_md)

    # Register both: good one valid, bad one with malformed permission_level
    entries = [
        approved_entry(tmp_path, d_good, id="skill-good"),
        approved_entry(tmp_path, d_bad, id="skill-bad", permission_level="high"),  # not an int!
    ]
    manifest = write_manifest(tmp_path, entries)

    # list_skills must NOT raise — it must load the good one and skip the bad one
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert len(loaded) == 1
    assert loaded[0].id == "skill-good"

    # Verify the bad one triggered the isolation warning
    output = capsys.readouterr().out
    assert "skill-bad" in output
    assert "failed to load" in output


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


def test_skill_context_for_handles_format_skill_context_exception(tmp_path, monkeypatch, capsys):
    """Prove that if format_skill_context raises, skill_context_for catches it and returns ''."""
    # Set up a skill that will match the query
    d = make_skill_dir(tmp_path)
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])

    # Monkeypatch format_skill_context to raise an exception
    def failing_format(skill):
        raise RuntimeError("simulated format_skill_context failure")

    monkeypatch.setattr(skills, "format_skill_context", failing_format)

    # Call skill_context_for with a message that matches the skill
    # (select_skill will find it via keyword match)
    result = skills.skill_context_for("open", "greet the operator",
                                      manifest_path=manifest, repo_root=tmp_path)

    # Must return "" instead of raising
    assert result == ""
    # And must print a warning
    output = capsys.readouterr().out
    assert "[!!]" in output
    assert "non-fatal" in output


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


def test_fetch_tap_rejects_non_https():
    with pytest.raises(skills.SkillError):
        skills.fetch_tap("http://evil.example/repo", "x")
    with pytest.raises(skills.SkillError):
        skills.fetch_tap("file:///tmp/whatever", "x")


def test_fetch_tap_rejects_symlink_and_copies_nothing(tmp_path, monkeypatch):
    """Fix 1: a symlink inside the tap's skill dir must fail closed, and nothing
    should land in Skills/_incoming/ (no partial copy that could hide exfiltrated
    content from the SKILL.md-only preview)."""
    secret = tmp_path / "sensitive.txt"
    secret.write_text("super-secret-content", encoding="utf-8")

    url = make_tap_repo(tmp_path, skill_name="tap-skill")
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))

    # Re-create the repo with a symlink added after the initial commit isn't
    # necessary — git doesn't need to track the symlink target's content for
    # this test since fetch_tap inspects the checked-out working tree directly.
    # Add the symlink straight into the already-cloned-from source repo tree.
    repo = tmp_path / "tap-src"
    skill_dir = repo / "skills" / "tap-skill"
    (skill_dir / "leak.txt").symlink_to(secret)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "add symlink"],
        cwd=repo, check=True,
    )

    with pytest.raises(skills.SkillError, match="symlink"):
        skills.fetch_tap(url, "tap-skill", repo_root=tmp_path)

    dest = tmp_path / "Skills" / "_incoming" / "tap-skill"
    assert not dest.exists() or not any(dest.iterdir())


def test_fetch_tap_rejects_unsafe_skill_name(tmp_path, monkeypatch):
    """Fix 2: fetch_tap must independently validate skill_name, not trust the
    caller — a path-traversal payload must be rejected before any subprocess call."""
    def _spy_run(*a, **k):
        raise AssertionError("subprocess.run should not be called — name check must fail first")

    monkeypatch.setattr(subprocess, "run", _spy_run)
    with pytest.raises(skills.SkillError, match="unsafe skill name"):
        skills.fetch_tap("https://example.com/whatever", "../../Config", repo_root=tmp_path)


def test_fetch_tap_rejects_oversized_tap(tmp_path, monkeypatch):
    """Fix 3: a tap whose skill directory exceeds the size cap must be rejected."""
    url = make_tap_repo(tmp_path, skill_name="tap-skill")
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    monkeypatch.setattr(skills, "_MAX_TAP_SIZE_BYTES", 100)  # tiny cap for the test

    repo = tmp_path / "tap-src"
    skill_dir = repo / "skills" / "tap-skill"
    (skill_dir / "big.bin").write_bytes(b"x" * 1000)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "add big file"],
        cwd=repo, check=True,
    )

    with pytest.raises(skills.SkillError, match="too large"):
        skills.fetch_tap(url, "tap-skill", repo_root=tmp_path)


def test_register_import_logs_refetch_when_staging_missing(tmp_path, monkeypatch, capsys):
    """Fix 4: registration re-fetching due to missing staged copy must be logged."""
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    manifest = write_manifest(tmp_path, [])

    # Skip preview_import (which would stage it) and register directly —
    # staged dir is missing, forcing the re-fetch path.
    entry = skills.register_import("tap-skill", url, repo_root=tmp_path, manifest_path=manifest)
    assert entry["id"] == "tap-skill"
    output = capsys.readouterr().out
    assert "[!!]" in output and "re-fetching" in output


def test_import_flow_end_to_end(tmp_path, monkeypatch):
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    manifest = write_manifest(tmp_path, [])

    preview = skills.preview_import("tap-skill", url, repo_root=tmp_path)
    assert "Imported test skill" in preview
    # staged in _incoming — still inert
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []

    entry = skills.register_import("tap-skill", url, repo_root=tmp_path, manifest_path=manifest)
    assert entry["id"] == "tap-skill"
    assert entry["workshop"] == "open"
    assert (tmp_path / "Skills" / "imported" / "tap-skill" / "SKILL.md").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["tap-skill"]


def make_draft(root: Path, name: str = "stack-health-check") -> Path:
    d = root / "Skills" / "_drafts" / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: Drafted procedure.\n---\n\n## Procedure\nDo it.\n",
        encoding="utf-8",
    )
    return d


def test_promotion_flow(tmp_path):
    make_draft(tmp_path)
    manifest = write_manifest(tmp_path, [])
    preview = skills.preview_promote("stack-health-check", repo_root=tmp_path)
    assert "Drafted procedure" in preview
    entry = skills.register_promotion(
        "stack-health-check",
        workshop="open", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["id"] == "stack-health-check"
    assert (tmp_path / "Skills" / "learned" / "stack-health-check" / "SKILL.md").exists()
    assert not (tmp_path / "Skills" / "_drafts" / "stack-health-check").exists()
    loaded = skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)
    assert [s.name for s in loaded] == ["stack-health-check"]


def test_promote_missing_draft_raises(tmp_path):
    with pytest.raises(skills.SkillError):
        skills.preview_promote("ghost", repo_root=tmp_path)


def test_promote_registered_open_skill_into_private(tmp_path):
    # no draft — the skill is already live in Open; promotion adds a Private entry
    d = make_skill_dir(tmp_path, name="hello-cooper")
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, d)])
    entry = skills.register_promotion(
        "hello-cooper",
        workshop="private", repo_root=tmp_path, manifest_path=manifest,
    )
    assert entry["workshop"] == "private"
    # both workshops now load it — the Open entry survived the append
    assert len(skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path)) == 1
    assert len(skills.list_skills("private", manifest_path=manifest, repo_root=tmp_path)) == 1


# ── Step 10 deferred follow-ups (2026-08-02) ─────────────────────────────────

def test_fetch_tap_rejects_oversized_clone(tmp_path, monkeypatch):
    """The size cap must bound the whole clone, not just the final skills/<name>
    subdir — a huge file elsewhere in the tap repo must reject the import."""
    url = make_tap_repo(tmp_path, skill_name="tap-skill")
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    monkeypatch.setattr(skills, "_MAX_CLONE_SIZE_BYTES", 10_000, raising=False)

    repo = tmp_path / "tap-src"
    (repo / "big-elsewhere.bin").write_bytes(b"x" * 100_000)  # outside skills/
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "pad repo"],
        cwd=repo, check=True,
    )

    with pytest.raises(skills.SkillError, match="clone too large"):
        skills.fetch_tap(url, "tap-skill", repo_root=tmp_path)
    assert not (tmp_path / "Skills" / "_incoming" / "tap-skill").exists()


def test_discard_staged_removes_staging_dir(tmp_path, monkeypatch):
    """Denied imports must be able to clean their Skills/_incoming/<name> staging
    dir; discarding again (or a name with nothing staged) is a silent no-op."""
    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    skills.preview_import("tap-skill", url, repo_root=tmp_path)
    staged = tmp_path / "Skills" / "_incoming" / "tap-skill"
    assert staged.exists()

    assert skills.discard_staged("tap-skill", repo_root=tmp_path) is True
    assert not staged.exists()
    assert skills.discard_staged("tap-skill", repo_root=tmp_path) is False
    assert skills.discard_staged("no-such-skill", repo_root=tmp_path) is False


def test_fetch_tap_sweeps_stale_staging_dirs(tmp_path, monkeypatch):
    """Orphans from expired tickets: fetch_tap must remove _incoming entries older
    than the staleness window while leaving recent ones alone."""
    import os
    import time

    url = make_tap_repo(tmp_path)
    monkeypatch.setattr(skills, "_ALLOWED_SCHEMES", ("https://", "file://"))
    incoming = tmp_path / "Skills" / "_incoming"
    stale = incoming / "old-skill"
    stale.mkdir(parents=True)
    (stale / "SKILL.md").write_text("x", encoding="utf-8")
    past = time.time() - 7200
    os.utime(stale, (past, past))
    fresh = incoming / "fresh-skill"
    fresh.mkdir()
    (fresh / "SKILL.md").write_text("x", encoding="utf-8")

    skills.fetch_tap(url, "tap-skill", repo_root=tmp_path)
    assert not stale.exists()
    assert fresh.exists()


# ── Semantic skill selection (embeddings + keyword fallback) ─────────────────

def _two_skill_setup(tmp_path):
    a = make_skill_dir(tmp_path, name="stack-doctor", body=(
        "---\nname: stack-doctor\ndescription: Diagnose container stack problems.\n---\n\nBody A.\n"))
    b = make_skill_dir(tmp_path, name="note-writer", body=(
        "---\nname: note-writer\ndescription: Write vault notes.\n---\n\nBody B.\n"))
    manifest = write_manifest(tmp_path, [approved_entry(tmp_path, a), approved_entry(tmp_path, b)])
    return manifest


def test_select_skill_semantic_picks_highest_cosine(tmp_path):
    """Message shares no keywords with either skill — embeddings must decide."""
    import asyncio
    import sqlite3
    manifest = _two_skill_setup(tmp_path)
    conn = sqlite3.connect(":memory:", check_same_thread=False)

    async def embed_fn(texts):
        def vec(t):
            if "stack-doctor" in t:
                return [1.0, 0.0]
            if "note-writer" in t:
                return [0.0, 1.0]
            return [0.9, 0.1]  # the query — near stack-doctor
        return [vec(t) for t in texts]

    picked = asyncio.run(skills.select_skill_semantic(
        "open", "why is everything down?", conn=conn, model="m",
        embed_fn=embed_fn, manifest_path=manifest, repo_root=tmp_path))
    assert picked is not None and picked.name == "stack-doctor"


def test_select_skill_semantic_below_threshold_falls_back_to_keywords(tmp_path, monkeypatch):
    import asyncio
    import sqlite3
    manifest = _two_skill_setup(tmp_path)
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    monkeypatch.setattr(skills, "_SEMANTIC_SIM_DEFAULT", 0.99)

    async def embed_fn(texts):
        return [[1.0, 0.0] if "stack-doctor" in t else [0.5, 0.5] for t in texts]

    picked = asyncio.run(skills.select_skill_semantic(
        "open", "write vault notes please", conn=conn, model="m",
        embed_fn=embed_fn, manifest_path=manifest, repo_root=tmp_path))
    # similarity below threshold → keyword overlap picks note-writer
    assert picked is not None and picked.name == "note-writer"


def test_select_skill_semantic_embed_failure_falls_back_to_keywords(tmp_path):
    import asyncio
    import sqlite3
    manifest = _two_skill_setup(tmp_path)
    conn = sqlite3.connect(":memory:", check_same_thread=False)

    async def embed_fn(texts):
        raise RuntimeError("backend down")

    picked = asyncio.run(skills.select_skill_semantic(
        "open", "write vault notes please", conn=conn, model="m",
        embed_fn=embed_fn, manifest_path=manifest, repo_root=tmp_path))
    assert picked is not None and picked.name == "note-writer"


def test_select_skill_semantic_threshold_is_per_model(tmp_path, monkeypatch):
    """Similarity scales differ per embedding model (nomic ~0.5 vs openai ~0.3
    for true matches) — the acceptance threshold must be model-aware."""
    import asyncio
    import sqlite3
    manifest = _two_skill_setup(tmp_path)
    monkeypatch.setitem(skills._SEMANTIC_SIM_BY_MODEL, "loose-model", 0.20)
    monkeypatch.setattr(skills, "_SEMANTIC_SIM_DEFAULT", 0.48)

    async def embed_fn(texts):
        # 0.30 cosine between query and stack-doctor; 0.0 for note-writer
        def vec(t):
            if "stack-doctor" in t:
                return [1.0, 0.0, 0.0]
            if "note-writer" in t:
                return [0.0, 1.0, 0.0]
            return [0.3, 0.0, 0.9539392]
        return [vec(t) for t in texts]

    async def run(model):
        conn = sqlite3.connect(":memory:", check_same_thread=False)
        return await skills.select_skill_semantic(
            "open", "unrelated words entirely", conn=conn, model=model,
            embed_fn=embed_fn, manifest_path=manifest, repo_root=tmp_path)

    assert asyncio.run(run("loose-model")).name == "stack-doctor"   # 0.30 > 0.20
    assert asyncio.run(run("strict-model")) is None                 # 0.30 < 0.48 default, no keywords either
