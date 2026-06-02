# PDA Persistent Orchestration Layer Checkpoint

Date: 2026-06-02

## What changed

- Added a persistent worker lifecycle layer around the existing canonical queue worker.
- Preserved `Scripts\Start-PDAQueueWorker.ps1` without changing queue semantics.
- Kept `/reporter` compatible with the existing n8n → staging → intake → queue flow.

## Orchestration design

- `Scripts\Start-PDAWorker.ps1` launches `Scripts\Start-PDAQueueWorker.ps1` and `Scripts\Start-PDAReporterIntakeWatcher.ps1` in hidden background PowerShell processes.
- `Scripts\Stop-PDAWorker.ps1` stops both tracked worker processes safely and cleans up orphan matches.
- `Scripts\Get-PDAWorkerStatus.ps1` reports queue-worker and intake-watcher PID/state, queue counts, and log tails.
- Queue execution logging is stored at `PDA-Logs\workers\pda-worker.log`.
- Intake execution logging is stored at `PDA-Logs\workers\pda-reporter-intake.log`.
- State files are stored beside the logs in `PDA-Logs\workers\`.

## Lifecycle

1. Start the worker with `Start-PDAWorker.ps1`.
2. Submit work through the existing `/reporter` flow.
3. The intake watcher polls `PDA-Tasks\staging\n8n-reporter` and invokes `Process-PDAReporterStagedTasks.ps1` automatically.
4. The intake processor dispatches to `PDA-Tasks\pending`.
5. Monitor queue consumption with `Get-PDAWorkerStatus.ps1`.
6. Stop the worker with `Stop-PDAWorker.ps1`.

## Validation targets

- Persistent worker starts with a recorded PID.
- Reporter staging still appears under `PDA-Tasks\staging\n8n-reporter`.
- Intake watcher automatically triggers the preserved intake processor.
- Intake processor dispatches to `PDA-Tasks\pending`.
- Queue worker consumes the task and produces Obsidian artifacts.
- Worker stops cleanly without an orphan `pwsh` process.
- Current validation: `20260602_153104-reporter.json` flowed through automatically, produced `3ba88332-1907-4c4d-a080-646828083d54-result.json`, and left no orphan worker process.

## Next steps

- Keep this layer human-controlled.
- Consider a later phase supervisor/watchdog only if uptime requirements justify it.
- Avoid Windows service installation unless persistence needs expand.
