# Workflow Evidence Standard

## Phase 7A Governance Artifact

This document defines the canonical evidence records used by WF-004 and future workflow status reporting.

It is a file-based standard only.

- It does not introduce a database.
- It does not introduce an event bus.
- It does not introduce agents or new orchestration.
- It does not replace the existing workflow runtime or approval policy.
- It defines the records that workflow code should write, read, and preserve.
- It defines the file-based standard for Phase 7A and the validation target for Phase 7B.

## Purpose

WF-004 currently has to reconcile multiple evidence sources:

- workflow artifacts
- state files
- project memory
- approval records
- workflow-specific outputs

That mixed-source approach has been adequate for Phase 5 and Phase 6 operations, but it is not a stable long-term source of truth.

Phase 7A establishes a canonical file-based evidence shape so WF-004 can eventually consume structured workflow records directly.

## Core Principles

1. Evidence is file-based and human-auditable.
2. Open Workshop and Private Workshop evidence remain separated.
3. Private Workshop evidence stays inside the Restricted DMZ Workspace unless it is explicitly sanitized for Open Workshop use.
4. Evidence records must not include secrets, credentials, private keys, tokens, or raw restricted material.
5. Workflow execution code must not mutate historical evidence once the record is complete.
6. WF-004 may use artifact fallback during the transition period, but canonical records are the intended primary source of truth.

## Canonical Record Types

### 1. Workflow Completion Record

This is the canonical record that states a workflow completed, what it produced, and how it was reviewed.

### 2. Approval Lifecycle Record

This is the canonical record that tracks an approval request from creation through approval, completion, staleness, blocking, or rejection.

## Canonical Workflow Completion Record

### Canonical Serialization

- Canonical machine-readable format: `JSON`
- Phase 7B writers and readers must produce and consume canonical JSON records
- YAML may appear only as illustrative documentation examples, not as implementation evidence
- Each record must be a single JSON object per file
- Field names must remain stable and snake_case

### Required Fields

- `workflow_id`
- `workflow_name`
- `execution_id`
- `status`
- `completion_time`
- `workshop_id`
- `workshop_name`
- `approval_id`
- `artifact_paths`
- `review_status`
- `user_accepted`
- `notes`

### Optional Fields

- `requested_time`
- `started_time`
- `completed_by`
- `requested_by`
- `trigger`
- `source_of_truth`
- `workflow_chain`
- `parent_workflow_id`
- `run_context`
- `limitations`
- `next_action`
- `artifact_summary`
- `review_notes`

### Field Definitions

- `workflow_id`: stable workflow identifier such as `WF-001`.
- `workflow_name`: human-readable workflow name.
- `execution_id`: unique id for one execution instance.
- `status`: final workflow status value.
- `completion_time`: timestamp of the execution completion.
- `workshop_id`: `open` or `private`.
- `workshop_name`: `Open Workshop` or `Private Workshop`.
- `approval_id`: related approval record id, or an empty string when not applicable.
- `artifact_paths`: a JSON array of one or more file paths or artifact references produced by the workflow; use an empty array when nothing was produced.
- `review_status`: review outcome for the workflow output. Use the Phase 7A workflow status values: `pass`, `fail`, `blocked`, or `unknown`.
- `user_accepted`: boolean indicating whether the user accepted the result.
- `notes`: free-text summary, excluding sensitive material.

### Workflow Status Values

- `pass`
- `fail`
- `blocked`
- `unknown`

### Workflow Completion Semantics

- `pass` means the workflow completed and produced an acceptable result record.
- `fail` means the workflow completed but did not satisfy requirements or review.
- `blocked` means execution stopped due to policy, missing approval, missing prerequisites, or restricted boundary enforcement.
- `unknown` means the workflow has no canonical completion record yet or its status cannot be established from the canonical record.
- `review_status` must use the same value set unless a future phase explicitly expands it.

## Canonical Approval Lifecycle Record

### Canonical Serialization

- Canonical machine-readable format: `JSON`
- Phase 7B writers and readers must produce and consume canonical JSON records
- YAML may appear only as illustrative documentation examples, not as implementation evidence
- Each record must be a single JSON object per file
- Field names must remain stable and snake_case

### Required Fields

- `approval_id`
- `workflow_id`
- `status`
- `requested_time`
- `approved_time`
- `completed_time`
- `blocked_time`
- `stale_time`
- `expiration_time`
- `reason`
- `notes`

### Optional Fields

- `requested_by`
- `approved_by`
- `completed_by`
- `blocked_by`
- `stale_by`
- `policy_reference`
- `request_summary`
- `decision_summary`
- `related_execution_id`
- `artifact_paths`
- `workshop_id`
- `workshop_name`

### Approval Status Values

- `pending`
- `approved`
- `completed`
- `stale`
- `blocked`
- `rejected`

### Approval Lifecycle Semantics

