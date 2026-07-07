# COOPER Step 8 — Memory + Skill Loop Design

> Status: approved for implementation. Written 2026-07-01 during brainstorming.
> DoD (PRD §5, step 8): COOPER recalls a prior decision and reuses a saved skill at runtime.

## 1. Problem

Steps 1–7 give COOPER a full conversational-to-execution pipeline (classify → select tool →
gate for approval → execute → review) but no persistence across turns beyond the request's
`history` array. Every dispatch starts from zero — COOPER cannot say "you've run this before"
or skip re-deriving something it already knows. Step 8 closes that gap.

## 2. Storage decision (already made, recorded in `PROGRESS.md` / `Key Decisions.md`)

**SQLite (FTS5) + Obsidian markdown, not ChromaDB.** PRD.md names ChromaDB, but neither
comparable project the PRD itself cites (Hermes Agent, Agentic OS) actually uses a vector DB —
both land on SQLite FTS5, with markdown as the human-readable source of truth. Full rationale
in the decisions log entries dated 2026-07-01. This spec proceeds from that decision; it is not
re-litigated here.

- `Obsidian Vault/brain/` stays the durable, human-curated source of truth (unchanged — humans
  and Claude Code sessions still read/write it as they already do).
- A new SQLite database, `cooper-core/cooper_memory.db`, becomes COOPER's own runtime-queryable
  store. Already covered by the repo's blanket `*.db` gitignore rule — no new ignore entry
  needed.
- The Obsidian brain files are *also* indexed into SQLite FTS5 (read-only mirror, not a second
  source of truth) so a single recall query can search decisions, skills, and doctrine together.
  This is what satisfies the PRD's literal "Obsidian brain read each turn" wording using the
  chosen SQLite substitution for Chroma.

## 3. Architecture — the Archivist

A fifth named pipeline role, alongside Quartermaster (registry), Safety Officer (approval),
Workbench (executor), and Reviewer. Lives in `cooper-core/archivist.py`.

**Read path — `recall()`:** deterministic FTS5 query, no LLM call. Mirrors
`registry.select_tool()`'s existing keyword-matching pattern rather than Letta's
LLM-function-call-triggered memory ops — COOPER's dispatch pipeline is already deterministic
classification, not native tool-calling, so recall stays consistent with that shape instead of
introducing a new mechanism.

**Write path — `remember()`:** one JSON-schema-constrained Ollama call (temperature=0,
`think:false` — identical shape to `decision.py`'s classifier and `review.py`'s reviewer,
reusing `_ollama_complete`/`_openai_complete`) extracts `{summary, tags, outcome}` from a
completed dispatch, then writes a row. This is the one technique borrowed directly from
Mem0/Zep/Cognee — structured extraction beats storing raw transcript blobs for recall quality —
implemented with infrastructure already proven in this codebase, no new dependency.

**Explicitly not adopted:** Letta's tool-invoked memory calls (would require real function-calling
the pipeline doesn't have), Cognee's knowledge graph (new graph-store infra unjustified at this
memory volume), LangChain/LlamaIndex Memory (conflicts with the repo's stdlib-first convention
in `CLAUDE.md`), Supermemory (a new process/binary to run versus SQLite living inside
`cooper-core`), HRR (schema reserves a column, implementation deferred — see §6).

## 4. Schema

```sql
CREATE TABLE decisions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at    TEXT NOT NULL,          -- ISO 8601
    workshop      TEXT NOT NULL,
    message       TEXT NOT NULL,
    tool_name     TEXT,                   -- NULL for answer/clarify turns
    summary       TEXT NOT NULL,          -- LLM-extracted
    tags          TEXT NOT NULL,          -- comma-separated
    outcome       TEXT NOT NULL,          -- "success" | "failure" | "n/a"
    review_verdict TEXT,                  -- "pass" | "flag" | NULL
    hrr_vector    BLOB                    -- reserved, unused (see §6)
);

CREATE VIRTUAL TABLE decisions_fts USING fts5(
    message, summary, tags, content='decisions', content_rowid='id'
);

CREATE TABLE skills (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_name           TEXT NOT NULL,
    tags                TEXT NOT NULL,
    successful_run_count INTEGER NOT NULL DEFAULT 0,
    failed_run_count     INTEGER NOT NULL DEFAULT 0,
    trust_score          REAL NOT NULL DEFAULT 0.0,   -- successes / (successes + failures)
    last_success         TEXT,
    last_failure         TEXT,
    example_message       TEXT NOT NULL,
    example_output        TEXT,
    hrr_vector            BLOB                        -- reserved, unused (see §6)
);

CREATE VIRTUAL TABLE skills_fts USING fts5(
    tool_name, tags, example_message, content='skills', content_rowid='id'
);

CREATE VIRTUAL TABLE brain_fts USING fts5(
    file_name, heading, body      -- read-only mirror of Obsidian Vault/brain/*.md, chunked by heading
);
```

`decisions` is the audit trail — every dispatch attempt gets a row, pass or flag, matching the
existing "run don't describe" / auditability posture already enforced elsewhere in this repo
(approval tickets, workshop violations, etc.). `skills` only gets a row once a tool has passed
review at least once; it is the reusable, trust-scored layer.

`brain_fts` is refreshed the same way `registry.py` already caches the YAML registry —
mtime-checked, rebuilt on change, no server restart required.

## 5. Turn-loop integration

No changes to `approval.py`'s security logic — Archivist is purely additive, never bypasses the
permission ladder. Integration points in `main.py`:

- **After `_execute()` succeeds** (post-`review.govern()`): call `archivist.remember(...)`
  with the tool, message, raw output, and reviewer verdict. One more awaited call in the same
  request — same latency shape as the reviewer call already added in Step 7.
- **Before generating an `answer`-classified reply**: call `archivist.recall(message)`; if a
  relevant decision/skill/brain snippet is found, inject it into the generation context as an
  extra system note ("Relevant memory: ..."). This is the observable "COOPER recalls a prior
  decision" behavior.
- **Inside `_handle_dispatch()`, after `registry.select_tool()` picks a tool**: call
  `archivist.recall(message, kind="skill")`; if a matching skill exists above a trust threshold
  (0.5, i.e. more successes than failures), prepend a note to the halt/auto-run reply — "This
  matches a proven skill — N successful runs, trust X%." This is the observable "reuses a saved
  skill at runtime" behavior. The approval ladder still fires exactly as it does today for L2+
  tools; a proven skill is not an approval bypass.

## 6. Deferred work (explicitly out of scope for this step)

- **HRR (Holographic Reduced Representations).** Schema reserves `hrr_vector BLOB NULL` on both
  `decisions` and `skills` so it can be added later without a migration, but implementing the
  bind/bundle/decode/cleanup-memory algebra is deferred — the memory corpus is too small right
  now for fuzzy vector recall to pay for its own complexity.
- Knowledge graph, LLM-function-call-triggered memory, hosted memory APIs — see §3.

## 7. Verification plan

No formal pytest suite exists for `cooper-core` yet (matches the rest of the project's
convention of live `curl` verification against the running server). Two scenarios prove the DoD:

1. **Skill reuse:** dispatch a tool once, approve, let it succeed → `skills` row created.
   Dispatch the same/similar request again → halt/auto-run reply references the prior
   successful run and its trust score.
2. **Decision recall:** ask a question related to a stored decision (e.g. referencing a prior
   dispatch's outcome) → `answer`-classified reply includes content grounded in the stored
   memory, not just the model's unaided response.

Both are checked live via `curl` against `POST /chat`, same pattern used to verify every prior
step in `PROGRESS.md`.
