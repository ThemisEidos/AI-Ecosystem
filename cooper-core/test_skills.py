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