- `pending` means the approval request is active and awaiting a decision.
- `approved` means the request was authorized, but the governed action has not yet been completed.
- `completed` means the governed action finished and the approval can no longer count as active pending work.
- `stale` means the approval aged out or expired without being completed in time.
- `blocked` means the request was denied by policy, boundary rules, or governance constraints.
- `rejected` means a human or policy decision explicitly denied execution.

## Canonical Storage Expectations

The standard is file-based. Implementation records must be written as JSON files at the locations below.

### Recommended Workflow Evidence Locations

#### Open Workshop

- `State/Workflow_Evidence/completion/`
- `State/Workflow_Evidence/approval/`
- `State/Workflow_Evidence/archive/`

#### Private Workshop

- `Restricted DMZ Workspace/State/Workflow_Evidence/completion/`
- `Restricted DMZ Workspace/State/Workflow_Evidence/approval/`
- `Restricted DMZ Workspace/State/Workflow_Evidence/archive/`

- Category 1 evidence may live in normal project state.
- Category 2 / Private Workshop evidence must remain inside the Restricted DMZ Workspace unless sanitized by the user.
- Private evidence must not be routed to cloud AI or written into Open Workshop state.
- Sanitized Open Workshop summaries may be copied out of the Restricted DMZ Workspace only after sensitive content is removed.

### Recommended Approval Record Locations

- Approval records should live in the same governed file system region as the workflow that created them.
- Private Workshop approvals should remain in Restricted DMZ storage unless sanitized copies are explicitly required for Open Workshop reporting.

### Filename Patterns

- Workflow completion record: `workflow_completion_<workflow_id>_<execution_id>.json`
- Approval lifecycle record: `approval_lifecycle_<approval_id>.json`
- Archived records preserve the original filename
- Archived records move under the appropriate `archive/` path
- Archived records must not be renamed unless required to prevent filename collision

### Timestamp Format

- Mandatory format: ISO 8601 UTC
- Example: `2026-06-21T20:30:12Z`
- Apply to `completion_time`, `requested_time`, `approved_time`, `completed_time`, `blocked_time`, `stale_time`, and `expiration_time`
- Use `null` when a lifecycle timestamp does not apply yet

## Retention Rules

### Workflow Completion Records

- Active records remain in the active evidence folders while status is `pending`, `approved`, `blocked`, `stale`, or `unknown`.
- `pass` records may be archived after they are no longer needed for active WF-004 reporting.
- `fail`, `blocked`, `stale`, and `unknown` records remain active until reviewed or superseded.
- Keep the most recent canonical completion record for each workflow execution.
- Retain historical records long enough for operational review, audit, and workflow regression analysis.
- Do not overwrite a prior execution record with a newer run.
- Do not collapse distinct executions into one mutable record.
- No automated deletion is authorized in this phase.

### Approval Lifecycle Records

- Active records remain in the active evidence folders while status is `pending`, `approved`, `blocked`, or `stale`.
- `completed` approval records remain recorded as history and must not continue to count as pending.
- `rejected` approval records remain visible as historical records.
- Approval records must not be archived before the related workflow completion record.
- Retain the full approval lifecycle for auditability.
- A completed approval must remain recorded as history.
- A completed approval must not continue to count as pending.
- A stale or rejected approval must remain visible as a historical record.
- No automated deletion is authorized in this phase.

### Practical Retention Guidance

- Active records should remain immediately queryable.
- Historical records should remain discoverable for governance review.
- Archival thresholds should be file-based and deterministic, not hidden inside runtime code.
- If a fixed retention window is needed for tests or migration scaffolding, use a conservative active reporting window of 30 days.
- Archive eligibility for `pass` records with `user_accepted: true` begins after 30 days.
- No deletion window is defined.

## Archival Rules

### Workflow Completion Records

- Archive completed records once they are no longer needed for active WF-004 reporting.
- Archived records must remain readable and attributable to their original workflow and execution id.
- Archived records must preserve the original status, completion time, and artifact references.
- Archived records must stay inside the appropriate Open Workshop or Restricted DMZ archive path.

### Approval Lifecycle Records

- Archive resolved approvals only after they are no longer active.
- Resolved means `completed`, `stale`, `blocked`, or `rejected`.
- Archived approval history must remain available for governance review.
- Approval records must not be archived before the related workflow completion record.

### Restricted DMZ Archival Rules

- Private Workshop evidence may be archived inside the Restricted DMZ Workspace.
- If evidence is exported to Open Workshop space, it must first be sanitized by the user.
- Sanitization must remove secrets, raw restricted content, and any data that would violate compartment boundaries.

## WF-004 Consumption Rules

WF-004 should eventually use canonical workflow completion records and approval lifecycle records as the primary source of truth.

### Required Behavior

