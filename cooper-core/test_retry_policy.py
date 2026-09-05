"""Tests for per-stage timeout/retry budgets (Step 15f-ii). Implements
Scripts/PDA_RetryPolicy.json — repo rule: no new policy files, implement the
existing one."""
import asyncio
import json

import pytest

import retry_policy


# ── policy lookup ────────────────────────────────────────────────────────
def test_budget_for_returns_the_declared_role_budget():
    policy = {
        "default_max_retries": 2,
        "default_timeout_seconds": 60,
        "roles": {"reviewer": {"timeout_seconds": 30, "max_retries": 1}},
    }
    budget = retry_policy.budget_for("reviewer", policy=policy)
    assert budget.timeout == 30.0
    assert budget.max_retries == 1


def test_budget_for_falls_back_to_defaults_for_an_undeclared_role():
    policy = {"default_max_retries": 2, "default_timeout_seconds": 60, "roles": {}}
    budget = retry_policy.budget_for("nonexistent", policy=policy)
    assert budget.timeout == 60.0
    assert budget.max_retries == 2


def test_budget_for_fills_a_partial_role_entry_from_defaults():
    policy = {
        "default_max_retries": 2, "default_timeout_seconds": 60,
        "roles": {"brain": {"timeout_seconds": 15}},
    }
    budget = retry_policy.budget_for("brain", policy=policy)
    assert budget.timeout == 15.0
    assert budget.max_retries == 2


def test_budget_for_never_returns_a_negative_or_zero_timeout():
    """A zero/negative timeout would mean 'fail instantly' or 'hang forever'
    depending on the client — neither is a budget."""
    policy = {
        "default_max_retries": 2, "default_timeout_seconds": 60,
        "roles": {"brain": {"timeout_seconds": 0}, "planner": {"timeout_seconds": -5}},
    }
    assert retry_policy.budget_for("brain", policy=policy).timeout > 0
    assert retry_policy.budget_for("planner", policy=policy).timeout > 0


def test_budget_for_clamps_absurd_retry_counts():
    policy = {
        "default_max_retries": 2, "default_timeout_seconds": 60,
        "roles": {"brain": {"max_retries": 999}},
    }
    assert retry_policy.budget_for("brain", policy=policy).max_retries <= retry_policy._MAX_RETRIES_CAP


def test_budget_for_fails_open_when_the_policy_file_is_missing(tmp_path):
    """An unreadable policy must not take the runtime down — it degrades to
    conservative built-in defaults, the same fail-open convention load_registry
    and existing_entry_sites already use."""
    budget = retry_policy.budget_for("brain", path=tmp_path / "absent.json")
    assert budget.timeout > 0
    assert budget.max_retries >= 0


def test_the_shipped_policy_file_declares_a_budget_for_every_routed_role():
    """Every role in PDA_ModelRouting.json makes LLM calls, so every one needs a
    budget — otherwise a stage silently inherits the default and the policy
    lies about its own coverage."""
    import model_routing
    routed = set(model_routing.load_routing()["roles"])
    declared = set(retry_policy.load_policy().get("roles", {}))
    assert routed <= declared, f"roles with no declared budget: {routed - declared}"


# ── the retry wrapper ────────────────────────────────────────────────────
def test_call_with_budget_returns_the_result_on_first_success():
    calls = []

    async def op():
        calls.append(1)
        return "ok"

    budget = retry_policy.Budget(timeout=5.0, max_retries=2)
    assert asyncio.run(retry_policy.call_with_budget(op, budget)) == "ok"
    assert len(calls) == 1


def test_call_with_budget_retries_a_transient_failure_then_succeeds():
    attempts = []

    async def flaky():
        attempts.append(1)
        if len(attempts) < 3:
            raise RuntimeError("503 upstream hiccup")
        return "recovered"

    budget = retry_policy.Budget(timeout=5.0, max_retries=2, backoff_base=0.0)
    assert asyncio.run(retry_policy.call_with_budget(flaky, budget)) == "recovered"
    assert len(attempts) == 3   # 1 initial + 2 retries


def test_call_with_budget_gives_up_after_max_retries_and_raises_the_last_error():
    attempts = []

    async def always_fails():
        attempts.append(1)
        raise RuntimeError("429 rate limited")

    budget = retry_policy.Budget(timeout=5.0, max_retries=2, backoff_base=0.0)
    with pytest.raises(RuntimeError, match="429"):
        asyncio.run(retry_policy.call_with_budget(always_fails, budget))
    assert len(attempts) == 3   # bounded: never unbounded retry


def test_call_with_budget_enforces_the_timeout_per_attempt():
    """The Step 11 failure class: a stage with no timeout hangs the whole chain."""
    async def hangs():
        await asyncio.sleep(10)

    budget = retry_policy.Budget(timeout=0.05, max_retries=0, backoff_base=0.0)
    with pytest.raises(asyncio.TimeoutError):
        asyncio.run(retry_policy.call_with_budget(hangs, budget))


