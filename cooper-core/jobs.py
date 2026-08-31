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
import asyncio
import csv
import datetime
import hashlib
import io
import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import List, Optional

import httpx
import yaml

import council
import executor

_REPO_ROOT = Path(__file__).resolve().parent.parent
_REGISTRY_PATH = _REPO_ROOT / "Config" / "jobs_registry.yaml"

# write_job_evidence computes its own output dir inline (from _REPO_ROOT, so
# Task 6's tests can relocate it by monkeypatching _REPO_ROOT). These two are
# separate, dedicated constants for write_digest to read/write through — same
# monkeypatch-a-module-constant pattern as _REGISTRY_PATH above, but pointed at
# by name rather than derived through _REPO_ROOT at call time.
_EVIDENCE_DIR = _REPO_ROOT / "State" / "Workflow_Evidence" / "completion"
_DIGEST_DIR = _REPO_ROOT / "Obsidian Vault" / "00_Inbox"

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


def _apply_csv_row_updates(csv_path: Path, updates: dict) -> str:
    """Read csv_path in full and return the updated CSV text with `updates`
    (row_index -> {column: value, ...}) applied to the matching data rows.
    Does not touch the file on disk — run_job hands the returned text to
    csv_line_edit, which is the only thing that actually writes."""
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        rows = list(reader)
    for row_index, changes in updates.items():
        if 0 <= row_index < len(rows):
            rows[row_index].update(changes)
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    return buf.getvalue()


async def csv_line_edit(filename: str, content: str, write_scope: List[str]) -> str:
    """Thin wrapper around executor._run_file_edit for a job's CSV rewrite step.
    run_job builds the full updated CSV text (see _apply_csv_row_updates) and
    hands it here with the job's own caller-supplied write_scope — the same
    contract executor._run_file_edit documents (write_scope is never LLM-set;
    it comes from the trusted job entry). Raises executor.ExecutionError
    unchanged on any containment/scope failure; run_job is responsible for
    catching that and enqueueing an exception instead of propagating it."""
    tool = {"name": "csv_line_edit"}
    args = {"filename": filename, "content": content, "write_scope": write_scope}
    return await executor._run_file_edit(tool, "job run: csv_line_edit", "open", args)


def _execution_id(now: datetime.datetime) -> str:
    """Compact timestamp matching the existing
    State/Workflow_Evidence/completion/ filename convention, e.g.
    '20260623T040423552Z' (UTC, millisecond precision, no separators)."""
    return now.strftime("%Y%m%dT%H%M%S") + f"{now.microsecond // 1000:03d}Z"


def write_job_evidence(
    job_id: str,
    run_id: str,
    job_entry: dict,
    status: str,
    artifact_paths: List[str],
    notes: str,
    verdicts: List[dict],
) -> Path:
    """Write a job-linked completion record (Task 2's job-linkage schema:
    job_id/envelope_hash/run_id all present and non-empty) to
    State/Workflow_Evidence/completion/, matching the existing
    'workflow_completion_<id>_<execution_id>.json' naming convention used by
    the 12 records already there. approval_id is left "" — job-linked
    completions don't need one (evidence.validate_completion's job_linked
    branch skips the open-workshop-requires-approval_id check)."""
    now = datetime.datetime.now(datetime.timezone.utc)
    execution_id = _execution_id(now)
    workshop = str(job_entry.get("workshop", "open"))
    record = {
        "workflow_id": job_id,
        "workflow_name": job_id,
        "execution_id": execution_id,
        "status": status,
        "completion_time": now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond:06d}Z",
        "workshop_id": workshop,
        "workshop_name": f"{workshop.capitalize()} Workshop",
        "approval_id": "",
        "artifact_paths": artifact_paths,
        "review_status": "unknown",
        "user_accepted": False,
        "notes": notes,
        "job_id": job_id,
        "envelope_hash": job_entry.get("envelope_hash", ""),
        "run_id": run_id,
        "verdicts": verdicts,
    }
    evidence_dir = _REPO_ROOT / "State" / "Workflow_Evidence" / "completion"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    out_path = evidence_dir / f"workflow_completion_{job_id}_{execution_id}.json"
    out_path.write_text(json.dumps(record, indent=4), encoding="utf-8")
    return out_path


