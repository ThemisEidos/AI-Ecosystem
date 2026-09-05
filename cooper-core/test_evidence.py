"""Workflow-evidence validation — the runner the fixture set never had.

Every fixture in Tests/Fixtures/Workflow_Evidence must validate cleanly;
every fixture in .../Invalid must produce at least one error naming the rule.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

import evidence

_REPO = Path(__file__).resolve().parent.parent
FIXTURES = _REPO / "Tests" / "Fixtures" / "Workflow_Evidence"
VALID_FILES = sorted(FIXTURES.glob("*.json"))
INVALID_FILES = sorted((FIXTURES / "Invalid").glob("*.json"))


def _records(files):
    return [json.loads(f.read_text(encoding="utf-8")) for f in files]


def _fixture_params(files, corpus):
    """Parametrize over `files`, but never silently to zero cases.

    `Tests/Fixtures/` is deliberately absent from the cooper-core image
    (.dockerignore allowlist), so these globs come back empty in-container. An
    empty `parametrize` list does not skip and does not error — it collects zero
    tests and the run is green, which is how 13 tests went missing from the
    in-image suite unnoticed until 2026-09-05 (Gotchas). Emit one explicitly
    skipped case instead, so the absence is visible in the count.
    """
    if files:
        return list(files)
    return [
        pytest.param(
            None,
            marks=pytest.mark.skip(
                reason=f"{corpus} fixture corpus absent ({FIXTURES}) — expected in the "
                       "cooper-core image, where Tests/Fixtures/ is deliberately not "
                       "shipped. Skipping is honest; shipping test fixtures into a "
                       "production image to make this pass would not be."
            ),
        )
    ]


def _fixture_id(path):
    return path.name if path is not None else "corpus-absent"


@pytest.mark.parametrize("path", _fixture_params(VALID_FILES, "valid"), ids=_fixture_id)
def test_valid_fixture_passes(path):
    context = _records(VALID_FILES)
    record = json.loads(path.read_text(encoding="utf-8"))
    assert evidence.validate_record(record, context) == []


@pytest.mark.parametrize(
    "path", _fixture_params(INVALID_FILES, "invalid"), ids=_fixture_id
)
def test_invalid_fixture_fails(path):
    # union context: paired halves of a broken linkage live in Invalid/ too
    context = _records(VALID_FILES + INVALID_FILES)
    record = json.loads(path.read_text(encoding="utf-8"))
    assert evidence.validate_record(record, context) != []


def _job_completion(**overrides):
    base = {
        "workflow_id": "link-checker", "workflow_name": "CSV Link Checker",
        "execution_id": "run-abc123", "status": "completed",
        "completion_time": "2026-08-30T12:00:00Z", "workshop_id": "open",
        "workshop_name": "Open Workshop", "approval_id": "",
        "artifact_paths": ["State/LinkAudit/links.csv"],
        "review_status": "pass", "user_accepted": True,
        "job_id": "link-checker", "envelope_hash": "a" * 64, "run_id": "run-abc123",
    }
    base.update(overrides)
    return base


def test_job_linked_open_completion_valid_without_approval_id():
    errs = evidence.validate_completion(_job_completion(), [])
    assert errs == []


def test_job_linked_completion_requires_envelope_hash():
    rec = _job_completion()
    del rec["envelope_hash"]
    errs = evidence.validate_completion(rec, [])
    assert any("envelope_hash" in e for e in errs)


def test_job_linked_completion_requires_job_id_and_run_id_together():
    rec = _job_completion()
    del rec["run_id"]
    errs = evidence.validate_completion(rec, [])
    assert any("run_id" in e for e in errs)


def test_non_job_open_completion_still_requires_approval_id():
    # Regression: existing per-action-approval behavior must be untouched.
    rec = _job_completion(job_id="", envelope_hash="", run_id="")
    errs = evidence.validate_completion(rec, [])
    assert any("requires an approval_id" in e for e in errs)


def test_is_job_linked():
    assert evidence.is_job_linked(_job_completion()) is True
    assert evidence.is_job_linked(_job_completion(job_id="")) is False


def test_job_linked_completion_rejects_empty_envelope_hash():
    # Present, correct type, but empty — envelope_hash is meant to
    # cryptographically tie the record to an approved job envelope, so an
    # empty value must not silently validate.
    rec = _job_completion(envelope_hash="")
    errs = evidence.validate_completion(rec, [])
    assert any("envelope_hash" in e and "must not be empty" in e for e in errs)


@pytest.mark.skipif(
    not FIXTURES.exists(),
    reason="Tests/Fixtures/ is deliberately not shipped in the cooper-core image "
           "(.dockerignore allowlist), so this fixture-backed CLI test cannot run "
           "in-container. Skipping is honest; shipping test fixtures into a production "
           "image to make it pass would not be.",
)
def test_cli_runner_reports_negative_fixtures_as_expected_not_as_failures(tmp_path):
    """Updated 2026-09-05. This previously asserted returncode == 1 "because
    Invalid/ records are present" — pinning the very conflation that made a
    healthy corpus look broken and put "12 legacy fixtures still fail" into
    PROGRESS.md. The corpus is fine; the runner could not tell a broken record
    from one that is SUPPOSED to be broken. The contract asserted here is
    strictly stronger: the full corpus exits 0, every negative is confirmed
    still-negative, and none has quietly started validating.
    """
    proc = subprocess.run(
        [sys.executable, str(_REPO / "cooper-core" / "evidence.py"), str(FIXTURES)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, proc.stdout
    assert "invalid as expected" in proc.stdout
    assert "0 unexpectedly valid" in proc.stdout

    # a directory holding only the valid records exits 0
    clean = tmp_path / "clean"
    clean.mkdir()
    for f in VALID_FILES:
        (clean / f.name).write_text(f.read_text(encoding="utf-8"), encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, str(_REPO / "cooper-core" / "evidence.py"), str(clean)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0


def _valid_completion(**overrides):
    record = {
        "workflow_id": "wf-1", "workflow_name": "Test", "execution_id": "exec-1",
        "status": "completed", "completion_time": "2026-08-31T00:00:00.000000Z",
        "workshop_id": "open", "workshop_name": "Open Workshop", "approval_id": "",
        "artifact_paths": [], "review_status": "unknown", "user_accepted": False,
        "job_id": "test-job", "envelope_hash": "abc123", "run_id": "run-1",
    }
    record.update(overrides)
    return record


def test_verdicts_field_absent_is_valid():
    record = _valid_completion()
    assert evidence.validate_completion(record, []) == []


def test_verdicts_field_valid_when_well_shaped():
    record = _valid_completion(verdicts=[
        {"member": "openai", "verdict": "pass", "reason": "looks fine"},
        {"member": "claude", "verdict": "flag", "reason": "quota concern"},
    ])
    assert evidence.validate_completion(record, []) == []


def test_verdicts_field_rejects_empty_list():
    record = _valid_completion(verdicts=[])
    errs = evidence.validate_completion(record, [])
    assert any("verdicts" in e for e in errs)


def test_verdicts_field_rejects_missing_subfield():
    record = _valid_completion(verdicts=[{"member": "openai", "verdict": "pass"}])
    errs = evidence.validate_completion(record, [])
    assert any("reason" in e for e in errs)


def test_verdicts_field_rejects_invalid_verdict_value():
    record = _valid_completion(verdicts=[{"member": "openai", "verdict": "maybe", "reason": "x"}])
    errs = evidence.validate_completion(record, [])
    assert any("verdict" in e for e in errs)


def test_verdicts_field_hygiene_checks_reason_text():
    record = _valid_completion(verdicts=[
        {"member": "openai", "verdict": "flag", "reason": "found api_key=sk-abc123 in output"}
    ])
    errs = evidence.validate_completion(record, [])
    assert any("hygiene" in e for e in errs)


# ── legacy pre-approval-gate records (owner decision 2026-09-05) ──────────
def _v1_completion(**overrides):
    """A real v1-era (June 2026) completion: the approval gate did not exist
    yet, so no approval_id could ever have been cited."""
    return {
        "workflow_id": "WF-001", "workflow_name": "Research Summary",
        "execution_id": "20260623T040423552Z", "status": "pass",
        "completion_time": "2026-06-23T04:04:23.5529784Z",
        "workshop_id": "open", "workshop_name": "Open Workshop",
        "approval_id": "", "artifact_paths": [],
        "review_status": "unknown", "user_accepted": False,
        "notes": "WF-001 research summary completed; review pending.",
        **overrides,
    }


def test_open_completion_without_approval_id_is_still_invalid_by_default():
    """The approval requirement must stay enforced for ordinary records —
    the exemption below must not become a general escape hatch."""
    errs = evidence.validate_completion(_v1_completion(), [])
    assert any("approval_id" in e for e in errs)


def test_legacy_pre_approval_gate_record_is_exempt_from_the_approval_requirement():
    """Records predating the approval gate cannot cite an approval that never
    existed. Marking them truthfully is the honest repair — deleting real audit
    history to make a validator pass would spend M7 for convenience."""
    record = _v1_completion(legacy_pre_approval_gate=True)
    assert evidence.validate_completion(record, []) == []


def test_legacy_flag_does_not_waive_any_other_rule():
    """The exemption is narrow: it waives the approval linkage only."""
    record = _v1_completion(legacy_pre_approval_gate=True, notes="api_key=abc123")
    errs = evidence.validate_completion(record, [])
    assert any("sensitive" in e for e in errs)


def test_legacy_flag_does_not_waive_schema_requirements():
    record = _v1_completion(legacy_pre_approval_gate=True)
    del record["execution_id"]
    errs = evidence.validate_completion(record, [])
    assert any("execution_id" in e for e in errs)


# --- the guard itself (2026-09-05) -------------------------------------------
# These must run everywhere, including in-container where the corpus is absent —
# they are the reason an empty corpus can no longer collect to zero unnoticed.

def test_fixture_params_passes_through_a_real_corpus():
    files = [Path("a.json"), Path("b.json")]
    assert _fixture_params(files, "valid") == files


def test_fixture_params_emits_one_skipped_case_when_corpus_absent():
    params = _fixture_params([], "valid")
    assert len(params) == 1, "an absent corpus must still collect exactly one case"
    marks = params[0].marks
    assert any(m.name == "skip" for m in marks), "the stand-in case must be skipped"


def test_fixture_params_skip_reason_names_the_corpus_and_the_path():
    reason = _fixture_params([], "invalid")[0].marks[0].kwargs["reason"]
    assert "invalid" in reason
    assert str(FIXTURES) in reason


def test_fixture_id_handles_both_real_paths_and_the_stand_in():
    assert _fixture_id(Path("/x/WF-003.json")) == "WF-003.json"
    assert _fixture_id(None) == "corpus-absent"


# --- negative fixtures are expectations, not failures (2026-09-05) ------------
# evidence.py's directory runner rglob'd everything, so a corpus containing
# deliberate negative fixtures under Invalid/ reported them as failures and
# exited 1. That is not a broken corpus -- it is the runner unable to tell
# "this record is broken" from "this record is SUPPOSED to be broken". The
# misreading was carried in PROGRESS.md as "12 legacy fixtures still fail".
# The runner now asserts negatives ARE negative, which additionally catches a
# real regression: a governance rule relaxed until a negative fixture starts
# passing.

def _write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def _valid_completion(**overrides):
    return {**_job_completion(), **overrides}


def test_runner_treats_invalid_subdir_as_expected_failures(tmp_path, capsys):
    _write(tmp_path / "good.json", _valid_completion())
    _write(tmp_path / "Invalid" / "bad.json", _valid_completion(envelope_hash=""))
    rc = evidence.main(["evidence.py", str(tmp_path)])
    out = capsys.readouterr().out
    assert rc == 0, out
    assert "1/1 records valid" in out
    assert "1 negative fixture" in out


def test_runner_fails_when_a_negative_fixture_unexpectedly_validates(tmp_path, capsys):
    # The regression this buys: relax a governance rule until a fixture that
    # must fail starts passing, and the runner says so instead of going green.
    _write(tmp_path / "Invalid" / "not-actually-invalid.json", _valid_completion())
    rc = evidence.main(["evidence.py", str(tmp_path)])
    out = capsys.readouterr().out
    assert rc == 1
    assert "unexpectedly valid" in out.lower()


def test_runner_still_fails_on_a_genuinely_invalid_positive_record(tmp_path, capsys):
    _write(tmp_path / "broken.json", _valid_completion(envelope_hash=""))
    rc = evidence.main(["evidence.py", str(tmp_path)])
    assert rc == 1
    assert "[FAIL]" in capsys.readouterr().out


def test_runner_on_the_real_fixture_corpus_is_clean(capsys):
    # The concrete claim the PROGRESS.md note got wrong.
    if not FIXTURES.exists():
        pytest.skip("fixture corpus not shipped in the cooper-core image")
    rc = evidence.main(["evidence.py", str(FIXTURES)])
    out = capsys.readouterr().out
    assert rc == 0, out
    assert "12 negative fixture" in out
