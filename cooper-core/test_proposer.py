"""Tests for the self-improvement draft loop (Step 11)."""
import asyncio

import yaml

import proposer
import skills


FAKE_DRAFT = {
    "name": "stack-health-check",
    "description": "Run the stack health script and interpret its output.",
    "body": "## Procedure\nRun Test-PDAStack.ps1 and report failures first.",
}


def fake_extract(*args, **kwargs):
    async def _inner():
        return dict(FAKE_DRAFT)
    return _inner()


def run(coro):
    return asyncio.run(coro)


def _draft(tmp_path, extract=fake_extract, manifest_entries=None):
    manifest = tmp_path / "Config" / "skills_registry.yaml"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(yaml.safe_dump({"skills": manifest_entries or []}), encoding="utf-8")
    return run(proposer.draft_skill(
        {"id": "stack_test", "name": "Stack Test"},
        "check the stack health",
        "[Test-PDAStack.ps1 — OK]\nall green",
        base_url="", api_key="", model="", backend="ollama",
        repo_root=tmp_path, manifest_path=manifest,
        extract_fn=lambda *a, **k: extract(),
    ))


def test_draft_written_to_drafts_dir(tmp_path):
    path = _draft(tmp_path)
    assert path == tmp_path / "Skills" / "_drafts" / "stack-health-check"
    meta, body = skills.parse_skill_md((path / "SKILL.md").read_text(encoding="utf-8"))
    assert meta["name"] == "stack-health-check"
    assert "Procedure" in body


def test_draft_is_not_loadable(tmp_path):
    """Even if a manifest entry pointed straight at the draft (e.g. a stale
    or hand-edited entry), Step 10's _RESERVED_DIRS check must still refuse
    to load it — proves _drafts/ is inert by mechanism, not just by omission
    from the manifest."""
    path = _draft(tmp_path)
    manifest = tmp_path / "Config" / "skills_registry.yaml"
    entry = {
        "id": "stack-health-check",
        "path": str(path.relative_to(tmp_path)).replace("\\", "/"),
        "workshop": "open",
        "permission_level": 1,
        "content_hash": skills.compute_content_hash(path),
    }
    manifest.write_text(yaml.safe_dump({"skills": [entry]}), encoding="utf-8")
    assert skills.skill_status(entry, repo_root=tmp_path) == "draft_path"
    assert skills.list_skills("open", manifest_path=manifest, repo_root=tmp_path) == []


def test_no_draft_when_skill_already_registered(tmp_path):
    entry = {"id": "stack-health-check", "path": "Skills/x", "workshop": "open",
             "permission_level": 1, "content_hash": "aa"}
    assert _draft(tmp_path, manifest_entries=[entry]) is None


def test_no_duplicate_draft(tmp_path):
    assert _draft(tmp_path) is not None
    assert _draft(tmp_path) is None  # second run: draft dir already exists


def test_extraction_failure_returns_none(tmp_path):
    def broken(*a, **k):
        async def _inner():
            raise RuntimeError("llm down")
        return _inner()
    assert _draft(tmp_path, extract=broken) is None
