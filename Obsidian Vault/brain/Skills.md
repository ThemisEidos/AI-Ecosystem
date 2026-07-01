# Skills — Proven COOPER Capabilities

> Updated 2026-07-01. Source: State/COOPER_Skills.json + FastAPI build steps 1-5.
> Do not reimplement a skill that already works — extend or configure it.

---

## PS-Era Skills (WF-xxx, operational via port 8788)

### WF-007 · Private Local Analysis
- Status: operational (5 successful runs, last: 2026-06-23)
- Trigger: "Analyze the private workshop boundary, local routing, and restricted output path"
- Route: local-only, no cloud

### WF-005 · Note Creation
- Status: operational (2 successful runs, last: 2026-06-23)
- Route: local-only

### WF-002 · Codex Task Generator
- Status: operational (4 successful runs, last: 2026-06-25)
- Trigger: "Create a Codex task to [description]"
- Output: `TASK-YYYYMMDD-HHMMSS-[slug].md` in `Codex_Tasks/`
- Route: local-only

---

## FastAPI-Era Skills (Steps 1-5, active via port 8000)

### Conversational Runtime (Step 1)
- `POST /chat {"message":"..."}` → in-character COOPER reply
- `POST /v1/chat/completions` → OpenAI-compatible (used by Open WebUI)
- Model: `COOPER:latest` (gemma4:12b base, Modelfile in `Models/cooper-personality/`)

### Decision Classifier (Step 2)
- Classifies every turn: `answer` / `clarify` / `dispatch`
- gemma4:12b, temperature=0, JSON-schema-constrained, `think:false`
- Few-shot 10-example prompt in `decision.py` `_CLASSIFIER_SYSTEM`

### Quartermaster Registry (Step 3)
- `GET /tools` → full workshop registry from YAML (no LLM call)
- Config: `Config/general_tool_registry.yaml` (open), `Config/private_tool_registry.yaml` (private)
- Mtime-cached reader, bag-of-words tool selection

### Safety Officer Approval Gate (Step 4)
- L0/L1 auto-run; L2+ (or `approval_required: true`) halt for approval
- In-memory ticket, 600s TTL, one per workshop
- `GET /pending` → ticket inspection

### Workbench Execution Gateway (Step 5)
- Executes PowerShell scripts from `Scripts/` after approval
- Requires explicit `.ps1` filename in user message
- Path traversal protected via `relative_to()` guard
- `Scripts/Test-Exec.ps1` — fast verification script, no Docker needed
- Other executor_types (`python`, `browser`, etc.) return stubs — not yet wired
