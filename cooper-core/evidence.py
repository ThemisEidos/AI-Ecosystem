"""
Workflow-evidence validation (Tests/Fixtures/Workflow_Evidence rule set).

Two record shapes, paired by approval_id:
  completion  — a workflow run's outcome + artifact paths (has execution_id)
  approval    — the approval lifecycle that authorized it (has requested_time)

Rules encoded by the fixture set:
  linkage      — an Open-workshop completion must reference a known approval;
                 Private may run without one (approval_id "")
  consistency  — linked records must agree on workflow_id, and a completion
                 can only exist against a 'completed' approval; a 'completed'
                 approval with no completion referencing it is an orphan
  boundaries   — Category 2 area ("Restricted DMZ Workspace/") is forbidden to
                 Open artifacts and mandatory for Private artifacts (no vault
                 paths, external URLs, or cloud-drive paths from Private)
  hygiene      — no sensitive markers (api keys, PII, secrets) in any field

CLI runner: `python evidence.py <dir>` validates every *.json under <dir>
recursively; exit 1 if any record fails.
"""
import json
import re
import sys
from pathlib import Path
from typing import List, Optional

_COMPLETION_REQUIRED = {
    "workflow_id": str, "workflow_name": str, "execution_id": str,
    "status": str, "completion_time": str, "workshop_id": str,
    "workshop_name": str, "approval_id": str, "artifact_paths": list,
    "review_status": str, "user_accepted": bool,
}
_APPROVAL_REQUIRED = {
    "approval_id": str, "workflow_id": str, "status": str,
    "requested_time": str, "reason": str,
}
_JOB_LINKAGE_REQUIRED = {"job_id": str, "envelope_hash": str, "run_id": str}


def is_job_linked(record: dict) -> bool:
    return bool(record.get("job_id"))


_RESTRICTED_PREFIX = "Restricted DMZ Workspace/"
_SENSITIVE_RE = re.compile(
    r"api[_-]?key|password|\bsecret\b|\bPII\b|access[_-]?token", re.IGNORECASE
)
_URL_RE = re.compile(r"^[a-z][a-z0-9+.-]*://", re.IGNORECASE)
_CLOUD_DRIVE_RE = re.compile(r"proton\s*drive|onedrive|dropbox|google\s*drive", re.IGNORECASE)


def is_completion(record: dict) -> bool:
    return "execution_id" in record


def _schema_errors(record: dict, required: dict) -> List[str]:
    errs = []
    for field, typ in required.items():
        if field not in record:
            errs.append(f"schema: missing field '{field}'")
        elif not isinstance(record[field], typ):
            errs.append(f"schema: field '{field}' is not {typ.__name__}")
    return errs


def _sensitive_errors(record: dict) -> List[str]:
    for key, value in record.items():
        if isinstance(value, str) and _SENSITIVE_RE.search(value):
            return [f"hygiene: sensitive marker in field '{key}'"]
    return []


def _find_approval(approval_id: str, context: List[dict]) -> Optional[dict]:
    for r in context:
        if not is_completion(r) and r.get("approval_id") == approval_id:
            return r
    return None


def validate_completion(record: dict, context: List[dict]) -> List[str]:
    errs = _schema_errors(record, _COMPLETION_REQUIRED)
    if errs:
        return errs
    errs += _sensitive_errors(record)

    workshop = record["workshop_id"]
    approval_id = record["approval_id"]
    job_linked = is_job_linked(record)
    if job_linked:
        errs += _schema_errors(record, _JOB_LINKAGE_REQUIRED)
        for field in _JOB_LINKAGE_REQUIRED:
            if field in record and not record[field]:
                errs.append(f"schema: field '{field}' must not be empty for a job-linked completion")
    if approval_id:
        approval = _find_approval(approval_id, context)
        if approval is None:
            errs.append(f"linkage: approval '{approval_id}' not found")
        else:
            if approval.get("workflow_id") != record["workflow_id"]:
                errs.append(
                    f"consistency: approval '{approval_id}' is for workflow "
                    f"'{approval.get('workflow_id')}', not '{record['workflow_id']}'"
                )
            if approval.get("status") != "completed":
                errs.append(
                    f"consistency: approval '{approval_id}' status is "
                    f"'{approval.get('status')}' — a completion may only cite a completed approval"
                )
    elif workshop == "open" and not job_linked:
        errs.append("linkage: open-workshop completion requires an approval_id")

    for path in record["artifact_paths"]:
        if workshop == "open" and path.startswith(_RESTRICTED_PREFIX):
            errs.append(f"boundary: open artifact inside Category 2 area: '{path}'")
        if workshop == "private":
            if _URL_RE.match(path):
                errs.append(f"boundary: private artifact points at an external URL: '{path}'")
            elif _CLOUD_DRIVE_RE.search(path):
                errs.append(f"boundary: private artifact on a cloud drive: '{path}'")
            elif not path.startswith(_RESTRICTED_PREFIX):
                errs.append(
                    f"boundary: private artifact outside '{_RESTRICTED_PREFIX}': '{path}'"
                )
    return errs


def validate_approval(record: dict, context: List[dict]) -> List[str]:
    errs = _schema_errors(record, _APPROVAL_REQUIRED)
    if errs:
        return errs
    errs += _sensitive_errors(record)

    approval_id = record["approval_id"]
    referencing = [
        r for r in context if is_completion(r) and r.get("approval_id") == approval_id
    ]
    for c in referencing:
        if c.get("workflow_id") != record["workflow_id"]:
            errs.append(
                f"consistency: completion '{c.get('execution_id')}' cites this approval "
                f"but belongs to workflow '{c.get('workflow_id')}', not '{record['workflow_id']}'"
            )
    if record["status"] == "completed" and not referencing:
        errs.append("consistency: completed approval with no completion citing it (orphan)")
    if record["status"] != "completed" and referencing:
        errs.append(
            f"consistency: approval status is '{record['status']}' yet "
            f"{len(referencing)} completion record(s) cite it"
        )
    return errs


def validate_record(record: dict, context: List[dict]) -> List[str]:
    if is_completion(record):
        return validate_completion(record, context)
    return validate_approval(record, context)


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        print("usage: python evidence.py <evidence-dir>")
        return 2
    root = Path(argv[1])
    files = sorted(root.rglob("*.json"))
    if not files:
        print(f"no *.json records under {root}")
        return 2
    records, by_file = [], {}
    for f in files:
        try:
            by_file[f] = json.loads(f.read_text(encoding="utf-8"))
            records.append(by_file[f])
        except (OSError, json.JSONDecodeError) as exc:
            by_file[f] = exc
    failed = 0
    for f in files:
        rec = by_file[f]
        errs = (
            [f"unreadable: {rec}"] if not isinstance(rec, dict)
            else validate_record(rec, records)
        )
        rel = f.relative_to(root)
        if errs:
            failed += 1
            print(f"[FAIL] {rel}")
            for e in errs:
                print(f"       - {e}")
        else:
            print(f"[ ok ] {rel}")
    print(f"\n{len(files) - failed}/{len(files)} records valid")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
