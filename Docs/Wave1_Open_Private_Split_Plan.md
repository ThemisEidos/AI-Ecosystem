# Wave 1 Open / Private Split Plan

## Purpose

Define the documentation-approved implementation plan for the Open / Private ecosystem split before any runtime changes are made.

Wave 1 establishes the boundary model, isolation rules, baseline health expectations, and review dependencies for the approved Open-first / Private-derivative strategy.

## Scope

- define the target Open and Private runtime split
- define shared standards that must remain portable
- define baseline isolation rules for Private
- define startup, shutdown, and health-check expectations
- define the review sequence required before runtime implementation begins

## Non-Goals

- no Docker, script, launcher, registry, or workflow execution changes
- no new orchestration layer
- no agent, queue, database, or dashboard approval
- no Private cloud enablement
- no Workspace content changes

## Current-State Assumptions

- Open Workshop is the active development and reference ecosystem
- Private Workshop is the hardened derivative baseline
- Phase 8 remains current
- Open WebUI Workspace is knowledge and reference only
- current Open and Private runtime boundaries are not yet fully split into independently planned stacks
- shared standards exist but require explicit Wave 1 planning references before runtime split work begins

## Target-State Structure

```text
Open Ecosystem
- Open WebUI
- LiteLLM
- n8n
- local model runtime where applicable
- Open-only integrations where approved

Private Ecosystem
- Private UI/runtime surface
- local model runtime only
- local workflow execution only
- no cloud fallback
- no outbound internet dependency

Shared Standards
- workflow contracts
- registry contract shape
- approval semantics
- evidence expectations
- security rules
- taxonomy and naming
```

## Proposed Open Stack Boundary

Open is the reference implementation.

Open may use:

- Open WebUI
- LiteLLM
- n8n
- local model runtime
- approved cloud-enabled tooling
- approved external integrations when tagged and reviewed

Open implementation details are not automatically portable to Private.

## Proposed Private Stack Boundary

Private is the hardened derivative.

Private must use:

- local-only execution paths
- local model runtime
- local workflow execution
- isolated storage and runtime surfaces
- verifiable network restrictions

Private must not use:

- cloud AI
- outbound internet dependencies
- external APIs
- Open runtime services by implicit fallback

## Shared Standards Boundary

The following standards remain shared across Open and Private:

- workflow names and meanings
- approval semantics
- evidence expectations
- security classifications
- contract shapes for portable workflows and tools
- governance terminology

Implementations may differ. Contracts must match.

## No Shared Runtime Network Rule

Open and Private must not depend on a shared runtime network for normal operation.

Any future cross-environment connectivity proposal requires separate review and must not be assumed in Wave 1 planning.

## No Shared Writable Runtime Volume Rule

Open and Private must not use shared writable runtime volumes.

Read-only reference duplication may be considered later, but writable runtime state, logs, caches, and workflow artifacts must remain separated.

## Independent Startup / Shutdown Requirement

Open and Private must be startable and stoppable independently.

Operational consequences:

- Open restart must not be required to operate Private
- Private restart must not be required to operate Open
- one environment failing must not force the other into runtime dependency

## Private Baseline Freeze Rule

Private is treated as a hardened baseline during Wave 1 planning.

No Private runtime expansion should proceed until:

- the split plan is reviewed
- the isolation verification standard is accepted
- health-check expectations are documented
- any port candidate passes Private Adaptation Review

## Implementation Phases

### Phase A - Boundary Definition

- confirm Open boundary
- confirm Private boundary
- confirm shared standards boundary
- identify current mixed assumptions that require tags

### Phase B - Isolation Verification Planning

- define minimum Private isolation tests
- define expected evidence
- define pass/fail criteria

### Phase C - Health Baseline Planning

- define required service health checks for Open
- define required service health checks for Private
- define logging expectations

### Phase D - Review Gate

- review the Wave 1 planning package
- identify runtime split prerequisites
- approve or reject transition into runtime implementation work

## Risks

- Open implementation details may be mistaken for shared standards
- Private isolation may remain policy-only if not verified
- shared volumes or networks may create hidden coupling
- health checks may be incomplete without clear service ownership
- future ports may drift from shared contracts if review is weak

## Dependencies

- [AI_Ecosystem_Implementation_Strategy.md](../Docs/AI_Ecosystem_Implementation_Strategy.md)
- [07_Implementation Roadmap.md](../07_Implementation%20Roadmap.md)
- [Private_Isolation_Verification_Standard.md](../Docs/Private_Isolation_Verification_Standard.md)
- [Private_Adaptation_Review_Template.md](../Docs/Private_Adaptation_Review_Template.md)
- [Wave1_Health_Check_Baseline.md](../Docs/Wave1_Health_Check_Baseline.md)

## Definition of Done

- Open and Private target boundaries are documented
- shared standards boundary is documented
- no shared runtime network rule is documented
- no shared writable runtime volume rule is documented
- independent startup and shutdown is documented
- Private baseline freeze rule is documented
- isolation verification and health baseline documents exist
- runtime split implementation is explicitly deferred until review and approval

## Implemented Runtime Structure

Wave 1 runtime implementation now uses:

- `PDA-Runtime/docker-compose.yml` as the Open compatibility compose file
- `PDA-Runtime/docker-compose.open.yml` as the explicit Open stack compose file
- `PDA-Runtime/docker-compose.private.yml` as the Private stack compose file

Open services:

- `pda-open-webui`
- `pda-litellm`
- `pda-n8n`

Private services:

- `pda-private-open-webui`
- `pda-private-ollama`

Open and Private use separate Docker networks and separate writable volumes.

## Start Commands

Start Open:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Start-PDAOpenStack.ps1
```

Start Private:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Start-PDAPrivateStack.ps1
```

## Health and Isolation Commands

Open health:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAOpenStackHealth.ps1
```

Private health:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAPrivateStackHealth.ps1 -ValidateWF007
```

Private isolation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAPrivateIsolation.ps1
```

## Evidence Output

Private isolation verification writes local evidence to:

```text
State/Wave1_Runtime_Split/
```

## Rollback

Rollback steps:

1. stop the Private stack
2. continue using the Open compatibility compose file only
3. remove `pda-private-net`, `pda-private-open-webui`, and `pda-private-ollama` only if the rollback is approved
4. restore previous stack start habits through `Scripts/Start-PDAStack.ps1`

## Known Limitations

- the Private stack now depends on separate `ghcr.io/open-webui/open-webui:main` and `ollama/ollama:latest` images being locally available
- Private runtime implementation is intentionally narrow and does not add a Private n8n surface
- Open and Private are separated at the Docker runtime boundary, but workflow semantics remain unchanged
