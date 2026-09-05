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


@pytest.mark.parametrize("path", VALID_FILES, ids=lambda p: p.name)
def test_valid_fixture_passes(path):
    context = _records(VALID_FILES)
    record = json.loads(path.read_text(encoding="utf-8"))
    assert evidence.validate_record(record, context) == []


@pytest.mark.parametrize("path", INVALID_FILES, ids=lambda p: p.name)
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


def test_cli_runner_flags_invalid_dir(tmp_path):
    proc = subprocess.run(
        [sys.executable, str(_REPO / "cooper-core" / "evidence.py"), str(FIXTURES)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 1                    # Invalid/ records present
    assert "Invalid/" in proc.stdout or "invalid" in proc.stdout.lower()

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
