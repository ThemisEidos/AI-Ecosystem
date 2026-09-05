"""Chaos tests (Step 15f-iii): inject real faults at component boundaries and
assert COOPER degrades honestly rather than hanging, crashing, or — worst —
reporting success it did not achieve.

These are regression guards for robustness that largely already exists. Where a
test documents existing behaviour rather than driving new behaviour, it has been
mutation-checked: the protection was removed and the test confirmed to fail. A
chaos test that cannot fail is theatre.

Spec: Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md, 15f(iii).
"""
import asyncio
import json
import sqlite3
from pathlib import Path

import pytest

import archivist
import evidence
import executor
import jobs
import retry_policy
import review


# ── backend killed mid-dispatch ──────────────────────────────────────────
def test_backend_death_mid_job_yields_an_honest_failure_and_valid_evidence(tmp_path, monkeypatch):
    """The 15f DoD: a mid-dispatch backend kill must produce an honest error AND
    an evidence record — a run nobody can audit is worse than a run that failed."""
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    queries = tmp_path / "Config" / "q.json"
    queries.parent.mkdir(parents=True)
    queries.write_text(json.dumps({"queries": ["broker list"], "next_index": 0}))
    monkeypatch.setattr(jobs, "_QUERIES_PATH", queries)

    async def search_ok(query, max_results=10):
        return [{"title": "t", "url": "https://a.example", "snippet": "s"}]

    async def backend_dies(*a, **k):
        raise ConnectionError("connection reset by peer")

    async def review_ok(*a, **k):
        return [{"member": "r", "verdict": "pass", "reason": "ok"}]

    monkeypatch.setattr(jobs.executor, "_run_web_search", search_ok)
    monkeypatch.setattr(jobs, "_ollama_complete", backend_dies)
    monkeypatch.setattr(jobs.council, "final_review", review_ok)

    entry = {
        "id": "chaos-job", "job_type": "pii_research", "workshop": "open",
        "schedule_hint": "daily", "steps": ["web_search"],
        "read_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
        "write_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
        "quota": {"entries_per_run": 5}, "permission_level": 3, "approved": True,
    }
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [entry]})

    conn = sqlite3.connect(":memory:")
    archivist.init_db(conn)
    result = asyncio.run(jobs.run_job(
        "chaos-job", conn, base_url="", api_key="", backend="ollama",
        workshop="open", reviewer_model="m",
    ))

    assert result["status"] == "failed"                       # honest, not "completed"
    assert "connection reset" in result["reason"]             # the real cause, not a euphemism
    record = json.loads(Path(result["evidence_path"]).read_text())
    assert record["status"] == "failed"
    assert evidence.validate_completion(record, []) == []     # auditable despite failing


def test_backend_death_does_not_hang_the_reviewer(monkeypatch):
    """A wedged backend must be bounded by the budget, not by the client timeout."""
    async def never_returns(*a, **k):
        await asyncio.sleep(60)

    monkeypatch.setattr(review, "_ollama_complete", never_returns)
    budget = retry_policy.Budget(timeout=0.05, max_retries=0, backoff_base=0.0)

    async def timed():
        loop = asyncio.get_running_loop()
        t0 = loop.time()
        v = await review.review({"name": "t"}, "m", "o", base_url="", api_key="",
                                model="m", backend="ollama", budget=budget)
        return v, loop.time() - t0

    verdict, elapsed = asyncio.run(timed())
    assert elapsed < 1.0                                      # bounded, not 60s
    assert verdict.verdict == "pass" and "fail-open" in verdict.reason.lower()


# ── malformed tool / model output ────────────────────────────────────────
@pytest.mark.parametrize("garbage", [
    "", "   ", "not json at all", "{", '{"unclosed": ', "[]", "null",
    '{"verdict": "banana", "reason": "x"}',
])
def test_malformed_reviewer_output_never_crashes_a_turn(garbage, monkeypatch):
    """Every one of these has to degrade to a verdict, not an exception."""
    async def junk(*a, **k):
        return garbage

    monkeypatch.setattr(review, "_ollama_complete", junk)
    v = asyncio.run(review.review({"name": "t"}, "m", "o", base_url="", api_key="",
                                  model="m", backend="ollama"))
    assert v.verdict in ("pass", "flag")


