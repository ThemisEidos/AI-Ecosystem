# PDA Routing Analytics

`Scripts/Get-PDARoutingSummary.ps1` aggregates `PDA-Logs/routing/*.json` into operational routing metrics without changing routing behavior.

## Inputs

- Default log path: `PDA-Logs/routing`
- Source records: per-dispatch audit JSON written by `Scripts/Invoke-PDAModel.ps1`

## Metrics

- dispatches by command
- dispatches by model
- dispatches by worker
- success and failure counts
- success and failure rate
- fallback usage count
- `category_1` versus `category_2` / `restricted_local` volume
- cloud versus local usage
- top routing reasons

## Usage

Human-readable console summary:

```powershell
pwsh -File Scripts/Get-PDARoutingSummary.ps1
```

JSON to stdout:

```powershell
pwsh -File Scripts/Get-PDARoutingSummary.ps1 -AsJson
```

JSON export to a file:

```powershell
pwsh -File Scripts/Get-PDARoutingSummary.ps1 -ExportPath PDA-Logs/routing-summary.json -AsJson
```

Custom log directory:

```powershell
pwsh -File Scripts/Get-PDARoutingSummary.ps1 -LogPath C:\path\to\routing-logs
```

## Notes

- Empty log directories return a valid zero-count summary.
- Invalid JSON files are reported under `invalid_files` and excluded from counts.
- Cloud versus local usage is derived from `routing_surface` when present and falls back to `selected_model`.
- Fallback usage counts are exact for audit records that include `fallback_used`. Older routing logs created before that field was added are still summarized, but they do not contribute to `fallback_usage_count`.

## Validation

- `Scripts/Test-PDARoutingSummary.ps1 -AsJson -NoThrow`
- `Scripts/Get-PDARoutingSummary.ps1 -AsJson`
