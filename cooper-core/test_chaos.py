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
import os
import sqlite3
from pathlib import Path

import pytest

import archivist
import evidence
import executor
import jobs
import retry_policy
import review




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








@pytest.mark.skipif(
    os.geteuid() == 0,
    reason="root ignores file permission bits, so this fault cannot be injected as root "
           "(the cooper-core container runs as root; this asserts real behaviour for the "
           "non-root case rather than pretending to cover it)",
)
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
