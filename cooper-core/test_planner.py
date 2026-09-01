"""Tests for narrow-scope job drafting (Step 15e, narrow — owner decision 2026-09-01)."""
import asyncio

import pytest
import yaml

import jobs
import planner


FAKE_DRAFT = {
    "id": "newsletter-links",
    "csv_path": "State/LinkAudit/links.csv",
    "rows_per_run": 10,
    "fetches_per_run": 30,
    "schedule_hint": "daily 03:00",
}


def fake_extract(**overrides):
    async def _inner(*args, **kwargs):
        return {**FAKE_DRAFT, **overrides}
    return _inner


def run(coro):
    return asyncio.run(coro)


def _write_csv(path, header="url,last_checked,status,notes\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + "https://a.example,,,\n", encoding="utf-8")


def _draft(tmp_path, *, extract=None, goal="watch the newsletter links CSV"):
    registry_path = tmp_path / "Config" / "jobs_registry.yaml"
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    return run(planner.draft_envelope(
        goal, workshop="open",
        base_url="", api_key="", model="", backend="ollama",
        repo_root=tmp_path, registry_path=registry_path,
        extract_fn=extract or fake_extract(),
    ))


def test_draft_envelope_persists_fixed_csv_monitor_shape(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path)

    assert entry["id"] == "newsletter-links"
    assert entry["workshop"] == "open"
    assert entry["steps"] == ["csv_next_rows", "url_verify", "csv_line_edit"]
    assert entry["permission_level"] == 3
    assert entry["approved"] is False
    assert entry["read_scope"] == ["State/LinkAudit/links.csv"]
    assert entry["write_scope"] == ["State/LinkAudit/links.csv"]
    assert entry["envelope_hash"] == jobs.compute_envelope_hash(entry)

    registry = jobs.load_registry(tmp_path / "Config" / "jobs_registry.yaml")
    assert jobs.get_job("newsletter-links", registry) == entry


def test_draft_envelope_ignores_llm_chosen_steps_and_permission_level(tmp_path):
    """The narrow-scope invariant: even if the LLM output carried extra keys
    trying to widen the job shape, draft_envelope must never read them —
    steps/permission_level/workshop are fixed in code, not in the schema."""
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    hostile = fake_extract(steps=["shell_exec"], permission_level=6, workshop="private")
    entry = _draft(tmp_path, extract=hostile)

    assert entry["steps"] == ["csv_next_rows", "url_verify", "csv_line_edit"]
    assert entry["permission_level"] == 3
    assert entry["workshop"] == "open"


def test_draft_envelope_rejects_empty_csv_path(tmp_path):
    with pytest.raises(planner.PlannerError, match="did not name"):
        _draft(tmp_path, extract=fake_extract(csv_path=""))


def test_draft_envelope_rejects_path_outside_repo(tmp_path):
    with pytest.raises(planner.PlannerError, match="not a safe repo-relative"):
        _draft(tmp_path, extract=fake_extract(csv_path="../outside.csv"))


def test_draft_envelope_rejects_nonexistent_csv(tmp_path):
    with pytest.raises(planner.PlannerError, match="does not exist"):
        _draft(tmp_path, extract=fake_extract(csv_path="State/LinkAudit/missing.csv"))


def test_draft_envelope_rejects_csv_without_url_column(tmp_path):
    csv_path = tmp_path / "State" / "LinkAudit" / "notes.csv"
    _write_csv(csv_path, header="topic,body\n")
    with pytest.raises(planner.PlannerError, match="no 'url' column"):
        _draft(tmp_path, extract=fake_extract(csv_path="State/LinkAudit/notes.csv"))


def test_draft_envelope_rejects_duplicate_job_id(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    registry_path = tmp_path / "Config" / "jobs_registry.yaml"
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    registry_path.write_text(
        yaml.safe_dump({"jobs": [{"id": "newsletter-links", "workshop": "open"}]}), encoding="utf-8"
    )
    with pytest.raises(planner.PlannerError, match="already exists"):
        _draft(tmp_path)

    # Must not have touched the existing entry.
    reg = jobs.load_registry(registry_path)
    assert len(reg["jobs"]) == 1


def test_draft_envelope_clamps_quota_to_max(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path, extract=fake_extract(rows_per_run=99999, fetches_per_run=99999))
    assert entry["quota"]["rows_per_run"] == planner._MAX_ROWS_PER_RUN
    assert entry["quota"]["fetches_per_run"] == planner._MAX_FETCHES_PER_RUN


def test_draft_envelope_defaults_quota_on_bad_values(tmp_path):
    _write_csv(tmp_path / "State" / "LinkAudit" / "links.csv")
    entry = _draft(tmp_path, extract=fake_extract(rows_per_run="not-a-number", fetches_per_run=None))
    assert entry["quota"]["rows_per_run"] == 10
    assert entry["quota"]["fetches_per_run"] >= entry["quota"]["rows_per_run"]


def test_slugify_matches_proposer_convention():
    assert planner.slugify("Newsletter Links!!") == "newsletter-links"
    assert planner.slugify("") == "unnamed-job"
