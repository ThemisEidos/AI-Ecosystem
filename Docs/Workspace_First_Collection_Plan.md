# Workspace First Collection Plan

## Purpose

This document defines the plan for the first approved low-risk Open WebUI Workspace collection.

It is a planning artifact only, not actual Workspace ingestion.

## Recommended First Collection

- Collection name: `workspace_governance_core`
- Collection type: `Project Governance`
- Security category: `Category 1 / Open Workshop`
- Workshop scope: `Open Workshop`
- Purpose: provide COOPER and Open Workshop with retrieval access to approved project governance and operating rules.

## Candidate Source Documents

The first collection should use only approved governance documents:

- `00_Project Charter.md`
- `01_AI Ecosystem Architecture.md`
- `02_COOPER System Specification.md`
- `03_AI Tool Stack & Roles.md`
- `04_Security & Compartmentalization Policy.md`
- `05_Reporting Workflow Standards.md`
- `06_Automation & Workflow Catalog.md`
- `07_Implementation Roadmap.md`
- `08_Obsidian Vault Structure.md`

## Explicit Exclusions

The first collection must exclude:

- `State/`
- `Restricted DMZ Workspace/`
- Secure Vault content
- StandardNotes content
- private or client-sensitive material
- local model weights
- credentials, secrets, tokens, or API keys
- raw workflow evidence files unless separately summarized and approved
- transient Codex task artifacts
- unsanitized Obsidian exports

## Required Review Before Ingestion

Refer to `Docs/Workspace_Import_Checklist.md`.

Each candidate source must pass:

- source-of-truth review
- Category 1 confirmation
- prohibited content scan
- duplicate or source conflict check
- human approval

## Collection Metadata Draft

```text
collection_id: workspace_governance_core
collection_name: Workspace Governance Core
collection_type: Project Governance
security_category: Category 1
workshop_scope: Open Workshop
source_of_truth: repo governance docs
owner: project owner
review_status: proposed
sanitization_status: pending
allowed_sources: 00_Project Charter.md; 01_AI Ecosystem Architecture.md; 02_COOPER System Specification.md; 03_AI Tool Stack & Roles.md; 04_Security & Compartmentalization Policy.md; 05_Reporting Workflow Standards.md; 06_Automation & Workflow Catalog.md; 07_Implementation Roadmap.md; 08_Obsidian Vault Structure.md
prohibited_sources: Restricted DMZ Workspace; Secure Vault; StandardNotes; runtime State/; secrets; private/client-sensitive material; unsanitized exports
last_reviewed_utc:
related_workflows: WF-001, WF-004, WF-006
retention_notes: update when governance docs change
```

## Validation Plan

After manual import, validate retrieval behavior by asking governance questions that should resolve from the collection.

Validation should confirm:

- Open vs Private Workshop boundary answers are correct
- roadmap and current-phase answers are correct
- WF-006 import boundary answers are correct
- prohibited or private content is not retrieved

## Test Questions

Candidate retrieval questions:

- What is the current roadmap phase?
- What is the difference between Open Workshop and Private Workshop?
- What content is prohibited from Open WebUI Workspace?
- What is WF-006 allowed to do?
- What is the role of Obsidian versus Open WebUI Workspace?
- What does the Security & Compartmentalization Policy require for Private Workshop material?

## Definition Of Done

This plan is complete when:

- the first collection candidate is identified
- allowed sources are listed
- prohibited sources are listed
- metadata draft exists
- validation questions exist
- no actual Workspace import is performed

## Recommended Next Step

- Manually review the candidate source documents using `Docs/Workspace_Import_Checklist.md`
- Then create a manual import runbook or checklist result artifact before actual Open WebUI Workspace ingestion
