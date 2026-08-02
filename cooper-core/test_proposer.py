"""Tests for the self-improvement draft loop (Step 11)."""
import asyncio

import yaml

import archivist
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


def test_offer_line_format(tmp_path):
    path = _draft(tmp_path)
    assert proposer.offer_line(path) == (
        '\n\n[Proposer] Drafted skill \'stack-health-check\' from this run — '
        'say "promote skill stack-health-check" to review and activate it.'
    )
    assert proposer.offer_line(None) == ""


def test_no_draft_for_governance_tools(tmp_path):
    """Whole-branch review finding: with the tool param unchecked, approving
    a promote_skill/skill_import dispatch would draft a meta-skill about
    promoting/importing (a self-referential loop only visible once Tasks 2
    and 3 are combined). Also asserts the LLM extraction call is skipped
    entirely, not just its result discarded — no wasted round-trip."""
    calls = []

    def spy_extract(*a, **k):
        async def _inner():
            calls.append(1)
            return dict(FAKE_DRAFT)
        return _inner()

    manifest = tmp_path / "Config" / "skills_registry.yaml"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(yaml.safe_dump({"skills": []}), encoding="utf-8")

    for executor_type in ("skill_promote", "skill_import"):
        result = run(proposer.draft_skill(
            {"id": "promote_skill", "name": "Promote Skill", "executor_type": executor_type},
            "promote skill stack-health-check", "Skill 'stack-health-check' promoted…",
            base_url="", api_key="", model="", backend="ollama",
            repo_root=tmp_path, manifest_path=manifest,
            extract_fn=lambda *a, **k: spy_extract(),
        ))
        assert result is None
    assert calls == []


def test_activation_stats_roundtrip(tmp_path):
    conn = archivist.get_conn(tmp_path / "t.db")
    archivist.init_db(conn)
    assert skills.get_activation_count(conn, "hello-cooper") == 0
    skills.record_activation(conn, "hello-cooper")
    skills.record_activation(conn, "hello-cooper")
    assert skills.get_activation_count(conn, "hello-cooper") == 2


# ── Draft gate: test-residue dispatches (Batch 7 follow-up) ──────────────────

def _draft_msg(tmp_path, message, extract=fake_extract):
    manifest = tmp_path / "Config" / "skills_registry.yaml"
    manifest.parent.mkdir(exist_ok=True)
    manifest.write_text(yaml.safe_dump({"skills": []}), encoding="utf-8")
    return run(proposer.draft_skill(
        {"id": "t", "name": "T"}, message, "output ok",
        base_url="", api_key="", model="", backend="ollama",
        repo_root=tmp_path, manifest_path=manifest,
        extract_fn=lambda *a, **k: extract(),
    ))


def test_no_draft_for_test_style_dispatches(tmp_path):
    """Batch 7 curation found 5 of 7 drafts were residue of test dispatches —
    gate them BEFORE any LLM call is spent."""
    calls = []

    def spying():
        async def _inner():
            calls.append(1)
            return dict(FAKE_DRAFT)
        return _inner()

    for msg in [
        "run Test-Exec.ps1",
        "/reporter test payload from batch 5",
        "browse https://example.com and summarize the page",
        "use the router to say the word banana",
        "quick demo of the note editor",
    ]:
        assert _draft_msg(tmp_path, msg, extract=spying) is None, msg
    assert calls == []  # the LLM was never consulted


def test_no_draft_when_llm_marks_not_reusable(tmp_path):
    def not_reusable():
        async def _inner():
            return {**FAKE_DRAFT, "reusable": False}
        return _inner()

    assert _draft_msg(tmp_path, "check the stack health", extract=not_reusable) is None
    assert not (tmp_path / "Skills" / "_drafts" / "stack-health-check").exists()


def test_draft_proceeds_when_llm_marks_reusable(tmp_path):
    def reusable():
        async def _inner():
            return {**FAKE_DRAFT, "reusable": True}
        return _inner()

    path = _draft_msg(tmp_path, "check the stack health", extract=reusable)
    assert path is not None and (path / "SKILL.md").exists()
