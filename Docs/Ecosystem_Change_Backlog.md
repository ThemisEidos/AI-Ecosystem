# Ecosystem Change Backlog

## Purpose

This backlog records proposed and under-review ecosystem changes for the AI Ecosystem project.

It is a lightweight governance document only.

- It does not approve changes.
- It does not implement changes.
- It does not change workflow execution code.
- It does not introduce databases, agents, queues, orchestration systems, or new infrastructure.

Backlog inclusion is not approval.

## Governance Rules

1. Every backlog entry must be documentation-first and reviewable by humans.
2. Backlog inclusion means the change is being tracked, not accepted.
3. A change may remain in the backlog even if it is not currently planned for implementation.
4. Changes that require new infrastructure, autonomous orchestration, or execution-code modifications are out of scope for this backlog unless the project explicitly revises scope later.
5. Review notes should stay concise and should point to existing standards or evidence when possible.
6. Status changes should reflect the current review state, not a desired outcome.
7. This backlog should remain lightweight and should not duplicate full design documents.

## Status Values

Use only these status values for backlog items:

- Proposed
- Researching
- Evaluating
- Adopted
- Rejected
- Deferred

## Standard Change-Entry Template

```markdown
### <Change Title>

- Status: <Proposed|Researching|Evaluating|Adopted|Rejected|Deferred>
- Owner: <person or role>
- Added: <YYYY-MM-DD>
- Scope: <short description>
- Rationale: <why this change is being tracked>
- Constraints: <what must not change>
- Review Notes: <current findings or decision context>
- Related Docs: <links to supporting standards or references>
- Next Review: <optional date or trigger>
```

## Initial Entries

### GLM 5.2 Evaluation

- Status: Proposed
- Scope: Evaluate whether GLM 5.2 is suitable for supported local or routed workflow use cases.
- Rationale: Model capability and fit should be tracked separately from implementation decisions.
- Constraints: No deployment decision is implied by tracking this evaluation.
- Review Notes: Keep the evaluation documentation-only until evidence is gathered.
- Related Docs: [Documentation/Model-Catalog.md](../Documentation/Model-Catalog.md)

### Turbo Quant Evaluation

- Status: Proposed
- Scope: Evaluate turbo quantization options for quality, speed, and context retention tradeoffs.
- Rationale: Quantization may affect model selection and workflow reliability.
- Constraints: No runtime change, deployment change, or infrastructure change is implied.
- Review Notes: Track only documented findings and avoid implementation drift.
- Related Docs: [Documentation/Model-Catalog.md](../Documentation/Model-Catalog.md)

### Workflow Package Folders

- Status: Adopted
- Scope: Use standardized folder layouts inside workflow packages where folder structure improves visibility and review.
- Rationale: Folder organization supports clearer task packaging and review.
- Constraints: Do not alter workflow execution code or create new orchestration layers.
- Review Notes: Align with the existing workflow package standard and folder-based workflow state guidance.
- Related Docs: [Docs/WF002_Workflow_Package_Standard.md](WF002_Workflow_Package_Standard.md), [Docs/Folder_Based_Workflow_State_Standard.md](Folder_Based_Workflow_State_Standard.md)

### Minimal Context Doctrine

- Status: Adopted
- Scope: Keep task and workflow context scoped, short, and relevant to the active work.
- Rationale: Smaller context reduces noise and improves reviewability.
- Constraints: Do not replace governing docs with large context dumps.
- Review Notes: This is already established as a governance standard.
- Related Docs: [Docs/Minimal_Context_Doctrine.md](Minimal_Context_Doctrine.md)

### Folder-Based Workflow State

- Status: Adopted
- Scope: Use visible filesystem folders as an early-phase workflow state model when appropriate.
- Rationale: Folder state makes progress visible without introducing heavier systems.
- Constraints: Do not treat folder state as a replacement for canonical evidence.
- Review Notes: Continue to keep folder state and evidence separate.
- Related Docs: [Docs/Folder_Based_Workflow_State_Standard.md](Folder_Based_Workflow_State_Standard.md)

### AI Judgment vs Mechanical Work Separation

