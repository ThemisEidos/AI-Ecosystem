# Workspace Governance Core Manual Import Runbook

## Purpose

This runbook defines the manual procedure for creating or importing `workspace_governance_core` into Open WebUI Workspace.

It is manual and does not automate ingestion.

## Preconditions

Before starting, confirm all of the following:

- The collection review decision is `approved_for_manual_import`.
- You are operating in Open Workshop only.
- The candidate source list is limited to approved governance documents.
- No runtime `State/`, Restricted DMZ material, private content, or transient Codex artifacts are included.
- You have access to the Open WebUI Workspace UI.

## Approved Collection Metadata

```text
collection_id: workspace_governance_core
collection_name: Workspace Governance Core
collection_type: Project Governance
security_category: Category 1
workshop_scope: Open Workshop
source_of_truth: repo governance docs
review_status: approved_for_manual_import
sanitization_status: not_required
related_workflows: WF-001, WF-004, WF-006
retention_notes: update when governance docs change
```

## Approved Source Documents

Only the following documents are approved for this collection:

- `00_Project Charter.md`
- `01_AI Ecosystem Architecture.md`
- `02_COOPER System Specification.md`
- `03_AI Tool Stack & Roles.md`
- `04_Security & Compartmentalization Policy.md`
- `05_Reporting Workflow Standards.md`
- `06_Automation & Workflow Catalog.md`
- `07_Implementation Roadmap.md`
- `08_Obsidian Vault Structure.md`

## Manual Import Procedure

1. Open Open WebUI in the Open Workshop context.
2. Navigate to the Workspace knowledge or document area.
3. Create a collection named `workspace_governance_core` if the UI supports collections.
4. Add or upload only the approved source documents listed above.
5. Verify the collection name and the document list before finalizing.
6. Do not enable Private Workshop ingestion.
7. Do not import folders recursively unless each file is individually approved.
8. Record manual import completion after the collection is created or updated.

## Post-Import Validation Questions

Use these questions to validate retrieval behavior:

- What is the current roadmap phase?
- What is the difference between Open Workshop and Private Workshop?
- What content is prohibited from Open WebUI Workspace?
- What is WF-006 allowed to do?
- What is the role of Obsidian versus Open WebUI Workspace?
- What does the Security & Compartmentalization Policy require for Private Workshop material?

## Expected Validation Behavior

- Answers should cite or clearly reflect governance docs.
- Answers should not expose private data.
- Answers should not claim Private Workshop content belongs in Open Workspace.
- Answers should preserve roadmap sequencing.
- Answers should identify Phase 8 as current if roadmap state is up to date.

## Failure Handling

- If retrieval returns stale or wrong roadmap status, re-check the uploaded roadmap document.
- If retrieval suggests importing private material, remove the source and review boundaries.
- If retrieval cannot answer governance questions, check the collection assignment and document upload.
- If accidental prohibited material was uploaded, remove it immediately and document the incident.

## Import Completion Record

After manual import, create `Docs/Workspace_Governance_Core_Import_Record.md`.

The import record should include:

- date and time
- imported documents
- reviewer or importer
- collection name
- validation question results
- issues found
- final status

## Definition Of Done

This runbook is complete when:

- manual import steps are documented
- approved source list is documented
- prohibited import boundaries are documented
- validation questions are documented
- failure handling is documented
- no actual Workspace ingestion is performed by code
