---
name: om-vault-search
description: Search the Obsidian brain and vault for prior decisions, patterns, or context relevant to the current task. Use before implementing anything that might have been attempted before.
---

## How to search

1. **Quick grep** across brain files:
   ```bash
   grep -ri "<keyword>" "Obsidian Vault/brain/"
   ```

2. **Vault-wide search** (finds prior agent findings, checkpoints, etc.):
   ```bash
   grep -ri "<keyword>" "Obsidian Vault/" --include="*.md" -l
   ```

3. **Read relevant hits** with the Read tool.

## What to search for
- Before implementing a pattern: search for the pattern name or approach
- Before fixing a bug: search for the error message or component name
- Before adding a new tool: search for prior registry entries or executor stubs

## COOPER-specific search terms
- `gemma4:12b` — LLM decisions, performance notes
- `subprocess` / `run_in_executor` — async execution patterns
- `approval_required` / `permission_level` — gate configuration
- `workshop` — workspace-scoping decisions
- `WORKSHOP` — env var handling notes
- `think:false` — Ollama inference optimization
- `DrvFs` — WSL2/Windows filesystem boundary issues
