---
title: archivist.py
tags:
  - codemap
loc: 410
---

# archivist.py

COOPER Archivist — memory + skill loop (Step 8).

Part of [[Code Map]] · `cooper-core/archivist.py` · 410 lines

## Depends on

- [[decision]]
- [[retry_policy]]

## Classes

- **RecallResult** (0 methods) — —
- **SkillRecord** (0 methods) — —

## Functions

- `get_conn()` — —
- `init_db()` — —
- `_now()` — —
- `_fts_query()` — Build a safe FTS5 MATCH query from free text: OR of alphanumeric tokens, 3+ chars.
- `recall()` — Deterministic FTS5 search across past decisions and the Obsidian brain. No LLM call.
- `format_recall_context()` — —
- `get_skill()` — —
- `async remember()` — Write path: extract a structured fact, log it to decisions, upsert the skills row.
- `_write_decision()` — —
- `index_brain()` — Mirror Obsidian Vault/brain/*.md into brain_fts, chunked by ### heading. Mtime-cached —
- `_chunk_by_heading()` — Split markdown into (heading, body) chunks on ### headings; whole doc if none found.
- `async _extract()` — Production extractor: one JSON-schema-constrained LLM call. Fails safe on error.
