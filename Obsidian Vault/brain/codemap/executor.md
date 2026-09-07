---
title: executor.py
tags:
  - codemap
loc: 1228
---

# executor.py

COOPER Workbench — execution gateway (Step 5).

Part of [[Code Map]] · `cooper-core/executor.py` · 1228 lines

## Depends on

- [[decision]]
- [[model_routing]]
- [[registry]]
- [[retry_policy]]
- [[skills]]

## Classes

- **_HTMLTextExtractor** (5 methods) — Minimal, dependency-free HTML→text stripper (stdlib only, per decision #2 —
- **ExecutionError** (0 methods) — —

## Functions

- `_resolve_named_script()` — Resolve a script filename named directly in validated args against
- `_authorize_script()` — Check the resolved script against the tool's registry allowlist.
- `_stub()` — —
- `async run()` — Execute an approved tool and return the result string.
- `_run_informational()` — Level 0 — no external action, no execution gateway involved. Summarizes
- `_run_local_read()` — Level 1 — read-only registry inspection. Reuses the same in-memory,
- `_normalize()` — Lowercase, punctuation-to-space — so 'Report Summary', 'report-summary'
- `_fabric_catalog()` — Map pattern key (file stem, lowercased) -> pattern file path. Layout is
- `_resolve_pattern()` — Match a single name/phrase (the model's pattern_name arg) against the
- `_fill_pattern()` — —
- `async _run_filesystem()` — Restricted DMZ Writer (Private only). New files only — governance
- `async _run_local_llm()` — Qwen Local Assistant (Private only) — specialist analysis/drafting route.
- `async _run_note_editor()` — Obsidian Note Writer (Open only). Create-or-update, same Level 2
- `async _run_fabric_pattern()` — Fabric Pattern Writer (both workshops). Applies a PDA-Fabric prompt
- `async _run_llm_api()` — Specialist delegation (Open only) — the foreman's road to the roster.
- `async _run_browser()` — Browser Research (Open only). HTTP fetch + stdlib HTML→text extraction
- `_first_text()` — First non-empty text among `paths`, tolerating absent elements.
- `parse_feed()` — Parse RSS 2.0 <item>s or Atom <entry>s into {title,url,summary,published}.
- `async _run_rss_fetch()` — Fetch and parse one feed (Step 14d). Job-runner-only.
- `async _run_web_search()` — SearXNG metasearch (Step 14c, Open stack only per G4). Returns a list of
- `async _web_search_as_text()` — run()'s string-contract adapter for _run_web_search.
- `async _run_workflow_engine()` — n8n workflow trigger (Open only — no reachable instance from
- `_codex_task_title()` — Ported from Get-COOPERCodexTaskTitle.
- `_codex_task_slug()` — Ported from Get-COOPERCodexTaskSlug.
- `_codex_task_markdown()` — Ported verbatim from New-COOPERCodexTaskMarkdown.
- `async _run_cli_launcher()` — Codex Task Launcher (Open only) — Level 2 template-writing half of
- `async _run_powershell()` — —
- `async _run_python()` — Mirrors _run_powershell exactly, for .py scripts under Scripts/Python/.
- `async _run_skill_import()` — Post-approval skill registration. Network + filesystem work off-loop.
- `async _run_skill_promote()` — Post-approval draft activation. Filesystem work off-loop, same
- `_scope_admits()` — True if `filename` is admitted by a caller-supplied write_scope entry.
- `async _run_file_edit()` — Job-runner file writer (Step 14b). Not registered in any tool registry
