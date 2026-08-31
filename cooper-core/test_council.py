import asyncio
import time

import council
import review


JOB = {
    "id": "test-job",
    "workshop": "open",
    "steps": ["noop"],
    "read_scope": [],
    "write_scope": [],
    "quota": {"rows_per_run": 1},
    "permission_level": 3,
    "approved": False,
}


def test_needs_council_tier_true_for_l4_plus():
    assert council.needs_council_tier({**JOB, "permission_level": 4, "write_scope": []})


def test_needs_council_tier_true_for_file_writing_below_l4():
    assert council.needs_council_tier({**JOB, "permission_level": 3, "write_scope": ["a.csv"]})


def test_needs_council_tier_false_for_low_level_no_write():
    assert not council.needs_council_tier({**JOB, "permission_level": 3, "write_scope": []})


def test_has_objection_true_if_any_member_flags():
    verdicts = [
        council.CouncilVerdict(member="a", verdict="pass", reason=""),
        council.CouncilVerdict(member="b", verdict="flag", reason="too broad"),
    ]
    assert council.has_objection(verdicts)


def test_has_objection_false_if_all_pass():
    verdicts = [council.CouncilVerdict(member="a", verdict="pass", reason="")]
    assert not council.has_objection(verdicts)


def test_verdicts_to_dicts_shape():
    verdicts = [council.CouncilVerdict(member="a", verdict="flag", reason="why")]
    assert council.verdicts_to_dicts(verdicts) == [
        {"member": "a", "verdict": "flag", "reason": "why"}
    ]


def test_member_verdict_fails_open_and_logs(monkeypatch, capsys):
    async def boom(*a, **k):
        raise RuntimeError("network down")

    monkeypatch.setattr(council, "_ollama_complete", boom)
    result = asyncio.run(council._member_verdict(
        "system", "user", "some-model",
        base_url="http://x", api_key="", backend="ollama", temperature=0.0,
    ))
    assert result.verdict == "pass"
    assert "fail-open" in result.reason
    assert "fail-open" in capsys.readouterr().out


def test_critique_envelope_runs_each_roster_member(monkeypatch):
    calls = []

    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        calls.append(member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake)
    verdicts = asyncio.run(council.critique_envelope(
        JOB, "open", base_url="http://x", api_key="", backend="openai",
        roster=["m1", "m2", "m3"],
    ))
    assert sorted(calls) == ["m1", "m2", "m3"]
    assert [v.member for v in verdicts] == ["m1", "m2", "m3"]


def test_critique_envelope_surfaces_objection_from_seeded_flaw(monkeypatch):
    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        # simulate one member catching an over-broad write_scope mentioned in the envelope
        verdict = "flag" if "write_scope" in user_msg and "/" in user_msg else "pass"
        return council.CouncilVerdict(member=member, verdict=verdict, reason="over-broad write_scope")

    monkeypatch.setattr(council, "_member_verdict", fake)
    flawed = {**JOB, "write_scope": ["/"]}
    verdicts = asyncio.run(council.critique_envelope(
        flawed, "open", base_url="http://x", api_key="", backend="openai",
        roster=["m1", "m2", "m3"],
    ))
    assert council.has_objection(verdicts)


def test_final_review_uses_council_tier_for_file_writing_job(monkeypatch):
    calls = []

    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        calls.append(member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake)
    job = {**JOB, "permission_level": 3, "write_scope": ["a.csv"]}
    result = asyncio.run(council.final_review(
        job, "open", "job run: test-job", "ran fine",
        base_url="http://x", api_key="", backend="openai", reviewer_model="rev",
        roster=["m1", "m2", "m3"],
    ))
    assert len(result) == 3
    assert {r["member"] for r in result} == {"m1", "m2", "m3"}
    assert all(r["verdict"] == "pass" for r in result)


def test_final_review_uses_single_reviewer_for_low_tier_job(monkeypatch):
    async def fake_review(tool, message, raw_output, *, base_url, api_key, model, backend):
        return review.ReviewVerdict(verdict="pass", reason="looks fine")

    monkeypatch.setattr(review, "review", fake_review)
    job = {**JOB, "permission_level": 3, "write_scope": []}
    result = asyncio.run(council.final_review(
        job, "open", "job run: test-job", "ran fine",
        base_url="http://x", api_key="", backend="openai", reviewer_model="rev",
    ))
    assert result == [{"member": "rev", "verdict": "pass", "reason": "looks fine"}]


def test_critique_envelope_runs_concurrently(monkeypatch):
    """Prove that _member_verdict calls run concurrently via asyncio.gather, not sequentially.

    With 3 members each sleeping 0.05s: sequential would take ~0.15s, concurrent takes ~0.05s.
    Assert total time is under 0.1s (2x one member's delay) to verify concurrency.
    """
    delay_per_member = 0.05

    async def fake_with_delay(system, user_msg, member, *, base_url, api_key, backend, temperature):
        await asyncio.sleep(delay_per_member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake_with_delay)
    start = time.monotonic()
    verdicts = asyncio.run(council.critique_envelope(
        JOB, "open", base_url="http://x", api_key="", backend="openai",
        roster=["m1", "m2", "m3"],
    ))
    elapsed = time.monotonic() - start

    # 3 members * 0.05s each = 0.15s if sequential
    # Should be ~0.05s if concurrent (one member's delay)
    # Assert under 0.1s (2x one member) to verify concurrency
    assert elapsed < 0.1, f"Expected concurrent ~0.05s, got {elapsed:.3f}s (may indicate sequential execution)"
    assert len(verdicts) == 3


def test_final_review_runs_council_concurrently(monkeypatch):
    """Prove that final_review's council-tier calls run concurrently, not sequentially."""
    delay_per_member = 0.05

    async def fake_with_delay(system, user_msg, member, *, base_url, api_key, backend, temperature):
        await asyncio.sleep(delay_per_member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake_with_delay)
    job = {**JOB, "permission_level": 3, "write_scope": ["a.csv"]}
    start = time.monotonic()
    result = asyncio.run(council.final_review(
        job, "open", "job run: test-job", "ran fine",
        base_url="http://x", api_key="", backend="openai", reviewer_model="rev",
        roster=["m1", "m2", "m3"],
    ))
    elapsed = time.monotonic() - start

    # Should be ~0.05s if concurrent, ~0.15s if sequential
    assert elapsed < 0.1, f"Expected concurrent ~0.05s, got {elapsed:.3f}s (may indicate sequential execution)"
    assert len(result) == 3
