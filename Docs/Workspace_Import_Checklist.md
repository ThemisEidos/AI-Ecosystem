# Workspace Import Checklist

## Purpose

This checklist defines the human review required before any material enters Open WebUI Workspace.

It is a human review control, not an automated import process.

## Applicability

This checklist applies to:

- manual Workspace imports
- WF-006 drafted collection material
- approved project docs
- sanitized technical references
- approved collection summaries

## Required Pre-Import Checks

Before any import is approved, confirm all of the following:

- collection type matches `Docs/Workspace_Collection_Taxonomy.md`
- material has a clear workflow purpose
- source of truth is identified
- owner is identified
- security category is confirmed as Category 1 / Open Workshop
- sanitization status is confirmed
- review status is confirmed
- prohibited content scan is completed
- duplicate or source-of-truth conflict check is completed
- retention or update plan is identified

## Prohibited Content Review

The reviewer must confirm the material does not contain:

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

## Required Metadata

The import record or collection record must include:

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

## Approval Decision Values

Use one of the following approval decisions:

- `approved_for_workspace`
- `rejected`
- `needs_sanitization`
- `needs_source_review`
- `deferred`

## Relationship To WF-006

- WF-006 may draft candidate material.
- WF-006 output is not approval.
- A human must complete this checklist before ingestion.
- The checklist result should be retained with the collection or import record.

## Manual Import Rule

Direct or manual imports are allowed only after checklist completion.

Manual imports must record:

- source
- category
- reviewer
- approval decision

No bulk imports are allowed without explicit review.

## Definition Of Done

The checklist is complete when:

- all required review fields are defined
- prohibited content rules are included
- approval decision values are defined
- relationship to WF-006 is documented
- no Workspace import implementation is added

## Recommended Next Artifact

`Docs/Workspace_First_Collection_Plan.md`