- Status: Adopted
- Scope: Keep interpretation and review with AI, while deterministic actions remain script-owned.
- Rationale: Clear separation improves auditability and predictability.
- Constraints: Do not blur judgment work with deterministic execution.
- Review Notes: This should remain a governing principle for future changes.
- Related Docs: [Docs/AI_Judgment_Mechanical_Work_Separation.md](AI_Judgment_Mechanical_Work_Separation.md)

### Workflow Linting Standard

- Status: Adopted
- Scope: Define lightweight structural linting expectations for workflow packages and workflow-state folders.
- Rationale: Linting can catch obvious problems before review or acceptance.
- Constraints: Do not create a linter implementation inside this backlog.
- Review Notes: The standard is documentation-only and intentionally deferred from execution code.
- Related Docs: [Docs/Workflow_Linting_Standard.md](Workflow_Linting_Standard.md)

### Claude Design Evaluation

- Status: Evaluating
- Category: Frontend / UI prototyping
- Added: 2026-06-22
- Scope: Evaluate Claude Design as an external design and prototyping aid for future COOPER dashboard or ecosystem frontend concepts.
- Rationale: A design-focused evaluation may help with dashboard mockups, workflow status UI concepts, approval UI concepts, Open vs Private Workshop mode visualization, and presentation or briefing visuals.
- Constraints: Backlog inclusion is not approval; this is not part of the core runtime, not a workflow engine, not an orchestration layer, not a COOPER replacement, and not authorized to access repo execution, runtime config, credentials, approval logic, or Private Workshop data.
- Review Notes: Category 1 only; no restricted data, no client-sensitive data, no credentials or secrets, and no Private Workshop material. Evaluate later after Phase 7C/7D status evidence work is stable; likely useful for frontend/dashboard prototyping only.
- Related Docs: [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md), [Docs/Ecosystem_Change_Backlog.md](Ecosystem_Change_Backlog.md)
- Next Review: After Phase 7C/7D status evidence work stabilizes.

### Governed Codex Loop

- Status: Deferred
- Category: Governance / Workflow design
- Added: 2026-06-22
- Scope: Define a controlled Codex loop concept for future roadmap-state review, next-task identification, task-package generation, result review, validation gating, and human approval stop points.
- Rationale: The loop is a future concept only; the user chose not to pursue Codex loop design now.
- Constraints: No autonomous execution, no Codex auto-prompting, no automatic commits, no phase advancement without human approval, and no implementation approval at this stage.
- Review Notes: Keep this as backlog-only future design work until separately approved.
- Related Docs: [Docs/Phase_7E_Exit_Review.md](Phase_7E_Exit_Review.md), [07_Implementation Roadmap.md](../07_Implementation%20Roadmap.md)
- Next Review: After a separate approval to resume loop-design work.

## Change Review Guidance

- Proposed: change is identified but not yet examined.
- Researching: evidence gathering is in progress.
- Evaluating: evidence exists and tradeoffs are being weighed.
- Adopted: the project has accepted the change as a documented direction or standard.
- Rejected: the change is not suitable for the project.
- Deferred: the change is valid but not ready for adoption.

## WF-004 Cross-Reference

Backlog reviews should be reflected in WF-004 operational status reporting when the backlog item affects current visibility, governance posture, or workflow standards.

Relevant WF-004 references:

- [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md)
- [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md)

WF-004 should reference this backlog as a review source when reporting status for:

- active governance standards
- workflow packaging conventions
- folder-based workflow state conventions
- documentation-only policy changes
- any item whose status affects current operational interpretation

WF-004 remains the operational status reporting workflow; this backlog is only a review input.

This means:

- backlog review does not change WF-004 behavior by itself
- WF-004 does not approve backlog items
- WF-004 may report the existence and review state of backlog items when relevant
- canonical operational status reporting remains separate from backlog tracking

## Maintenance Notes

- Keep entries short.
- Update status only when there is a real review change.
- Add links to the governing document or evidence source instead of duplicating them.
- Do not use this file to introduce execution logic, agents, queues, orchestration, or databases.
