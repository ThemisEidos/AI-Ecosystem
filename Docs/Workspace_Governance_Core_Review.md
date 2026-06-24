# Workspace Governance Core Review

## Purpose

This document records the manual review result for the proposed `workspace_governance_core` collection.

It is a review artifact only, not actual Open WebUI Workspace ingestion.

## Collection Metadata

```text
collection_id: workspace_governance_core
collection_name: Workspace Governance Core
collection_type: Project Governance
security_category: Category 1
workshop_scope: Open Workshop
source_of_truth: repo governance docs
owner: project owner
review_status: approved_for_manual_import
sanitization_status: not_required
related_workflows: WF-001, WF-004, WF-006
retention_notes: update when governance docs change
```

## Candidate Documents Reviewed

All candidate documents were present, reviewed as repository governance sources, confirmed as Category 1 / Open Workshop material, scanned for prohibited content, and found eligible for manual import.

| Document | Source Exists | Source Of Truth Confirmed | Category 1 / Open Workshop | Prohibited Content Scan | Import Eligibility |
|---|---|---|---|---|---|
| `00_Project Charter.md` | Yes | Yes | Yes | Clear | Eligible |
| `01_AI Ecosystem Architecture.md` | Yes | Yes | Yes | Clear | Eligible |
| `02_COOPER System Specification.md` | Yes | Yes | Yes | Clear | Eligible |
| `03_AI Tool Stack & Roles.md` | Yes | Yes | Yes | Clear | Eligible |
| `04_Security & Compartmentalization Policy.md` | Yes | Yes | Yes | Clear | Eligible |
| `05_Reporting Workflow Standards.md` | Yes | Yes | Yes | Clear | Eligible |
| `06_Automation & Workflow Catalog.md` | Yes | Yes | Yes | Clear | Eligible |
| `07_Implementation Roadmap.md` | Yes | Yes | Yes | Clear | Eligible |
| `08_Obsidian Vault Structure.md` | Yes | Yes | Yes | Clear | Eligible |

## Prohibited Content Review

The reviewed set was checked for:

- credentials
- secrets
- tokens
- API keys
- private client material
- Restricted DMZ content
- Secure Vault content
- StandardNotes content
- unsanitized personal or private notes
- local model weights
- raw runtime `State/`
- sensitive approval records
- Private Workshop-only content

No prohibited content was identified in the reviewed set.

## Decision

`approved_for_manual_import`

## Manual Import Constraints

- This review does not perform ingestion.
- Import must be manual or separately governed.
- Do not bulk import anything outside the approved document list.
- Do not include runtime `State/`, Restricted DMZ material, private material, or transient Codex artifacts.
- If any document changes materially, this review should be refreshed.

## Retrieval Validation Questions

Use these questions after import to validate retrieval behavior:

- What is the current roadmap phase?
- What is the difference between Open Workshop and Private Workshop?
- What content is prohibited from Open WebUI Workspace?
- What is WF-006 allowed to do?
- What is the role of Obsidian versus Open WebUI Workspace?
- What does the Security & Compartmentalization Policy require for Private Workshop material?

## Recommended Next Step

Create `Docs/Workspace_Governance_Core_Manual_Import_Runbook.md`.

The runbook should describe how to manually create or import the collection in Open WebUI Workspace and how to validate retrieval after import.
