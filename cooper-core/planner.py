"""
COOPER Planner — narrow-scope job drafting (Step 15e, narrow).

Owner scope decision 2026-09-01 (PROGRESS.md, "15e scope"): the planner only
drafts new jobs of the exact shape run_job (14b, jobs.py) already knows how
to execute — a parameterized CSV-monitor job (csv_next_rows -> url_verify ->
csv_line_edit). No new autonomous tool-calling surface: `steps`,
`permission_level`, and `workshop` are fixed by this module and never read
from the LLM's output. The planner LLM only proposes the handful of fields a
CSV-monitor job actually varies by — id, which CSV file to monitor, quota,
and a schedule hint — and every one of those is validated in code before
anything is written to jobs_registry.yaml.

Flow: draft (this module) -> council critique (council.py, 15d) -> owner
hand-approval (flip approved: true in jobs_registry.yaml, same as 14b/15d
today) -> existing run_job (jobs.py, completely unmodified) -> 14b hash
mechanic. The planner alias is called exactly once, here, and never again
during a job's execution — satisfying the spec's 15e DoD ("big-brain alias
is called zero times during execution").

Spec: Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md §3's
15e row.
"""
import csv
import json
import re
from pathlib import Path
from typing import Optional

from decision import _ollama_complete, _openai_complete
import jobs

_REPO_ROOT = Path(__file__).resolve().parent.parent

# The one job shape this planner may ever draft — fixed here, never read from
# the LLM's output. This is the narrow-scope security boundary itself.
_LINK_CHECKER_STEPS = ["csv_next_rows", "url_verify", "csv_line_edit"]
_FIXED_PERMISSION_LEVEL = 3  # matches the existing link-checker job

_MAX_ROWS_PER_RUN = 50
_MAX_FETCHES_PER_RUN = 100

_SLUG_RE = re.compile(r"[^a-z0-9]+")

_DRAFT_SYSTEM = """\
You are COOPER's Planner. The owner described a goal for an unattended job \
that periodically checks a CSV file of URLs for reachability and content \
changes -- the only job shape this planner is allowed to draft. From the \
goal, propose: a short id slug, the repo-relative path to the CSV file to \
monitor (the owner's goal should name or clearly imply it), how many rows \
to check per run, how many URL fetches to allow per run, and a plain \
schedule hint (e.g. "daily 03:00"). If the goal does not name or clearly \
imply an existing CSV file to monitor, set "csv_path" to "".

Output JSON only -- no other text.
{"id":"<lowercase-hyphen slug, 2-4 words>","csv_path":"<repo-relative path ending in .csv, or empty>","rows_per_run":<int>,"fetches_per_run":<int>,"schedule_hint":"<short phrase>"}\
"""

_DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "id":              {"type": "string"},
        "csv_path":        {"type": "string"},
        "rows_per_run":    {"type": "integer"},
        "fetches_per_run": {"type": "integer"},
        "schedule_hint":   {"type": "string"},
    },
    "required": ["id", "csv_path", "rows_per_run", "fetches_per_run", "schedule_hint"],
}


class PlannerError(Exception):
    """A goal that cannot be drafted into the one supported job shape, or a
    drafted field that fails validation. Never partially written — a raised
    PlannerError means jobs_registry.yaml was not touched."""


def slugify(name: str) -> str:
    slug = _SLUG_RE.sub("-", name.lower()).strip("-")
    return slug or "unnamed-job"


async def _extract_fields(
    goal: str, *, base_url: str, api_key: str, model: str, backend: str,
) -> dict:
    messages = [
        {"role": "system", "content": _DRAFT_SYSTEM},
        {"role": "user", "content": f"Goal: {goal}"},
    ]
    if backend == "openai":
        raw = await _openai_complete(
            base_url, api_key, model, messages, temperature=0,
            response_format={"type": "json_schema", "json_schema": {
                "name": "job_draft", "strict": True,
                "schema": {**_DRAFT_SCHEMA, "additionalProperties": False},
            }},
        )
    else:
        raw = await _ollama_complete(
            base_url, model, messages, options={"temperature": 0}, fmt=_DRAFT_SCHEMA,
        )
    return json.loads(raw)


