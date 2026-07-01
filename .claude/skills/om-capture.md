---
name: om-capture
description: Capture a key decision, pattern, or gotcha to the Obsidian brain. Use when something non-obvious is learned — implementation choices, traps avoided, confirmed approaches.
---

## When to invoke
Use this skill when you've just made or confirmed a non-obvious decision, found a gotcha, or validated a pattern worth keeping. Captures persist across sessions via `Obsidian Vault/brain/`.

## How to capture

1. Identify which brain file the insight belongs to:
   - **Key Decisions.md** — architecture, tool, or process choices with lasting effect
   - **Patterns.md** — reusable implementation approaches that have been confirmed working
   - **Gotchas.md** — traps, bugs, environment quirks, and known non-obvious failures
   - **Skills.md** — proven workflow capabilities (WF-xxx, tool executions, integrations)

2. Open the target file with the Read tool, then append with Edit.

3. Add a dated entry:
   ```
   ### YYYY-MM-DD · <short title>
   <one-paragraph description>
   ```

4. Confirm the append succeeded (Read the last 10 lines).

## Rules
- Write the WHY, not just the what. "Used X because Y" is a capture; "used X" is noise.
- Do not capture things already in PROGRESS.md decisions log — cross-reference instead.
- Do not capture ephemeral state (current ticket values, live queue depth, etc).
