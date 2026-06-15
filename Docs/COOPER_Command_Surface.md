# COOPER Command Surface

## Current Commands

- `/cooper status`
  - Governed status command
  - Uses workshop identity, registry lookup, approval, and workbench execution
  - Returns truthful status only
  - Default workshop is Open Workshop when no mode is supplied
  - `COOPER_WORKSHOP_MODE` may override the default

## Planned Commands

- `/cooper mode`
  - Not yet implemented
- `/cooper private on`
  - Not yet implemented
- `/cooper private off`
  - Not yet implemented
- `/cooper tools`
  - Not yet implemented
- `/cooper workflows`
  - Not yet implemented

## Notes

- Status must come from approved sources only.
- If a status source is not configured, report `Not Configured`, `Not Available`, or `Unknown`.
- Workshop selection remains a human decision.
- `Scripts/Get-COOPERRuntimeStatus.ps1` is legacy and not authoritative for `/cooper status`.