def _validate_csv_path(csv_path: str, *, repo_root: Path) -> str:
    """Reject anything but an existing, in-repo, header-bearing CSV with a
    'url' column -- the exact shape csv_next_rows (jobs.py) already reads.
    Returns the validated repo-relative path. Same .resolve()+relative_to()
    containment technique executor.py uses for every write-scope check."""
    if not csv_path:
        raise PlannerError("goal did not name an existing CSV file to monitor")
    rel = csv_path.strip().replace("\\", "/").lstrip("/")
    if not rel.endswith(".csv") or ".." in Path(rel).parts:
        raise PlannerError(f"'{csv_path}' is not a safe repo-relative .csv path")
    full = (repo_root / rel).resolve()
    try:
        full.relative_to(repo_root.resolve())
    except ValueError:
        raise PlannerError(f"'{csv_path}' resolves outside the repo")
    if not full.is_file():
        raise PlannerError(f"'{rel}' does not exist — create the CSV before drafting a job for it")
    try:
        with open(full, newline="", encoding="utf-8") as f:
            fieldnames = csv.DictReader(f).fieldnames or []
    except Exception as exc:
        raise PlannerError(f"'{rel}' is not readable as CSV: {exc}")
    if "url" not in fieldnames:
        raise PlannerError(f"'{rel}' has no 'url' column — not a link-checker-shaped CSV")
    return rel


def _clamp(value, *, minimum: int, maximum: int, default: int) -> int:
    try:
        value = int(value)
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


async def draft_envelope(
    goal: str,
    *,
    workshop: str,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    repo_root: Optional[Path] = None,
    registry_path: Optional[Path] = None,
    extract_fn=None,
) -> dict:
    """Draft one CSV-monitor job envelope from a natural-language goal and
    persist it into jobs_registry.yaml as approved: false. Raises
    PlannerError (never writes anything) if the goal can't be drafted into
    the one supported job shape, or any field fails validation, or the
    drafted id collides with an already-registered job."""
    root = repo_root or _REPO_ROOT
    extract_fn = extract_fn or _extract_fields
    draft = await extract_fn(goal, base_url=base_url, api_key=api_key, model=model, backend=backend)

    job_id = slugify(str(draft.get("id", "")))
    existing = jobs.load_registry(registry_path)
    if jobs.get_job(job_id, existing) is not None:
        raise PlannerError(
            f"job id '{job_id}' already exists in the registry — rephrase the goal to draft a distinct job"
        )

    csv_path = _validate_csv_path(str(draft.get("csv_path", "")), repo_root=root)
    rows_per_run = _clamp(draft.get("rows_per_run"), minimum=1, maximum=_MAX_ROWS_PER_RUN, default=10)
    fetches_per_run = _clamp(
        draft.get("fetches_per_run"), minimum=rows_per_run, maximum=_MAX_FETCHES_PER_RUN,
        default=max(rows_per_run, 30),
    )
    schedule_hint = str(draft.get("schedule_hint", "")).strip() or "manual"

    job_entry = {
        "id": job_id,
        "workshop": workshop,                       # process-owned (G1), never LLM-chosen
        "schedule_hint": schedule_hint,
        "steps": list(_LINK_CHECKER_STEPS),          # fixed shape, never LLM-chosen
        "read_scope": [csv_path],
        "write_scope": [csv_path],
        "quota": {"rows_per_run": rows_per_run, "fetches_per_run": fetches_per_run},
        "permission_level": _FIXED_PERMISSION_LEVEL,  # fixed, never LLM-chosen
        "approved": False,
    }
    job_entry["envelope_hash"] = jobs.compute_envelope_hash(job_entry)

    jobs.append_job_entry(job_entry, registry_path=registry_path)
    return job_entry
