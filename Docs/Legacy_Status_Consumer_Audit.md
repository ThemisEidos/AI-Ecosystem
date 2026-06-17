# Legacy Status Consumer Audit

## Scope

This audit covers remaining non-governed consumers of `Get-COOPERRuntimeStatus.ps1` and related legacy status reporting behavior.

The governed conversational status path does not use the legacy helper.

## Consumer List

| File | Calling Function or Command | User-Facing | Can Produce Fictional / Security Status | Risk | Recommendation |
|---|---|---:|---:|---|---|
| `Scripts/Invoke-PDAChatBridge.ps1` | `Get-PDACommanderRuntimeContext` -> `Get-COOPERRuntimeStatus` | Yes | Yes | High | Quarantine |
| `Scripts/Get-PDADashboardStatus.ps1` | dashboard status assembly -> `Get-COOPERRuntimeStatus` | Yes | Yes | High | Quarantine |
| `Scripts/COOPER_ConversationalRouter.ps1` | orphaned `Get-COOPERRuntimeStatus.ps1` reference; not used by governed conversational status | Yes, indirectly | Potentially, if reactivated | Low | Preserve as deprecated non-authoritative |

## Notes on Legacy Helper

- `Scripts/Get-COOPERRuntimeStatus.ps1` is deprecated.
- It is not authoritative for governed COOPER status.
- It should remain isolated from the governed conversational status surface.

## Risk Assessment

- Immediate safety issue for governed conversational status: none.
- Immediate safety issue for legacy PDA status surfaces: yes, because those paths can still emit status text without passing through the COOPER governance chain.

## Recommended Remediation Order

1. Quarantine `Scripts/Invoke-PDAChatBridge.ps1` legacy status usage.
2. Quarantine `Scripts/Get-PDADashboardStatus.ps1` legacy status usage.
3. Remove or redirect the orphaned COOPER router reference once no consumers remain.
4. Remove `Get-COOPERRuntimeStatus.ps1` later only after all legacy consumers are retired and replacement coverage is in place.

## Validation

- `Scripts/Test-COOPERStatusCommand.ps1` passed.
- Governed conversational status remains routed through the identity -> registry -> router -> approval -> workbench chain.
- The governed status path does not use `Get-COOPERRuntimeStatus.ps1`.
