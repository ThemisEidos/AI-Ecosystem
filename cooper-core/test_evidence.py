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
