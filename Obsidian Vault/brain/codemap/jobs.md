---
title: jobs.py
tags:
  - codemap
loc: 1329
---

# jobs.py

COOPER Jobs — envelope loading, hash verification, exception queue (Step 14b).

Part of [[Code Map]] · `cooper-core/jobs.py` · 1329 lines

## Depends on

- [[archivist]]
- [[council]]
- [[decision]]
- [[executor]]
- [[retry_policy]]

## Classes

- **JobError** (0 methods) — —
- **QuotaExceeded** (0 methods) — —

## Functions

- `_neutralize_delimiter()` — Replace the RESULTS/EXISTING block's own '"""' delimiter with a
- `_flatten()` — Collapse newlines/tabs/space-runs to single spaces. Entry fields are LLM
- `load_registry()` — Read Config/jobs_registry.yaml. FAIL CLOSED: any read/parse error, or a
- `get_job()` — Look up one job entry by id. Loads the registry if none is given.
- `append_job_entry()` — Persist one job envelope into Config/jobs_registry.yaml, replacing any
- `set_job_approval()` — Approve or deny a job. The envelope itself is untouched.
- `update_job_settings()` — Edit a job's quota and/or schedule, then VOID its approval.
- `list_job_runs()` — Job-linked evidence records, newest first.
- `compute_envelope_hash()` — SHA-256 hex digest over the job entry's canonical JSON, excluding the
- `verify_job()` — Governance gate a run_job() call must pass before doing anything. Returns
- `_now()` — —
- `enqueue_exception()` — Record an action a job run wanted to take but could not authorize itself
- `list_exceptions()` — All job_exceptions rows in a given status, oldest first.
- `resolve_exception()` — Human review outcome for one exception (e.g. 'approved', 'dismissed').
- `_is_sha256_hex()` — True if value looks like a sha256 hex digest — the heuristic csv_next_rows
- `load_news_sources()` — The curated feed list. Fails CLOSED: no sources is a job error, not an
- `_normalise_title()` — —
- `_normalise_url()` — —
- `dedupe_items()` — Drop repeats by URL then by normalised title, WITHIN a category.
- `item_is_recent()` — Is a feed timestamp inside the window?
- `build_reel_prompt()` — One analysis call per category. Feed text is DATA, never instructions.
- `parse_reel_selection()` — Parse one category's selection, or raise JobError.
- `render_reel()` — Render the reel from a fixed in-code template.
- `input_hash()` — Content hash of a job's input document (Step 14e gate).
- `get_input_state()` — The last recorded input hash for a job, or None if it has never run.
- `set_input_state()` — Record the input hash a successful draft was produced from.
- `task_slug()` — Filename-safe slug from a drafted objective.
- `task_filename()` — TASK-<UTCdate>-<UTCtime>-<slug>[-<discriminator>].md, matching the corpus.
- `_bullets()` — —
- `render_task_file()` — Render a WF-002 task file from drafted fields, using a fixed template.
- `_as_list()` — Coerce a drafted field to a list of strings.
- `parse_task_draft()` — Parse the drafter's JSON reply into task fields, or raise JobError.
- `build_steward_prompt()` — One drafter call: the document is quoted as DATA, never as instructions.
- `_execution_id()` — Compact timestamp matching the existing
- `write_job_evidence()` — Write a job-linked completion record (Task 2's job-linkage schema:
- `async run_job()` — Dispatch a job to its hardcoded pipeline by job_type (Step 14c).
- `async draft_steward_task()` — One drafter-role LLM call turning the input document into task fields.
- `async analyse_reel_category()` — One drafter call ranking one category. Raises JobError on any fault.
- `async _run_news_reel()` — The News Reel's per-run orchestration (Step 14d, re-scoped).
- `async _run_repo_steward()` — The repo steward's per-run orchestration (Step 14e, draft-and-notify).
- `_todays_job_evidence()` — Every job-linked completion record under _EVIDENCE_DIR whose
- `write_digest()` — Write/overwrite the day's Obsidian inbox digest note — one file per day
- `write_critique_note()` — Write the planning-time council's critique to the Obsidian inbox --