async def run_job(
    job_id: str,
    conn: sqlite3.Connection,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    workshop: str,
    reviewer_model: str,
    registry_path: Optional[Path] = None,
) -> dict:
    """The link-checker job's full per-run orchestration (Step 14b Task 6).
    async def because it awaits executor._run_file_edit (already async) and,
    for each row's link check, awaits asyncio.to_thread(url_verify, ...) —
    url_verify is a synchronous blocking httpx.get call, and calling it
    directly here would stall the whole FastAPI event loop (every concurrent
    chat request) for the duration of each fetch. See the module docstring's
    reference to the plan's pre-flight review, which caught exactly this.

    1. Load + verify_job() the entry. Any refusal reason -> immediate
       {"status": "refused", "reason": ...}, nothing executed, no run_id.
    2. Generate a run_id and pull up to quota["rows_per_run"] unchecked CSV
       rows via csv_next_rows, capping total url_verify calls at
       quota["fetches_per_run"] (stop, don't raise, if a run would exceed it).
    3. Build the updated CSV text and write it via csv_line_edit. A write
       outside write_scope raises executor.ExecutionError, which is caught
       here and turned into an enqueue_exception call — not re-raised, not
       silently dropped; the run still completes and still gets an evidence
       record (a refused write is a completed, reviewable run).
    4. Write the job evidence record and return the run summary.
    """
    reg = load_registry(registry_path)
    job_entry = get_job(job_id, reg)
    if job_entry is None:
        return {"status": "refused", "reason": f"unknown job id '{job_id}'"}

    reason = verify_job(job_entry)
    if reason:
        return {"status": "refused", "reason": reason}

    run_id = uuid.uuid4().hex[:12]
    quota = job_entry.get("quota") or {}
    rows_per_run = int(quota.get("rows_per_run", 0))
    fetches_per_run = int(quota.get("fetches_per_run", rows_per_run))

    read_scope = job_entry.get("read_scope") or []
    csv_rel_path = read_scope[0] if read_scope else None
    csv_path = (_REPO_ROOT / csv_rel_path) if csv_rel_path else None

    rows_checked = 0
    rows_changed = 0
    fetches_used = 0
    fetches_capped = False
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    row_updates: dict = {}

    if csv_path is not None and csv_path.exists() and rows_per_run > 0:
        for row in csv_next_rows(csv_path, max_rows=rows_per_run):
            if fetches_used >= fetches_per_run:
                fetches_capped = True
                break
            result = await asyncio.to_thread(url_verify, row["url"], row["content_hash"] or None)
            fetches_used += 1
            rows_checked += 1
            if result.get("content_changed"):
                rows_changed += 1
            status_value = "ok" if result.get("reachable") else "unreachable"
            row_updates[row["row_index"]] = {"last_checked": today, "status": status_value}

    exceptions_raised = 0
    write_note = ""
    if csv_path is not None and row_updates:
        updated_content = _apply_csv_row_updates(csv_path, row_updates)
        write_scope = job_entry.get("write_scope") or []
        try:
            await csv_line_edit(csv_rel_path, updated_content, write_scope)
            write_note = f"wrote {len(row_updates)} updated row(s) to '{csv_rel_path}'."
        except executor.ExecutionError as exc:
            exceptions_raised += 1
            enqueue_exception(
                conn, job_id, run_id,
                proposed_action=f"write '{csv_rel_path}'",
                reason=str(exc),
            )
            write_note = f"write to '{csv_rel_path}' refused and queued as an exception: {exc}"

    notes = (
        f"run_id={run_id}: checked {rows_checked} row(s), {rows_changed} changed, "
        f"{fetches_used} fetch(es) used"
        + (" (fetches_per_run quota reached, run capped)" if fetches_capped else "")
        + (f". {write_note}" if write_note else "")
    )

    verdicts = await council.final_review(
        job_entry, workshop, f"job run: {job_id}", notes,
        base_url=base_url, api_key=api_key, backend=backend, reviewer_model=reviewer_model,
    )

    evidence_path = write_job_evidence(
        job_id=job_id,
        run_id=run_id,
        job_entry=job_entry,
        status="completed",
        artifact_paths=[csv_rel_path] if csv_rel_path else [],
        notes=notes,
        verdicts=verdicts,
    )

    return {
        "status": "completed",
        "run_id": run_id,
        "rows_checked": rows_checked,
        "rows_changed": rows_changed,
        "exceptions_raised": exceptions_raised,
        "fetches_used": fetches_used,
        "fetches_capped": fetches_capped,
        "evidence_path": str(evidence_path),
    }


