# OpenWebUI Workspace Design

## Purpose

This document defines how Open WebUI Workspace fits into the AI Ecosystem before implementation.

It is a design document only. It does not change scripts, configs, registries, tests, or runtime behavior.

## Role

Open WebUI Workspace is the knowledge, RAG, and reference-asset layer.

It supports curated collections of governance documents, technical references, training material, and research notes.

Open WebUI Workspace does not replace:

- COOPER
- Fabric
- tool registries
- the router
- the approval gate
- the workbench

COOPER remains the governed orchestrator.
Fabric remains the prompt-pattern source of truth.

## First Collection

Recommended first collection:

- `AI Ecosystem Governance`

Suggested contents:

- `00_Project Charter.md`
- `01_AI Ecosystem Architecture.md`
- `02_COOPER System Specification.md`
- `03_AI Tool Stack & Roles.md`
- `04_Security & Compartmentalization Policy.md`
- `06_Automation & Workflow Catalog.md`
- `07_Implementation Roadmap.md`
- `08_Obsidian Vault Structure.md`

## Collection Taxonomy

Suggested collections:

- AI Ecosystem Governance
- COOPER Operations
- Cyber / DFIR Reference
- Linux / Infrastructure Reference
- Automation / n8n Reference
- Reporting Templates
- Training Notes
- Research Library

Collection names should stay specific, searchable, and stable.

## Security Rules

Workspace is Category 1 only unless it is explicitly local-only and governed as Private Workshop safe.

Do not store the following in Open WebUI Workspace:

- secrets
- API keys
- client data
- private investigative material
- runtime state
- personality state
- tool registries
- approval rules
- DMZ material
- VeraCrypt material

Private Workshop content must not enter Workspace unless it has been sanitized and approved for Open Workshop use.

Workspace should not become an uncontrolled storage layer.

## Fabric Relationship

Fabric is the prompt-pattern source of truth.

Workspace provides knowledge context and reference material.

COOPER may later select Fabric patterns and retrieve Workspace knowledge during workflow planning.

Fabric and Workspace are separate layers:

- Fabric answers "how should the reasoning or workflow be structured?"
- Workspace answers "what approved reference context should be used?"

## Future Flow

```text
User
↓
COOPER
↓
Workflow Selection
↓
Fabric Pattern
↓
Workspace Knowledge Collection
↓
Registry
↓
Router
↓
Approval
↓
Workbench
↓
Result
```

This is the intended future flow, not a fully implemented integration path yet.

## Implementation Plan

### Phase 5A

- create the `AI Ecosystem Governance` collection manually in Open WebUI
- upload approved governance documents
- verify retrieval quality
- record the implementation in `Docs/OpenWebUI_Workspace_Implementation_Log.md`

### Phase 5B

- add technical reference collections

### Phase 5C

- document the Fabric pattern library

### Phase 5D

- connect COOPER workflow selection to pattern selection

## Risks

- Workspace becoming a dumping ground
- sensitive material entering RAG
- prompt sprawl
- stale governance documents
- confusing Workspace with execution or governance

## Definition of Done

- design doc created
- collection taxonomy defined
- Category 1 boundary documented
- first collection contents listed
- implementation remains deferred

