# Private Isolation Verification Standard

## Purpose

Define the minimum acceptable verification standard for Private Workshop isolation before and during the hardened baseline freeze.

## Minimum Acceptable Private Isolation Standard

Private isolation is acceptable only when all required tests pass and the evidence shows Private remains local-only, independently bounded, and free from Open or cloud fallback paths.

## Verification Tests

### No Outbound Internet Test

Confirm Private services do not require outbound internet access for normal operation.

Expected result:

- no successful dependency on external internet endpoints
- Private service operation remains local-only

### No External DNS Test

Confirm Private operation does not rely on external DNS resolution.

Expected result:

- no required external DNS lookups for Private runtime success
- local-only operation remains functional without public DNS dependence

### No OpenRouter / Cloud Fallback Test

Confirm Private has no fallback path to OpenRouter, hosted model APIs, or any cloud model service.

Expected result:

- no configured cloud fallback
- no implicit provider failover to remote endpoints
- no runtime dependence on external model access

### No Shared Docker Network Test

Confirm Private does not run on a shared Docker network with Open services.

Expected result:

- no shared runtime network between Open and Private
- no cross-environment service dependency through container networking

### No Shared Named Volume Test

Confirm Private does not use shared named volumes with Open for runtime state, caches, workflow artifacts, or writable data.

Expected result:

- no shared writable named volumes
- no mixed runtime artifact path

### No Open-to-Private Webhook / API Path Test

Confirm Open cannot directly invoke Private through a standing webhook or API dependency.

Expected result:

- no persistent Open-to-Private runtime call path
- no implicit bridge from Open workflow execution into Private services

### WF-007 Local-Only Verification

Confirm WF-007 remains executable only through local Private tooling and storage.

Expected result:

- WF-007 uses local-only paths
- WF-007 does not invoke cloud tools
- WF-007 outputs stay in the Restricted DMZ Workspace

## Expected Evidence Artifacts

Recommended evidence:

- dated verification notes
- service/network inspection output
- configuration review notes
- local-only workflow test notes for WF-007
- explicit pass/fail record per verification test

Evidence should remain local when it contains Private-sensitive detail.

## Pass / Fail Criteria

Pass:

- all required isolation tests pass
- no cloud fallback is present
- no shared network or writable volume dependency exists
- no Open-to-Private execution path exists
- WF-007 remains local-only

Fail:

- any required isolation test fails
- any cloud or external API fallback is present
- any shared runtime dependency weakens Private independence
- evidence is missing for a required control

## Recommended Verification Frequency During Private Freeze

- before any proposed Private runtime change
- after any approved Private runtime change
- before any Open-to-Private port decision
- at each review checkpoint during the Private baseline freeze

## Implemented Verification Command

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAPrivateIsolation.ps1
```

Current evidence output path:

```text
State/Wave1_Runtime_Split/
```

Current implementation verifies:

- no outbound internet path from the Private Open WebUI container
- no external DNS resolution from the Private Open WebUI container
- no OpenRouter reachability from the Private Open WebUI container
- no shared Docker network with Open
- no shared writable volume with Open
- no disallowed cloud provider environment variables on Private Open WebUI
- WF-007 local-only behavior
- no direct Open-to-Private endpoint reachability through the tested paths

## Related Documents

- [Wave1_Open_Private_Split_Plan.md](../Docs/Wave1_Open_Private_Split_Plan.md)
- [Private_Adaptation_Review_Template.md](../Docs/Private_Adaptation_Review_Template.md)
- [04_Security & Compartmentalization Policy.md](../04_Security%20%26%20Compartmentalization%20Policy.md)
