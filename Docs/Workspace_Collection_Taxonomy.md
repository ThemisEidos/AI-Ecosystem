# Workspace Collection Taxonomy

## Purpose

This document defines the approved Open WebUI Workspace collection types for Phase 8.

It is taxonomy only, not import implementation.

The taxonomy exists to prevent knowledge sprawl, duplicate sources of truth, and accidental sensitive ingestion.

## Workspace Collection Principles

- Open WebUI Workspace is the AI-facing retrieval layer.
- Obsidian remains the durable human knowledge vault.
- Private Workshop and Restricted DMZ content is prohibited.
- Collection inclusion requires a clear workflow purpose.
- Do not create collections just in case.
- Workflow to collection to source documents should remain traceable.

## Approved Initial Collection Types

### A. Project Governance

- Purpose: project charter, architecture, policy, roadmap, workflow standards
- Allowed content: approved governance docs only
- Security category: Category 1 / Open Workshop
- Source of truth: repo docs
- Review requirement: human-approved
- Example docs:
  - `00_Project Charter.md`
  - `01_AI Ecosystem Architecture.md`
  - `04_Security & Compartmentalization Policy.md`
  - `05_Reporting Workflow Standards.md`
  - `06_Automation & Workflow Catalog.md`
  - `07_Implementation Roadmap.md`

### B. Workflow Operations

- Purpose: support workflow routing, task generation, reporting, and import drafting
- Allowed content: workflow standards, package standards, evidence standards, and checklists
- Security category: Category 1 / Open Workshop
- Source of truth: repo docs and approved workflow documentation
- Review requirement: human-approved

### C. Technical Reference

- Purpose: approved non-sensitive technical references used by workflows
- Allowed content: public docs, sanitized setup references, approved technical notes
- Security category: Category 1 only
- Source of truth: approved external/public references or sanitized local docs
- Review requirement: source and sanitization review

### D. Collection Import Drafts

- Purpose: staged outputs from WF-006 before final approval
- Allowed content: sanitized draft summaries and metadata
- Security category: Category 1 only
- Source of truth: WF-006 output artifacts
- Review requirement: must be reviewed before actual Workspace ingestion

### E. Ecosystem Change Backlog

- Purpose: track candidate tools, concepts, and deferred ideas
- Allowed content: backlog entries and evaluations only
- Security category: Category 1 only
- Source of truth: `Docs/Ecosystem_Change_Backlog.md`
- Review requirement: human-approved; backlog inclusion is not adoption

## Explicitly Prohibited Collection Types

The following are prohibited from Open WebUI Workspace collections:

- Private Workshop data
- Restricted DMZ content
- Secure Vault content
- StandardNotes content
- credentials
- secrets
- tokens
- API keys
- client-sensitive material
- raw runtime `State/`
- local model weights
- personal or private notes
- unsanitized Obsidian vault exports
- approval records containing sensitive details
- generated evidence files unless explicitly summarized and sanitized

## Collection Metadata Standard

Required metadata fields:

- `collection_id`
- `collection_name`
- `collection_type`
- `security_category`
- `workshop_scope`
- `source_of_truth`
- `owner`
- `review_status`
- `sanitization_status`
- `allowed_sources`
- `prohibited_sources`
- `last_reviewed_utc`
- `related_workflows`
- `retention_notes`

## Naming Convention

Use the following pattern:

```text
workspace_<collection_type>_<short_name>
```

Examples:

- `workspace_governance_core`
- `workspace_workflow_operations`
- `workspace_technical_linux_reference`
- `workspace_backlog_ecosystem_changes`

## Review Statuses

- `proposed`
- `approved`
- `active`
- `deprecated`
- `rejected`

## Sanitization Statuses

- `not_required`
- `pending`
- `sanitized`
- `rejected`

## Relationship To WF-006

- WF-006 may draft candidate collection material.
- WF-006 does not approve ingestion.
- The taxonomy determines whether a draft is eligible.
- Human approval is required before Workspace ingestion.

## Definition Of Done

The taxonomy is complete when:

- approved initial collection types are documented
- prohibited collection types are documented
- metadata standard exists
- naming convention exists
- relationship to WF-006 is documented
- no Workspace import implementation is added

## Recommended Next Artifact

`Docs/Workspace_Import_Checklist.md`
