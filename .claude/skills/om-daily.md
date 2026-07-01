---
name: om-daily
description: Session startup briefing for COOPER build work. Combines brain review with server health check and current step confirmation. Run this at the top of every build session.
---

## Sequence

1. **Read brain** (invoke om-review)
2. **Confirm server state**:
   ```bash
   curl -s --max-time 3 http://localhost:8000/health
   ```
   Expected: `{"status":"ok","workshop":"private",...}`
   If not reachable: run `Start-CooperCore.ps1 -Workshop private` from Windows PowerShell.

3. **State your starting position** in one sentence:
   > "Step N in progress. Server [up|down]. Gotcha to watch: [X if any]."

4. **Proceed to task** without asking the user to repeat context already in PROGRESS.md.

## Recovery if server is down
```bash
powershell.exe -ExecutionPolicy Bypass -File "D:\D_Projects\01_AI_Ecosystem\cooper-core\Start-CooperCore.ps1" -Workshop private
```
Wait ~10s, then re-check health. If still down, check `cooper-core/cooper-core.err.log`.

## Do not
- Do not re-read PROGRESS.md if brain files are current (they summarize it)
- Do not ask the user "what are we working on today?" — read the brain, state the step
