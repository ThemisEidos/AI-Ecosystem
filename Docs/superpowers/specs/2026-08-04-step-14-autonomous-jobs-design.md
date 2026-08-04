# Step 14 — Autonomous Jobs: COOPER as a Daily-Use Worker

**Date:** 2026-08-04
**Status:** Approved direction (owner, this date); slices pending individual plans
**Branch context:** all work on `main` (Steps 1–13 merged and live)

---

## 1. Decision record

### The redefinition

Owner redefined success on 2026-08-04: the six tasks COOPER should take over are
five scheduled background jobs and one chat task. **COOPER's primary surface is
autonomous work — the browser chat is the control panel, not the workbench.**
This is not scope drift; it is PRD §1 ("Planning, Execution, and Reporting…
routes work to the best tool") finally given concrete daily jobs.

### The six tasks (owner's words, condensed)

| # | Task | Mode |
|---|------|------|
| T1 | CSV link checker — 10 rows/day, verify each https link still works and still points at the same content; replace dead links with working ones | cron |
| T2 | PII-collector research — daily at a randomized time, search the web and grow a list of sites/companies that collect, store, or sell PII | cron |
| T3 | Opt-out documenter — daily, pick 3 sites from T2's list, work out the data-sale opt-out process, document it | cron |
| T4 | Fabric templates — fill reusable templates from raw conversations / workflow output | chat |
| T5 | Repo steward — crawl a projects repo, read status + next steps, advance the work, update the progress plan, notify owner | cron |
| T6 | Home-network security review — devise and run a process for spotting malicious activity | cron (Private) |

### Governance amendment: per-job approval (owner-approved 2026-08-04)

The Phase 1 rule ("one-time-per-action approval, no remembered permissions")
is **amended for scheduled jobs only**:

- Approval moves from **per-action** to **per-job-definition**. The owner
  reviews and approves a job's *envelope* once: which tools it may call, what
  it may read, what it may write (explicit path allowlist), and its per-run
  quota (rows, sites, fetches, steps).
- A job definition is content-hashed (same mechanic as `skills_registry.yaml`).
  **Any edit changes the hash and voids the approval** — the job will not run
  again until re-approved.
- Every run writes a Workflow_Evidence record (validated by `evidence.py`,
  linkage = job id + envelope hash) whether it succeeds or fails.
- An action that would exceed the envelope is **never taken and never silently
  skipped**: it lands in an exception queue for owner review.
- Interactive chat is untouched — per-action approval stays exactly as built.

### The morning digest

Each day COOPER writes one digest note (Obsidian inbox) covering: jobs that
ran, what changed (with evidence links), exceptions awaiting decision, and
failures. The owner reads one note, not N logs. Chat surfaces the same queue
on request ("review the job queue") with approve/deny per item. Signal/email
push can attach later; the digest note is the v1 channel.

---

## 2. Architecture

### What carries over unchanged

- cooper-core remains the only runtime; n8n (already in the Open stack)
  remains the scheduler — it owns cron/randomized triggers and calls
  cooper-core over HTTP with the existing bearer key.
- The reviewer (Step 7) reviews every job step's output, same as chat
  dispatches. Workshop isolation, Category 1/2, and the permission ladder
  apply to jobs identically.

### New pieces

1. **`Config/jobs_registry.yaml`** — declarative job envelopes, same
   discipline as the tool registries:

   ```yaml
   jobs:
     - id: link-checker
       workshop: open
       schedule_hint: "daily 03:00"        # n8n owns the real trigger
       steps: [csv_next_rows, url_verify, csv_line_edit]
       read_scope:  ["State/LinkAudit/links.csv"]
       write_scope: ["State/LinkAudit/links.csv"]
       quota: {rows_per_run: 10, fetches_per_run: 30}
       permission_level: 3
       envelope_hash: <sha256 of this entry>
       approved: true                       # flipped only by owner
   ```

2. **`POST /jobs/run/{job_id}`** — headless entry point (bearer-authed, called
   by n8n). **Jobs do not pass through the chat classifier.** The envelope
   names its steps directly — this sidesteps the known classifier-reachability
   failure (Gotchas 2026-08-04) entirely for scheduled work.

3. **Job runner** (`cooper-core/jobs.py`) — loads the envelope, verifies hash +
   approved flag, executes steps with quota/scope enforcement *in code*,
   invokes the reviewer per step, writes the evidence record, queues
   exceptions, contributes to the digest.

4. **Exception queue** — SQLite table in `cooper_memory.db`
   (`job_exceptions`: job id, run id, proposed action, reason, status).
   Drained via chat review or left pending; never auto-expires into action.

5. **Bounded multi-step loop** (T3/T5 only) — plan → act → observe → next,
   hard-capped at `quota.steps_per_run`, tool choices restricted to the
   envelope's `steps` list. This is the only place COOPER chains actions
   without a human turn between them, and it exists *inside* an approved
   envelope or not at all.

6. **New executors** (each with tests, per repo convention):
   - `fabric_pattern` — apply a `PDA-Fabric/<pattern>` template to raw input (T4)
   - `file_edit` — write only within a job envelope's `write_scope` (T1)
   - `web_search` — SearXNG container added to the Open stack (local
     metasearch, no API key, no per-query cost) (T2/T3)

### Model note

gpt-4o-mini stays as COOPER-Open's brain for v1. The bounded loop (T3/T5) is
where brain quality becomes load-bearing; if step-planning proves unreliable,
`COOPER_MODEL` is a one-line env swap (e.g. LiteLLM alias → a stronger model)
— measure first, swap second.

---

## 3. Slices and Definitions of Done

Each slice ships alone, runs live before the next starts, and lands with tests.

| Slice | Builds | DoD (observable, running) |
|---|---|---|
| **14a** | `fabric_pattern` executor + registry entry (T4) | In chat: paste raw text, name a pattern, approve, get the filled template back; verified against a real conversation of the owner's |
| **14b** | Jobs harness: `jobs.py`, `jobs_registry.yaml`, `/jobs/run`, evidence-per-run, digest note, exception queue, `file_edit` + link-checker job (T1) | n8n fires the schedule ≥2 consecutive days unattended; CSV rows verified/replaced within envelope; valid evidence records exist; digest note appears; an intentionally out-of-scope write lands in the exception queue instead of happening |
| **14c** | SearXNG container + `web_search` executor + PII-research job (T2) | Job runs at a randomized time, appends ≥1 sourced entry per run to the vault list; entries carry source links |
| **14d** | Bounded loop + opt-out documenter job (T3) | For 3 sites from T2's list, a documented opt-out procedure lands in the vault with sources; loop provably halts at step quota |
| **14e** | Repo steward in draft-and-notify shape (T5) | Job reads a target repo's progress docs, drafts the next step as a Codex task file (WF-002 path), queues it, and the digest names it; **no autonomous code edits** — advancing to auto-execution is a separate future decision |
| **14f** | Network review design doc + data-source decision (T6) | Blocked on owner hardware choice (router syslog / Pi-hole / other). Deliverable: Private-workshop design doc + collector recommendation. Explicitly *allowed* to end in a document — the runnable slice follows the data-source decision |

Order: 14a → 14b → 14c → 14d, with 14e/14f schedulable anytime after 14b.

## 4. Out of scope for Step 14

- Signal/email push (digest note is the channel; Signal remains far-later)
- Autonomous repo edits in T5 (draft-and-notify only)
- Image generation / rich media output (owner's earlier example — real, but
  none of the six tasks need it; revisit after 14d)
- Fixing chat-path classifier reachability (Gotchas 2026-08-04) — worth doing,
  tracked separately; jobs architecture deliberately does not depend on it

## 5. Risks

- **Envelope enforcement must live in code, not prompts.** The runner checks
  scope/quota mechanically; the LLM never gets to argue its way past a path
  allowlist. (This is the lesson of Hermes's audit history — approvals that
  the runtime can skip are not approvals.)
- **T2/T3 touch other companies' sites.** Fetch politely: obey robots.txt,
  rate-limit, identify honestly. Documentation of opt-out processes is
  legitimate personal research; keep it that way.
- **Evidence volume.** 3+ jobs × daily runs will accumulate; `evidence.py`
  already validates shape — add a retention decision before it becomes noise
  (flag at 90 days).
