# PDA Operator Console

Generated: 06/02/2026 14:41:57

## Queue Status

| Queue | Count |
|---|---:|
| Pending | 0 |
| Running | 0 |
| Completed | 39 |
| Failed | 0 |
| Results | 21 |

## Latest Activity

| Type | Latest |
|---|---|
| Completed Task | 9e1ea791-ce25-49c0-aafe-c81a6a837472.json |
| Failed Task | None |
| Result | 77ba5bc3-e327-425c-bb4d-f0904c9f0c8d-result.json |

## Worker Registry

| Command | Worker | Status | Routing Surface | Input Modes |
|---|---|---|---|---|
| /reporter | reporter-worker | active | local-only | staged-json, queue-json |
| /planner | planner-worker | active | local-only | queue-json, staged-json, message-only-test |
| /research | research-worker | active | local-only | queue-json, staged-json, message-only-test |
| /review | review-worker | active | local-only | file-based, message-only-test |
| /execute | execute-worker | active | local-only | file-based, message-only-test-dry-run |
| /fabric | fabric-worker | experimental | local-or-litellm | message-only-test, file |

## Operator Commands

`powershell
pwsh -File Scripts\Get-PDAStatus.ps1
pwsh -File Scripts\Get-PDAWorkerStatus.ps1
pwsh -File Scripts\Get-PDAQueueTelemetry.ps1
pwsh -File Scripts\Update-PDAOperatorConsole.ps1
pwsh -File Scripts\Start-PDAWorker.ps1
pwsh -File Scripts\Stop-PDAWorker.ps1
`

## Safety Notes

- Category 2 tasks must remain local-only.
- Do not commit runtime data, logs, secrets, or restricted files.
- /execute remains dry-run/no-op unless explicitly approved.
- Fabric Category 2 tasks must use local-only model routing.

## Next Improvements

- Retry policy
- Dead-letter queue
- Worker heartbeat details
- Artifact index
- Web dashboard later
