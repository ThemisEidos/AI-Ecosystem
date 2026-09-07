---
title: main.py
tags:
  - codemap
loc: 1157
---

# main.py

COOPER Core — FastAPI conversational runtime.

Part of [[Code Map]] · `cooper-core/main.py` · 1157 lines

## Depends on

- [[approval]]
- [[archivist]]
- [[council]]
- [[decision]]
- [[driver]]
- [[embeddings]]
- [[executor]]
- [[gateway]]
- [[jobs]]
- [[model_routing]]
- [[pairing]]
- [[proposer]]
- [[registry]]
- [[review]]
- [[skills]]
- [[workshop]]

## Classes

- **JobDraftRequest** (0 methods) — —
- **ChatRequest** (0 methods) — —
- **ChatResponse** (0 methods) — —
- **_OAIMessage** (0 methods) — —
- **_OAIChatRequest** (0 methods) — —

## Functions

- `_load_system_prompt()` — —
- `async _select_skill()` — One semantic-selection call shared by the blocking and streaming paths.
- `_parse_api_keys()` — COOPER_API_KEYS (comma-separated, one per client) + legacy COOPER_API_KEY.
- `_check_auth_config()` — Startup gate: anonymous auth on a network-exposed port must be explicit.
- `_require_auth()` — Bearer gate — unless COOPER_ALLOW_ANON=1, in which case the SOCKET
- `_derive_session_id()` — Session identity = the credential presented (Step 13). Each client key is
- `_session_id()` — —
- `_render_args_preview()` — Approval-halt preview line: short values verbatim, long ones as a
- `async _handle_tool_call()` — The model's tool_call IS the dispatch (spec §2 step 4-5). Resolve
- `_queue_notice()` — —
- `_drain_notices()` — —
- `async _post_dispatch()` — Memory write + skill draft — the two chained LLM calls that used to run
- `async _execute()` — Run an approved/auto-run tool through the Workbench (Worker), then have
- `async _resolve_approval()` — Consume the pending ticket and execute on approve, or cancel on deny.
- `async _chat_core()` — One routing path for every front door (HTTP endpoints + gateway):
- `async _chat_core_inner()` — —
- `async lifespan()` — —
- `async health()` — —
- `async list_tools()` — —
- `async list_skill_registry()` — —
- `async pending()` — —
- `async run_job()` — —
- `async _critique_and_note()` — —
- `async list_jobs()` — Every job envelope plus its approval state, for the cockpit.
- `async set_job_approval()` — Approve or deny a job. This IS the approval act — previously a YAML edit.
- `async patch_job_settings()` — Edit quota / schedule. Always voids approval — see jobs.update_job_settings.
- `async list_runs()` — —
- `async list_job_exceptions()` — —
- `async pair_new()` — Issue a pairing code so a phone can get the key without typing it.
- `async pair_pending()` — —
- `async pair_claim()` — Exchange a pairing code for the API key. UNAUTHENTICATED by necessity —
- `async metrics_summary()` — Everything the Cockpit dashboard shows, from what actually happened.
- `async brain_index()` — The brain's real structure: files and their headings.
- `async brain_search()` — Full-text search over brain_fts — the SAME table archivist.recall() reads.
- `_brain_model()` — The model driving this turn. On Open the Cockpit can switch it at
- `async get_driver()` — —
- `async put_driver()` — —
- `async driver_catalog()` — Dropdown contents: local aliases first, then the OpenRouter catalog.
- `async cockpit_page()` — The cockpit shell. Deliberately UNAUTHENTICATED and data-free: it embeds
- `async critique_job()` — —
- `async workshop_status()` — —
- `async chat()` — —
- `async list_models()` — —
- `_estimate_usage()` — —
- `async oai_chat()` — —
- `async _stream_sse()` — —
- `async _single_text_chunk()` — —
- `async _generate()` — —
- `_build_messages()` — —
