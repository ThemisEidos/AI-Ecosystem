import asyncio
import json

import review


TOOL = {"name": "PowerShell Private Runner"}


def _run(coro):
    return asyncio.run(coro)


def test_review_fails_open_and_logs_on_llm_error(monkeypatch, capsys):
    async def boom(*args, **kwargs):
        raise RuntimeError("llm down")

    monkeypatch.setattr(review, "_ollama_complete", boom)
    verdict = _run(review.review(
        TOOL, "run x", "[ok] output",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert verdict.verdict == "pass"
    assert "fail-open" in verdict.reason
    assert "reviewer fail-open" in capsys.readouterr().out


def test_review_normalizes_invalid_verdict(monkeypatch):
    async def weird(*args, **kwargs):
        return '{"verdict":"banana","reason":"x"}'

    monkeypatch.setattr(review, "_ollama_complete", weird)
    verdict = _run(review.review(
        TOOL, "run x", "output",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert verdict.verdict == "pass"


def test_review_passes_through_flag(monkeypatch):
    async def flagit(*args, **kwargs):
        return '{"verdict":"flag","reason":"non-zero exit"}'

    monkeypatch.setattr(review, "_ollama_complete", flagit)
    verdict = _run(review.review(
        TOOL, "run x", "[exit 1] err",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert verdict.verdict == "flag"


def test_govern_prefixes_flagged_output():
    v = review.ReviewVerdict(verdict="flag", reason="timeout")
    out = review.govern("raw", v)
    assert out.startswith("[Reviewer flagged this result — timeout]")
    assert out.endswith("raw")


def test_govern_returns_clean_output_untouched():
    v = review.ReviewVerdict(verdict="pass", reason="")
    assert review.govern("raw", v) == "raw"


# ── per-stage budgets (Step 15f-ii) ──────────────────────────────────────
def test_review_fails_open_within_its_budget_instead_of_hanging(monkeypatch):
    """The Step 11 failure class: before budgets, a wedged backend held the turn
    for the client's full hardcoded timeout. Now it fails open at the budget."""
    import retry_policy

    async def hangs(*a, **k):
        await asyncio.sleep(30)

    monkeypatch.setattr(review, "_ollama_complete", hangs)
    budget = retry_policy.Budget(timeout=0.05, max_retries=0, backoff_base=0.0)

    verdict = asyncio.run(review.review(
        {"name": "t"}, "do a thing", "output",
        base_url="", api_key="", model="m", backend="ollama", budget=budget,
    ))
    assert verdict.verdict == "pass"          # fail-open preserved
    assert "fail-open" in verdict.reason.lower()


def test_review_retries_a_transient_backend_failure_and_returns_the_real_verdict(monkeypatch):
    import retry_policy
    attempts = []

    async def flaky(*a, **k):
        attempts.append(1)
        if len(attempts) == 1:
            raise RuntimeError("503 upstream hiccup")
        return json.dumps({"verdict": "flag", "reason": "looks wrong"})

    monkeypatch.setattr(review, "_ollama_complete", flaky)
    budget = retry_policy.Budget(timeout=5.0, max_retries=1, backoff_base=0.0)

    verdict = asyncio.run(review.review(
        {"name": "t"}, "do a thing", "output",
        base_url="", api_key="", model="m", backend="ollama", budget=budget,
    ))
    assert len(attempts) == 2
    assert verdict.verdict == "flag"          # the retry's real verdict, not fail-open
    assert verdict.reason == "looks wrong"


def test_review_without_an_explicit_budget_uses_the_reviewer_role_policy(monkeypatch):
    """Production callers pass no budget; the reviewer role's declared budget applies."""
    import retry_policy
    seen = {}

    async def ok(*a, **k):
        return json.dumps({"verdict": "pass", "reason": "fine"})

    real = retry_policy.call_with_budget

    async def spy(operation, budget):
        seen["timeout"] = budget.timeout
        seen["retries"] = budget.max_retries
        return await real(operation, budget)

    monkeypatch.setattr(review, "_ollama_complete", ok)
    monkeypatch.setattr(review.retry_policy, "call_with_budget", spy)

    asyncio.run(review.review(
        {"name": "t"}, "m", "o",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    expected = retry_policy.budget_for("reviewer")
    assert seen["timeout"] == expected.timeout
    assert seen["retries"] == expected.max_retries
