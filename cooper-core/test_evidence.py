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
