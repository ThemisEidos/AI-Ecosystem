"""
COOPER Jobs — envelope loading, hash verification, exception queue (Step 14b).

Jobs skip the chat classifier entirely: a job envelope in Config/jobs_registry.yaml
names its steps directly, and a later step (Task 6) has main.py's
POST /jobs/run/{job_id} call straight into run_job(). This module is the pure
plumbing that sits under that: load the registry (fail closed, same pattern as
skills.py's load_manifest), hash-pin an envelope's content so any edit after
approval voids the approval (same hash-then-compare pattern as skills.py's
compute_content_hash/skill_status), and read/write the job_exceptions table
(Step 14b Task 1's addition to archivist.py's schema) for actions a running job
proposed but could not take on its own authority.

Spec: Docs/superpowers/specs/2026-08-30-step-14b-jobs-harness-design.md.
"""
import csv
import datetime
import hashlib
import json
import sqlite3
import time
from pathlib import Path
from typing import List, Optional

import httpx
import yaml

_REPO_ROOT = Path(__file__).resolve().parent.parent
_REGISTRY_PATH = _REPO_ROOT / "Config" / "jobs_registry.yaml"

# url_verify: short, bounded — a job step must fail fast, not hang a run.
_URL_VERIFY_TIMEOUT = 5.0

# Hashing the hash would be circular, and 'approved' must be flippable by the
# approval step without changing the hash it gates.
_HASH_EXCLUDED_KEYS = {"envelope_hash", "approved"}


class JobError(Exception):
    pass


class QuotaExceeded(JobError):
    pass


def load_registry(path: Optional[Path] = None) -> dict:
    """Read Config/jobs_registry.yaml. FAIL CLOSED: any read/parse error, or a
    file that doesn't parse to {"jobs": [...]}, returns {"jobs": []} — zero jobs
    load. Matches skills.py's load_manifest fail-closed pattern."""
    p = path or _REGISTRY_PATH
    try:
        data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        print(f"  [!!] jobs registry unreadable — zero jobs loaded (fail closed): {exc}")
        return {"jobs": []}
    if not isinstance(data, dict) or not isinstance(data.get("jobs"), list):
        print("  [!!] jobs registry malformed ('jobs' must be a list) — zero jobs loaded (fail closed)")
        return {"jobs": []}
    return data


def get_job(job_id: str, registry: Optional[dict] = None) -> Optional[dict]:
    """Look up one job entry by id. Loads the registry if none is given."""
    reg = registry if registry is not None else load_registry()
    for job in reg.get("jobs", []):
        if job.get("id") == job_id:
            return job
    return None


def compute_envelope_hash(job_entry: dict) -> str:
    """SHA-256 hex digest over the job entry's canonical JSON, excluding the
    entry's own envelope_hash and approved keys (spec: any edit to an approved
    job's envelope voids its approval; approval status itself must not affect
    the hash it gates)."""
    canonical = {k: v for k, v in job_entry.items() if k not in _HASH_EXCLUDED_KEYS}
    payload = json.dumps(canonical, sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def verify_job(job_entry: dict) -> Optional[str]:
    """Governance gate a run_job() call must pass before doing anything. Returns
    None when the job is approved and its stored envelope_hash still matches the
    current entry; otherwise a human-readable reason it must not run."""
    if not job_entry.get("approved"):
        return "not approved"
    if job_entry.get("envelope_hash") != compute_envelope_hash(job_entry):
        return "hash mismatch — envelope was edited after approval"
    return None


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def enqueue_exception(
    conn: sqlite3.Connection,
    job_id: str,
    run_id: str,
    proposed_action: str,
    reason: str,
) -> None:
    """Record an action a job run wanted to take but could not authorize itself
    (e.g. outside its write_scope) for human review."""
    from archivist import _DB_LOCK

    with _DB_LOCK:
        conn.execute(
            "INSERT INTO job_exceptions (job_id, run_id, proposed_action, reason, status, created_at) "
            "VALUES (?, ?, ?, ?, 'pending', ?)",
            (job_id, run_id, proposed_action, reason, _now()),
        )
        conn.commit()


def list_exceptions(conn: sqlite3.Connection, status: str = "pending") -> List[dict]:
    """All job_exceptions rows in a given status, oldest first."""
    from archivist import _DB_LOCK

    with _DB_LOCK:
        cur = conn.execute(
            "SELECT id, job_id, run_id, proposed_action, reason, status, created_at "
            "FROM job_exceptions WHERE status = ? ORDER BY created_at",
            (status,),
        )
        rows = cur.fetchall()
        columns = [c[0] for c in cur.description]
    return [dict(zip(columns, row)) for row in rows]


def resolve_exception(conn: sqlite3.Connection, exception_id: int, status: str) -> None:
    """Human review outcome for one exception (e.g. 'approved', 'dismissed')."""
    from archivist import _DB_LOCK

    with _DB_LOCK:
        conn.execute(
            "UPDATE job_exceptions SET status = ? WHERE id = ?", (status, exception_id)
        )
        conn.commit()


def _is_sha256_hex(value: str) -> bool:
    """True if value looks like a sha256 hex digest — the heuristic csv_next_rows
    uses to tell a prior content hash (stashed in the CSV's own 'status' column)
    apart from a plain status word like 'ok' or 'unreachable'."""
    return len(value) == 64 and all(c in "0123456789abcdef" for c in value.lower())


def csv_next_rows(csv_path: Path, max_rows: int) -> List[dict]:
    """Read the link-checker CSV and return up to max_rows rows not yet checked
    today (UTC), each as {"row_index", "url", "content_hash"}. row_index is the
    0-based position among data rows (header excluded) — csv_line_edit (Task 6)
    uses it to target the right line for its own targeted rewrite. content_hash
    is the prior content hash for that URL if the 'status' column holds one
    (sha256 hex digest) from an earlier run, else "" (first-ever check, or the
    last run only recorded a plain status word). Does not mutate the file —
    that's csv_line_edit's job, driven by run_job (Task 6)."""
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    rows: List[dict] = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row_index, row in enumerate(reader):
            if len(rows) >= max_rows:
                break
            last_checked = (row.get("last_checked") or "").strip()
            if last_checked == today:
                continue
            status = (row.get("status") or "").strip()
            content_hash = status if _is_sha256_hex(status) else ""
            rows.append({
                "row_index": row_index,
                "url": (row.get("url") or "").strip(),
                "content_hash": content_hash,
            })
    return rows


def url_verify(url: str, expected_content_hash: Optional[str]) -> dict:
    """One bounded HTTP GET (httpx, short timeout, following redirects but not
    infinite loops — httpx caps redirect count itself) to check a link is
    reachable and, if a prior content hash was supplied, whether the content
    changed. Best-effort/background convention: any failure (bad host, DNS,
    timeout, TLS, too-many-redirects, ...) degrades to reachable: False rather
    than propagating — matching archivist.recall's try/except in main.py."""
    checked_at = _now()
    try:
        response = httpx.get(url, timeout=_URL_VERIFY_TIMEOUT, follow_redirects=True)
    except Exception as exc:
        print(f"  [!!] url_verify: '{url}' unreachable (non-fatal): {exc}")
        return {
            "url": url,
            "reachable": False,
            "status_code": None,
            "content_changed": None,
            "checked_at": checked_at,
        }

    content_hash = hashlib.sha256(response.text.encode("utf-8")).hexdigest()
    content_changed = (content_hash != expected_content_hash) if expected_content_hash else None
    return {
        "url": url,
        "reachable": True,
        "status_code": response.status_code,
        "content_changed": content_changed,
        "checked_at": checked_at,
    }