def test_call_with_budget_retries_a_timeout_then_succeeds():
    attempts = []

    async def slow_then_fast():
        attempts.append(1)
        if len(attempts) == 1:
            await asyncio.sleep(10)
        return "fast"

    budget = retry_policy.Budget(timeout=0.05, max_retries=1, backoff_base=0.0)
    assert asyncio.run(retry_policy.call_with_budget(slow_then_fast, budget)) == "fast"
    assert len(attempts) == 2


def test_call_with_budget_does_not_retry_a_non_retryable_failure():
    """non_retryable_reasons in the policy exist so a governance refusal or a
    malformed request is not hammered N more times."""
    attempts = []

    async def refused():
        attempts.append(1)
        raise RuntimeError("category_policy_blocked")

    budget = retry_policy.Budget(
        timeout=5.0, max_retries=3, backoff_base=0.0,
        non_retryable=("category_policy_blocked",),
    )
    with pytest.raises(RuntimeError, match="category_policy_blocked"):
        asyncio.run(retry_policy.call_with_budget(refused, budget))
    assert len(attempts) == 1   # tried once, never retried


def test_total_wall_clock_is_bounded_by_the_budget():
    """The whole point: a stage's worst case must be computable in advance."""
    budget = retry_policy.Budget(timeout=0.05, max_retries=2, backoff_base=0.0)
    assert budget.worst_case_seconds() == pytest.approx(0.15, abs=0.01)


# ── call-site wiring (Step 15f-ii) ───────────────────────────────────────
def _budget_spy(module, seen):
    """Wrap a module's call_with_budget so a test can see which budget it used
    without changing behaviour."""
    real = retry_policy.call_with_budget

    async def spy(operation, budget):
        seen["timeout"] = budget.timeout
        seen["retries"] = budget.max_retries
        return await real(operation, budget)

    return spy


def test_archivist_extraction_runs_under_the_archivist_budget(monkeypatch):
    """A background memory write must never hold a turn open longer than its
    declared budget."""
    import archivist
    seen = {}

    async def ok(*a, **k):
        return json.dumps({"summary": "s", "tags": "t", "outcome": "success"})

    monkeypatch.setattr(archivist, "_ollama_complete", ok)
    monkeypatch.setattr(archivist.retry_policy, "call_with_budget", _budget_spy(archivist, seen))
    asyncio.run(archivist._extract(
        "msg", "out", base_url="", api_key="", model="m", backend="ollama",
    ))
    assert seen["timeout"] == retry_policy.budget_for("archivist").timeout


def test_archivist_extraction_still_fails_safe_on_a_hang(monkeypatch):
    """Fail-safe returns {} so remember() falls back to the reviewer's verdict
    rather than fabricating a success record — that must survive the budget."""
    import archivist

    async def hangs(*a, **k):
        await asyncio.sleep(30)

    monkeypatch.setattr(archivist, "_ollama_complete", hangs)
    monkeypatch.setattr(
        archivist.retry_policy, "budget_for",
        lambda role, **k: retry_policy.Budget(timeout=0.05, max_retries=0, backoff_base=0.0),
    )
    out = asyncio.run(archivist._extract(
        "msg", "out", base_url="", api_key="", model="m", backend="ollama",
    ))
    assert out == {}


def test_proposer_draft_runs_under_the_drafter_budget(monkeypatch):
    import proposer
    seen = {}

    async def ok(*a, **k):
        return json.dumps({"name": "n", "description": "d", "when_to_use": "w", "body": "b"})

    monkeypatch.setattr(proposer, "_ollama_complete", ok)
    monkeypatch.setattr(proposer.retry_policy, "call_with_budget", _budget_spy(proposer, seen))
    asyncio.run(proposer._extract_draft(
        "msg", "out", base_url="", api_key="", model="m", backend="ollama",
    ))
    assert seen["timeout"] == retry_policy.budget_for("drafter").timeout
    assert seen["retries"] == retry_policy.budget_for("drafter").max_retries


def test_planner_extraction_runs_under_the_planner_budget(monkeypatch):
    import planner
    seen = {}

    async def ok(*a, **k):
        return json.dumps({"id": "i", "csv_path": "p.csv", "rows_per_run": 1,
                           "fetches_per_run": 1, "schedule_hint": "daily"})

    monkeypatch.setattr(planner, "_ollama_complete", ok)
    monkeypatch.setattr(planner.retry_policy, "call_with_budget", _budget_spy(planner, seen))
    asyncio.run(planner._extract_fields(
        "goal", base_url="", api_key="", model="m", backend="ollama",
    ))
    assert seen["timeout"] == retry_policy.budget_for("planner").timeout


def test_data_broker_extraction_runs_under_the_drafter_budget(monkeypatch):
    import jobs
    seen = {}

    async def ok(*a, **k):
        return json.dumps({"entries": []})

    monkeypatch.setattr(jobs.retry_policy, "call_with_budget", _budget_spy(jobs, seen))
    asyncio.run(jobs.extract_pii_entries(
        "q", [{"title": "t", "url": "https://a.example", "snippet": "s"}], [],
        base_url="", api_key="", model="m", backend="ollama", complete_fn=ok,
    ))
    assert seen["timeout"] == retry_policy.budget_for("drafter").timeout
