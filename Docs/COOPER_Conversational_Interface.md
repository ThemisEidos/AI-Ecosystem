# COOPER Conversational Interface

## Current Conversational Entry Points

- `Show system status`
  - Governed status request
  - Uses workshop identity, registry lookup, approval, and workbench execution
  - Returns truthful status only
  - Default workshop is Open Workshop when no mode is supplied
  - `COOPER_WORKSHOP_MODE` may override the default
- `What tools are available?`
  - Returns the approved tool inventory for the active workshop
- `List available workflows`
  - Returns the documented workflow catalog
- `What workshop am I in?`
  - Returns the active workshop and current mode
- `Switch to Private Workshop`
  - Human decision request
- `Switch to Open Workshop`
  - Human decision request

## Notes

- Status must come from approved sources only.
- If a status source is not configured, report `Not Configured`, `Not Available`, or `Unknown`.
- Workshop selection remains a human decision.
- `Scripts/Get-COOPERRuntimeStatus.ps1` is legacy and not authoritative for COOPER status.