- WF-004 should prefer canonical completion records over scattered artifact inference whenever a canonical record exists.
- WF-004 should prefer canonical approval lifecycle records over counting raw approvals or pending state files.
- WF-004 must not mutate workflow evidence records.
- WF-004 must continue to emit canonical workflow chain formatting: `WF-001 → WF-006`.
- WF-004 may use artifact fallback only when canonical records are missing or incomplete during the transition period.
- Canonical evidence records are authoritative when present.
- Artifact fallback is transition-only and lower priority than canonical records.
- WF-004 should select the latest execution by `completion_time`, then `execution_id` as a tie-breaker.
- If multiple records conflict for the same `workflow_id` and `execution_id`, WF-004 should surface an evidence conflict instead of silently choosing one.
- If approval and completion records disagree, WF-004 should surface an approval/evidence mismatch.
- If a canonical record exists but referenced artifacts are missing, WF-004 should report `pass` with warning or `unknown` depending on the record status and missing artifact severity.
- If no canonical record exists, WF-004 may use legacy artifact fallback and must label the result as transition fallback.

### Transition Behavior

Until every workflow consistently writes canonical evidence:

- WF-004 may merge canonical records with artifact fallback.
- WF-004 should clearly distinguish canonical evidence from fallback evidence in its internal reasoning.
- WF-004 should treat fallback as transitional, not authoritative, when canonical records are available.
- WF-004 should report evidence conflicts and approval/evidence mismatches explicitly.

### WF-004 Reporting Expectations

- report workflow status as `pass`, `fail`, `blocked`, or `unknown`
- report approval status as `pending`, `approved`, `completed`, `stale`, `blocked`, or `rejected`
- include artifact paths only when they are available and safe to report
- keep private evidence isolated from Open Workshop summaries unless sanitized

## Workflow Implementation Requirements

### WF-001 Research Summary

- write a canonical workflow completion record
- include source-backed artifact paths
- include review status and user acceptance outcome
- preserve Open Workshop evidence in normal project state

### WF-002 Codex Task Generator

- write a canonical workflow completion record for each generated task
- include the task file path as an artifact path
- record approval linkage when execution required approval
- keep Open Workshop evidence in project workspace storage

### WF-003 Prompt Helper

- if operational, write a completion record when it produces a governed output
- keep the evidence minimal and non-sensitive
- preserve Open Workshop separation
- future/deferred evidence types are not valid for Phase 7A records

### WF-004 Operational Status

- write a canonical completion record when the status report is generated successfully
- include the report artifact or summary path when one exists
- record review status for the generated status summary
- do not treat its own evidence as mutable runtime state
- use canonical JSON evidence records as the primary status source when available
- treat non-canonical fallback evidence as transitional only

### WF-005 Note Creation

- write a canonical completion record for each note creation execution
- include the created note path
- record whether the note was accepted or rejected by review
- keep private note evidence in the correct workshop compartment

### WF-006 Knowledge Collection Import Draft

- write a canonical completion record for each import draft execution
- include the draft artifact path
- preserve source provenance where available
- keep Open Workshop evidence in normal project storage

### WF-007 Private Local Analysis

- write a canonical completion record for each private execution
- keep the record and artifact paths inside the Restricted DMZ Workspace
- record approval linkage and review status
- do not route private workflow evidence to cloud AI
- sanitize any Open Workshop-facing summary before it leaves the Restricted DMZ Workspace
- never write private evidence directly into Open Workshop state

## Security Rules

- Evidence records must not contain secrets, API keys, credentials, private keys, session tokens, or raw sensitive content.
- Private workflow evidence must remain local-only and must not be forwarded to cloud models.
- Private evidence may be summarized for Open Workshop reporting only if the summary is sanitized.
- Open Workshop evidence must not collapse restricted evidence into a general workspace file without sanitization.
- Evidence files should be treated as governed artifacts, not raw conversation logs.
- Category 1 evidence may live in normal project state.
- Category 2 / Private Workshop evidence must remain inside Restricted DMZ Workspace unless sanitized by the user.
- Private workflow evidence must not be routed to cloud AI.
- Future or deferred status values are not valid for Phase 7A records.

## Canonical Chain Formatting

WF-004 must preserve canonical chain formatting exactly as:

`WF-001 → WF-006`

If additional chains are reported later, they should use the same canonical arrow formatting and should not be duplicated by ASCII-only variants.

## Implementation Notes

This standard intentionally stops short of defining a persistence subsystem.

Future implementation work may add writer helpers, loaders, validators, or migration scripts, but the canonical structure itself remains file-based and workflow-owned.

Phase 7A is about making evidence consistent enough that WF-004 can trust it without guessing.

## Definition of Done

Phase 7A is complete only when:

- canonical JSON serialization is defined
- exact storage paths are defined
- filename patterns are defined
- timestamp format is defined
- WF-004 precedence and conflict rules are defined
- retention and archival rules are testable
- Open/Private evidence separation is preserved
- roadmap and catalog cross-references are updated
- no workflow execution code is changed
