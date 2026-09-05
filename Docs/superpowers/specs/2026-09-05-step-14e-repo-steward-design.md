# Step 14e — Repo Steward (draft-and-notify)

Status: **approved direction, 2026-09-05** (owner decisions inline below).
Parent spec: `Docs/superpowers/specs/2026-08-04-step-14-autonomous-jobs-design.md` (T5).

## 1. Definition of Done

From the parent spec's slice table, unchanged:

> Job reads a target repo's progress docs, drafts the next step as a Codex task file
> (WF-002 path), queues it, and the digest names it; **no autonomous code edits** —
> advancing to auto-execution is a separate future decision.

Observable proof required before this slice is called done:

1. A real run against the live Open stack writes a task file into `Codex_Tasks/`.
2. A second run with an unchanged input writes **no** new file and still records evidence.
3. Touching the input produces a second, different task file.
4. The digest note names the drafted task.
5. An out-of-scope write attempt lands in the exception queue rather than happening.

## 2. Owner decisions taken during design (2026-09-05)

Four forks were put to the owner and answered. They constrain everything below.

**D1 — The bounded multi-step loop is NOT built in 14e.** The parent spec assigns the
loop to "T3/T5 only", and T3 (14d) was cancelled the same day, which made 14e look like
the loop's remaining home. It is not. As specced the loop restricts "tool choices to the
envelope's `steps` list" — that is, it reads a job's `steps` at runtime and lets an LLM
choose among them, which is exactly the generic step-executor the owner declined on
2026-09-01 when choosing 15e option (a) narrow. 14e's DoD is a linear pipeline and does
not need a loop. **The narrow-scope invariant holds unchanged: a job's `steps` list stays
documentation, nothing dispatches on it, and no LLM selects a tool.**

**D2 — Target repo is `01_AI_Ecosystem`, COOPER's own.** Rejected: `09_automate_removal`
and `03_brain_bot`, both of which would require a new bind mount into the Open container
— a widening of what COOPER can see, and an owner-only decision not worth spending here.

**D3 — Read scope is `Obsidian Vault/brain/North Star.md` only.** Already mounted
**read-only** into the Open container. `PROGRESS.md` and `PRD.md` are deliberately NOT
mounted and will not be; a whole-repo read-only mount was also rejected. The consequence
is accepted openly: draft quality is capped by how current the North Star is. The upside
is that this slice changes **no mounts at all** — read path and write path both already
exist, so 14e adds no new surface to the container.

**D4 — Re-draft suppression is input-change gating, not output dedup.** A daily job
reading one mostly-static file would otherwise redraft the same task forever. Rejected:
drafting every run and comparing objectives (fuzzy, and burns a cloud call to discard it);
parsing the next unchecked roadmap item (impossible — the checkboxes are in `PROGRESS.md`,
which D3 excludes). Chosen: content-hash the input, draft only when the hash changes.

**D5 — `_run_file_edit` gains a directory-scope form.** Found during spec self-review,
not during implementation: `write_scope` is **exact string match only** — documented as
"resolves to EXACTLY what write_scope names", with no glob, prefix or directory matching.
The steward must create a *newly named* file every run, which that primitive forbids.
Computing the filename at runtime and passing it as its own scope was rejected outright:
it would make the envelope's approval meaningless, since the runner could then name
anything. Rejected alternatives: a single fixed filename overwritten each run (loses the
queue shape and can destroy an unread proposal), and pre-declared numbered slots (caps the
queue arbitrarily, abandons the corpus naming convention).

Chosen: **a `write_scope` entry ending in `/` means "any file directly inside this one
directory"** — no subdirectories, no traversal, and the existing `..`-segment rejection
applies unchanged to both the filename and the scope entry. Exact-match semantics remain
the default and every existing registry entry keeps them untouched. This is a real
widening of a deliberately tight security guarantee, taken as an owner decision, and it
lands with its own tests and its own review rather than riding in on the job slice.

## 3. Architecture

A **third hardcoded `job_type` branch**, exactly like the two before it. No new executor
type, no new container, no new mount, no registry-visible tool.

```
run_job(job_id)
  -> job_type == "repo_steward"  -> _run_repo_steward(...)
```

`repo_steward` joins `csv_link_check` (14b) and `pii_research` (14c) in `run_job`'s
dispatch. The 14c change is the precedent to copy verbatim in shape.

### Per-run orchestration

1. **Read the input.** `North Star.md` via the envelope's `read_scope[0]`. Unreadable
   input is a refusal, never a fail-open to empty string — see §5.
2. **Hash it.** `sha256` of the input bytes.
3. **Gate.** Look up the last recorded draft state for this job id in
   `cooper_memory.db`. If the stored hash equals the current hash, the run short-circuits:
   status `completed`, zero artifacts, notes recording "input unchanged", and a **valid
   evidence record is still written**. A quiet day is a real, reviewable run.
4. **Draft.** One `drafter`-role LLM call (bounded by the 15f `drafter` budget: 90s,
   2 retries). Input text is quoted as data inside a delimiter-neutralized fence. The
   model returns the task's fields, not a filename and not a path.
5. **Render.** Build the WF-002 task-file body from those fields using a fixed template
   in code — Objective / Background / Current State / Required Work / Constraints /
   Validation / Definition of Done, matching the existing `Codex_Tasks/*.md` corpus. The
   Constraints block is written by COOPER, not by the model.
6. **Write.** Through `executor._run_file_edit` with the job's own `write_scope`, the same
   contract `csv_line_edit` documents: `write_scope` is caller-supplied and never LLM-set.
   Filename `TASK-<UTC timestamp>-<slug>.md`, matching the corpus convention, admitted by
   the D5 directory-scope entry `Codex_Tasks/`. The slug is derived in code from the
   drafted objective and sanitized to `[a-z0-9-]`; the model never supplies a path, a
   filename, or any part of one.