@pytest.mark.parametrize("garbage", ["", "not json", "{", "null", '{"entries": "notalist"}'])
def test_malformed_extraction_output_raises_a_typed_error_not_a_crash(garbage):
    """A malformed model response must surface as JobError so run_job can write
    a failure record — never as a raw exception escaping to a 500."""
    async def junk(messages):
        return garbage

    try:
        out = asyncio.run(jobs.extract_pii_entries(
            "q", [{"title": "t", "url": "https://a.example", "snippet": "s"}], [],
            base_url="", api_key="", model="m", backend="ollama", complete_fn=junk,
        ))
        assert out == []          # tolerated shapes yield nothing, never junk entries
    except jobs.JobError:
        pass                      # or a typed error — both are honest


def test_hostile_entry_shapes_are_dropped_rather_than_written(monkeypatch):
    """Malformed/hostile extraction output must not reach the vault note."""
    async def hostile(messages):
        return json.dumps({"entries": [
            None, "a string", 42, {}, {"site": ""},
            {"site": "ok", "what_it_collects": "x"},          # missing source_url
            {"site": "Good", "what_it_collects": "x", "source_url": "https://g.example"},
        ]})

    out = asyncio.run(jobs.extract_pii_entries(
        "q", [{"title": "t", "url": "https://g.example", "snippet": "s"}], [],
        base_url="", api_key="", model="m", backend="ollama", complete_fn=hostile,
    ))
    assert [e["site"] for e in out] == ["Good"]


# ── disk full / unwritable filesystem ────────────────────────────────────
def test_disk_full_on_a_job_write_is_queued_not_crashed(tmp_path, monkeypatch):
    """ENOSPC mid-write must land in the exception queue for human review, and
    the run must still produce a valid evidence record."""
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    queries = tmp_path / "Config" / "q.json"
    queries.parent.mkdir(parents=True)
    queries.write_text(json.dumps({"queries": ["broker list"], "next_index": 0}))
    monkeypatch.setattr(jobs, "_QUERIES_PATH", queries)

    async def search_ok(query, max_results=10):
        return [{"title": "t", "url": "https://a.example", "snippet": "s"}]

    async def extract_ok(query, results, existing, **kw):
        return [{"site": "Acme", "what_it_collects": "emails",
                 "source_url": "https://a.example"}]

    async def review_ok(*a, **k):
        return [{"member": "r", "verdict": "pass", "reason": "ok"}]

    async def disk_full(*a, **k):
        raise executor.ExecutionError("file_edit: write failed unexpectedly — [Errno 28] No space left on device")

    monkeypatch.setattr(jobs.executor, "_run_web_search", search_ok)
    monkeypatch.setattr(jobs, "extract_pii_entries", extract_ok)
    monkeypatch.setattr(jobs.council, "final_review", review_ok)
    monkeypatch.setattr(jobs.executor, "_run_file_edit", disk_full)

    entry = {
        "id": "chaos-disk", "job_type": "pii_research", "workshop": "open",
        "schedule_hint": "daily", "steps": ["web_search"],
        "read_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
        "write_scope": ["Obsidian Vault/02_Projects/opt-out/Data-Brokers.md"],
        "quota": {"entries_per_run": 5}, "permission_level": 3, "approved": True,
    }
    entry["envelope_hash"] = jobs.compute_envelope_hash(entry)
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [entry]})

    conn = sqlite3.connect(":memory:")
    archivist.init_db(conn)
    result = asyncio.run(jobs.run_job(
        "chaos-disk", conn, base_url="", api_key="", backend="ollama",
        workshop="open", reviewer_model="m",
    ))

    assert result["status"] == "completed"        # a refused write is a completed, reviewable run
    assert result["exceptions_raised"] == 1
    assert result["entries_added"] == 0           # honest: nothing landed
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1 and "No space left" in pending[0]["reason"]
    record = json.loads(Path(result["evidence_path"]).read_text())
    assert record["artifact_paths"] == []         # must not claim an artifact it never wrote
    assert evidence.validate_completion(record, []) == []


def test_unwritable_destination_surfaces_as_execution_error(tmp_path, monkeypatch):
    """A read-only filesystem must raise ExecutionError, not silently no-op."""
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    target = tmp_path / "State" / "locked.md"
    target.parent.mkdir(parents=True)
    target.write_text("original", encoding="utf-8")
    target.chmod(0o444)                 # file itself read-only
    try:
        with pytest.raises(executor.ExecutionError):
            asyncio.run(executor._run_file_edit(
                {"name": "t"}, "m", "open",
                {"filename": "State/locked.md", "content": "new",
                 "write_scope": ["State/locked.md"]},
            ))
    finally:
        target.chmod(0o600)             # always restore so tmp cleanup works
    assert target.read_text() == "original"      # unchanged