def _todays_job_evidence(day: str) -> List[dict]:
    """Every job-linked completion record under _EVIDENCE_DIR whose
    completion_time falls on `day` (UTC 'YYYY-MM-DD'). Records with no job_id
    (ordinary, non-job workflow completions) are excluded — the digest is a
    jobs status report, not a general evidence viewer. Malformed/unreadable
    files are skipped rather than failing the whole digest (best-effort,
    matching url_verify's degrade-don't-propagate convention elsewhere in this
    module)."""
    records: List[dict] = []
    if not _EVIDENCE_DIR.exists():
        return records
    for path in sorted(_EVIDENCE_DIR.glob("*.json")):
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(record, dict) or not record.get("job_id"):
            continue
        if not str(record.get("completion_time", "")).startswith(day):
            continue
        records.append(record)
    return records


def write_digest(conn: sqlite3.Connection, date: Optional[str] = None) -> Path:
    """Write/overwrite the day's Obsidian inbox digest note — one file per day
    (Obsidian Vault/00_Inbox/COOPER-Digest-<date>.md), so the owner reads one
    note instead of N job-run logs. Idempotent per day: re-running jobs later
    the same day calls this again and it updates the same file in place
    (deterministic filename from `date`, plain overwrite — no append, no
    duplicate). `date` defaults to today (UTC, 'YYYY-MM-DD'); a caller can pass
    a specific day for testing or backfill.

    Covers, per the spec: which jobs ran today (job-linked completion records
    under _EVIDENCE_DIR dated today), what changed (each record's own `notes`
    summary — evidence.py only requires the strict completion schema fields,
    extra fields like `notes` pass through untouched), pending exceptions
    (jobs.list_exceptions(conn, status="pending")), and anything needing
    attention (any today's run whose status isn't "completed", or that itself
    raised an exception this run).
    """
    day = date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    runs = _todays_job_evidence(day)
    pending = list_exceptions(conn, status="pending")
    needs_attention = [r for r in runs if r.get("status") != "completed"]

    lines = [f"# COOPER Job Digest — {day}", ""]

    lines.append(f"## Jobs run today ({len(runs)})")
    if runs:
        for r in runs:
            lines.append(
                f"- **{r.get('job_id')}** (run `{r.get('run_id', '')}`, "
                f"{r.get('status', 'unknown')}) — {r.get('notes') or 'no summary recorded'}"
            )
    else:
        lines.append("- no job runs recorded today.")
    lines.append("")

    lines.append(f"## Pending exceptions ({len(pending)})")
    if pending:
        for e in pending:
            lines.append(
                f"- **{e.get('job_id')}** (run `{e.get('run_id', '')}`): "
                f"{e.get('proposed_action')} — {e.get('reason')}"
            )
    else:
        lines.append("- none.")
    lines.append("")

    lines.append(f"## Needs attention ({len(needs_attention)})")
    if needs_attention:
        for r in needs_attention:
            lines.append(
                f"- **{r.get('job_id')}** (run `{r.get('run_id', '')}`) — "
                f"status: {r.get('status')}. {r.get('notes') or ''}"
            )
    else:
        lines.append("- none — every job run today completed cleanly.")
    lines.append("")

    text = "\n".join(lines).rstrip() + "\n"

    _DIGEST_DIR.mkdir(parents=True, exist_ok=True)
    out_path = _DIGEST_DIR / f"COOPER-Digest-{day}.md"
    out_path.write_text(text, encoding="utf-8")
    return out_path


def write_critique_note(job_id: str, verdicts: List[dict]) -> Path:
    """Write the planning-time council's critique to the Obsidian inbox --
    the owner's approval prompt for job envelopes. There's no chat-based
    approval ticket for job entries (unlike tool calls); the owner reads
    this note, then hand-flips 'approved: true' in
    Config/jobs_registry.yaml themselves, same as today. One file per job id
    -- a re-critique overwrites the prior note so the owner always sees the
    current envelope's critique, never a stale one."""
    objections = [v for v in verdicts if v.get("verdict") == "flag"]
    lines = [f"# Council Critique -- job `{job_id}`", ""]
    lines.append(
        f"## Verdict: {'OBJECTION' if objections else 'clear'} "
        f"({len(objections)}/{len(verdicts)} flagged)"
    )
    lines.append("")
    for v in verdicts:
        lines.append(f"- **{v.get('member')}**: {v.get('verdict')} -- {v.get('reason')}")
    lines.append("")
    text = "\n".join(lines).rstrip() + "\n"

    _DIGEST_DIR.mkdir(parents=True, exist_ok=True)
    out_path = _DIGEST_DIR / f"COOPER-Job-Critique-{job_id}.md"
    out_path.write_text(text, encoding="utf-8")
    return out_path
