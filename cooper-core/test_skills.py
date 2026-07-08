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
