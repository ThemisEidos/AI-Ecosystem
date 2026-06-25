# AI Ecosystem Implementation Strategy

## Purpose

This document defines the approved implementation strategy for the AI Ecosystem.

The strategy is Open-first and Private-derivative.

Open Workshop is the active development and reference ecosystem.
Private Workshop is the hardened derivative, split now and maintained as a secure baseline.
Shared standards belong to the ecosystem and must remain portable across Open and Private.

## Core Model

```text
Open Workshop    = active reference implementation
Private Workshop = hardened derivative implementation
Shared standards = portable contracts and governance
```

## Governing Rule

Implementations may differ. Contracts must match.

Allowed differences:

- provider choice
- model choice
- local vs cloud implementation
- observability tooling
- UI and workflow convenience features

Required matches:

- workflow contracts
- registry contract shape
- approval semantics
- storage boundaries
- evidence expectations
- security rules
- workshop meaning

Open implementation details must not be treated as portable by default.
Portability must be demonstrated through shared contracts, not assumed from naming similarity.

## Assumption Tags

Use the following tags whenever an item is not environment-agnostic:

- `[OPEN-ONLY]` = valid only in Open Workshop
- `[REQUIRES-CLOUD]` = depends on cloud model or hosted service access
- `[REQUIRES-INTERNET]` = depends on outbound internet access
- `[REQUIRES-EXTERNAL-API]` = depends on a non-local API or webhook
- `[PRIVATE-PORT-REVIEW]` = requires explicit Private Adaptation Review before porting
- `[LOCAL-ALTERNATIVE-NEEDED]` = Open implementation is acceptable, but a local Private equivalent is required before porting

These tags are documentation controls.
They do not grant implementation approval by themselves.

## Implementation Waves

### Wave 1 - Split and Secure Baseline

- establish Open and Private as distinct stacks
- lock Private as a hardened baseline
- document the split, baseline boundaries, and non-portable assumptions
- identify Open-only dependencies that cannot move to Private without review

### Wave 2 - Shared Contracts and Registries

- define portable workflow and capability contracts
- keep registry meaning stable across Open and Private
- allow implementation differences only behind contract-compatible surfaces

### Wave 3 - Open Observability and Validation

- improve Open visibility, diagnostics, and validation
- keep observability improvements documentation-first until explicitly approved for runtime work
- avoid introducing new orchestration layers or hidden state systems

### Wave 4 - Phase 8 Open Knowledge Layer

- treat Open WebUI Workspace as the Open knowledge and reference layer
- keep Workspace knowledge-focused and Category 1 only
- keep registries, approval rules, runtime state, secrets, and private data out of Workspace

### Wave 5 - Controlled Open Integrations

- evaluate Open-only integrations behind explicit assumption tags
- keep cloud and external dependencies visible and reviewable
- require local alternatives or explicit non-portability decisions before any Private port

### Wave 6 - Governance and Review Workflows

- expand governance review surfaces only when workflow need is clear
- keep review workflows human-governed
- do not approve autonomous loops, parallel agents, or hidden orchestration as part of this wave

### Wave 7 - Open UX and Workspace Evolution

- refine Open UX, visibility, and knowledge-surface usability
- keep UX work separate from approval logic, execution policy, and Private boundary rules

### Wave X - Private Porting Pass

- port selected Open capabilities into Private only after review
- require contract preservation plus local-only implementation evidence
- reject any port that weakens isolation, cloud prohibition, or local auditability

## Private Adaptation Review

Private ports require explicit review before adoption.

Private Adaptation Review must confirm:

- the target capability has a stable shared contract
- no cloud fallback exists
- no outbound internet dependency exists
- no external API dependency exists
- the local implementation preserves approval and evidence behavior
- storage and boundary rules remain intact
- the Open implementation is not being copied into Private without local justification

Review output should classify the candidate as:

- portable now
- portable with local alternative work
- Open-only for now
- rejected for Private

## Planned Adoption Backlog Integration

The backlog should track strategy-aligned evaluations without treating them as approved implementation.

Backlog entries should:

- carry assumption tags when relevant
- identify whether the item is Open reference work or a Private port candidate
- mark any Private dependency as requiring Private Adaptation Review
- avoid implying runtime approval from documentation-only inclusion

Wave 1 planning artifacts define the pre-implementation review package for the Open / Private split:

- `Docs/Wave1_Open_Private_Split_Plan.md`
- `Docs/Private_Isolation_Verification_Standard.md`
- `Docs/Private_Adaptation_Review_Template.md`
- `Docs/Wave1_Health_Check_Baseline.md`

## Deferred and Rejected Directions

The following remain deferred or rejected unless separately approved:

- autonomous execution loops
- parallel agent swarms
- hidden queues or orchestration layers
- database-first workflow state
- direct assumption that Open cloud-enabled features can port to Private unchanged
- policy-only Private isolation without verifiable enforcement

## Cross-References

- [07_Implementation Roadmap.md](../07_Implementation%20Roadmap.md)
- [01_AI Ecosystem Architecture.md](../01_AI%20Ecosystem%20Architecture.md)
- [02_COOPER System Specification.md](../02_COOPER%20System%20Specification.md)
- [04_Security & Compartmentalization Policy.md](../04_Security%20%26%20Compartmentalization%20Policy.md)
- [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md)
- [Wave1_Open_Private_Split_Plan.md](../Docs/Wave1_Open_Private_Split_Plan.md)