7. **Record state.** Store the input hash + the written path, so step 3 can gate the next
   run.
8. **Review + evidence.** Council final review and an evidence record, identical in shape
   to the other two branches.

### Data flow

```
brain/North Star.md (ro mount)
      |  read + sha256
      v
  [ hash unchanged? ] --yes--> completed, 0 artifacts, evidence written, END
      |no
      v
  drafter LLM call (fenced, budgeted)  -> task fields
      v
  fixed template render (code, not model)
      v
  _run_file_edit within write_scope    -> Codex_Tasks/TASK-*.md
      v
  state row (job id, input hash, path) -> cooper_memory.db
      v
  council review -> evidence record -> digest names the task
```

## 4. Registry entry

```yaml
- id: repo-steward
  job_type: repo_steward
  workshop: open
  schedule_hint: daily 07:00
  steps:            # documentation only -- nothing dispatches on this
  - read_north_star
  - draft_task
  - write_task_file
  read_scope:
  - Obsidian Vault/brain/North Star.md
  write_scope:
  - Codex_Tasks/
  quota:
    tasks_per_run: 1
  permission_level: 3
  approved: false
```

Committed `approved: false`, like both existing jobs. There is no approval API, so
editing that field **is** the approval act and it belongs to the owner.

## 5. Error handling

Three failure modes have bitten this repo before and are designed against explicitly.

**Unreadable input must refuse, not fail open.** 14c's vault-note defect (2026-09-04) came
from an intermediate "fail open to empty string" that turned an append into an overwrite.
Here the input is read-only so no data can be destroyed, but a fail-open would be worse in
a subtler way: an empty input still hashes, still differs from the stored hash, and would
drive the model to draft a task from nothing. So: `OSError`/`UnicodeDecodeError` on the
input ends the run as `failed` with an evidence record, and drafts nothing.

**Type assumptions after `json.loads` are guarded.** The 2026-09-01 bug class has now
recurred three times, most recently found by the 15f chaos suite: a guarded backend call
and a guarded `json.loads`, then an unguarded assumption about the parsed type one line
later, letting a model returning `null` raise a raw `AttributeError` past the `JobError`
contract into an HTTP 500. Every field read off the model's response is type-checked
before use, and the whole extraction is covered by a chaos test asserting `JobError`.

**Out-of-scope writes queue, never happen.** Delegated to `_run_file_edit` + the existing
exception queue, unchanged from 14b/14c.

## 6. Security

**Prompt-fence escape.** The input is a file the owner writes, not web content, so it is
lower-risk than 14c's snippets — but it is still text the model is asked to reason over,
and the North Star quotes error messages and command output from all over the system.
It is fenced with the existing `_neutralize_delimiter` helper. Treating owner-authored
files as automatically trusted is how injection reaches a system indirectly.

**No autonomous code edits.** The write scope is `Codex_Tasks/` alone. The job produces a
*proposal* a human then chooses to run. This is the parent spec's explicit "draft-and-
notify" boundary and §4's "out of scope: autonomous repo edits in T5".

**The D5 widening, stated plainly.** A directory scope is weaker than an exact path: any
file directly inside `Codex_Tasks/` becomes writable by this job, where previously only a
named file was. Three things bound it. The directory is a bind mount containing only
generated task proposals — nothing executable, no secrets, nothing on the DO-NOT-TOUCH
list. Subdirectories are not matched, so the scope cannot deepen. And the `..` rejection
runs first and unchanged, so the traversal case the exact-match design was built to defeat
is still defeated. Exact-match stays the default; a scope entry is a directory only when
it ends in `/`, which no existing entry does.

**Evidence hygiene.** Job id `repo-steward`, artifact `TASK-*.md`, no field containing a
token matching `evidence._SENSITIVE_RE`. 14c's first defect was an unrecordable honest
failure caused by a job id containing `pii`; this id is checked against that regex in a
test, not by eye.

## 7. Testing

Every behavior lands with tests in `cooper-core/test_jobs.py` (and `test_chaos.py` for the
fault injection), per repo convention.

- Gate: same hash twice -> second run writes zero files, still records evidence.
- Gate: changed input -> a second, different task file.
- Render: template contains every required WF-002 section.
- Render: filename matches the corpus convention.
- Scope: a write outside `write_scope` raises an exception-queue entry, not a file.
- Scope (D5): a directory entry admits a file directly inside it.
- Scope (D5): a directory entry does NOT admit a file in a subdirectory of it.
- Scope (D5): a `..` segment is still rejected against a directory entry.
- Scope (D5): existing exact-match entries keep exact-match semantics -- a directory-like
  write against a non-`/` entry is still refused.
- Refusal: unreadable input -> `failed` + evidence, no draft call made.
- Chaos: model returns `null` / a bare string / a list -> `JobError`, never `AttributeError`.
- Hygiene: the job id and every evidence string field survive `_SENSITIVE_RE`.
- Budget: the drafter call runs under the `drafter` budget (15f).

Live verification against the running Open stack, per the discipline rule — the five
numbered DoD proofs in §1, each with its real output recorded in PROGRESS.md.

## 8. Out of scope

- The bounded multi-step loop (D1). Still unowned; a future re-scoped 14d may claim it.
- Any further loosening of `write_scope` beyond D5's single-directory form. Globs,
  recursive scopes and pattern matching stay unbuilt and unasked-for.
- Any n8n scheduler. Like 14b/14c this ships manual-trigger-only, so the parent spec's
  scheduling language stays unmet for this slice too — stated, not quietly skipped.
- Stewarding any repo but this one (D2), and reading anything but the North Star (D3).
- Auto-execution of drafted tasks. Explicitly a separate future decision.
