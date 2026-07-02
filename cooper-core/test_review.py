import asyncio

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
