# WF-002 Workflow Package Standard

## Phase 7A.1 Governance Artifact

This document defines the WF-002 workflow package as the preferred Codex handoff artifact.

The package improves task clarity, reviewability, and handoff quality by separating the task into a small filesystem-based folder with explicit context, requirements, constraints, and review checks.

This is a file and folder template standard only.

- It does not create an execution framework.
- It does not create an agent system.
- It does not create a task queue.
- It does not create a database or event bus.
- It does not change launcher behavior.
- It does not change approval policy.
- It does not change workflow execution code.

## Scope

- Applies to WF-002 Codex Task Generator.
- Applies to Open Workshop / Category 1 task packages.
- Does not apply to Private Workshop restricted data unless the user has sanitized it before entering WF-002.
- Context inside the package must remain minimal and task-specific per [Docs/Minimal_Context_Doctrine.md](Docs/Minimal_Context_Doctrine.md).
- Larger WF-002 tasks may optionally use the folder-based workflow state model per [Docs/Folder_Based_Workflow_State_Standard.md](Docs/Folder_Based_Workflow_State_Standard.md).

## Non-Goals

This standard does not create:

- new agents
- new orchestration
- task queues
- databases
- event buses
- automatic Codex execution
- recursive Codex loops
- launcher changes
- approval bypasses
- workflow execution changes

## Package Location

Preferred package location:

```text
Codex_Tasks/TASK-###_short-title/
```

Rules:

- Packages live in the Project Workspace under `Codex_Tasks/`.
- Package folders should use a clear short title.
- Package folders should use the pattern `TASK-###_short-title`.
- Existing single-file `TASK-###_short-title.md` files are legacy or fallback format.

## Required Package Structure

```text
Codex_Tasks/
└── TASK-###_short-title/
    ├── 00_Task.md
    ├── 01_Context.md
    ├── 02_Requirements.md
    ├── 03_Acceptance_Criteria.md
    ├── 04_Constraints.md
    ├── 05_Review_Checklist.md
    └── Output/
```

## Required Files

### `00_Task.md`

- Main Codex instruction.
- Objective.
- Expected output.
- Relevant target files or folders.
- Explicit instruction not to exceed scope.

### `01_Context.md`

- Current project state.
- Relevant prior decisions.
- Dependencies.
- Related roadmap phase.
- Related governing docs.
- Known constraints or assumptions.
- Must be scoped and minimal.
- Should reference source docs instead of copying long governance text.
- Should avoid full-history dumps.

### `02_Requirements.md`

- Specific requirements Codex must satisfy.
- Functional requirements.
- Documentation requirements.
- Security and governance requirements.
- Files expected to be created or updated.

### `03_Acceptance_Criteria.md`

- Definition of done.
- Pass or fail criteria.
- Validation expectations.
- Required tests or docs checks if applicable.

### `04_Constraints.md`

- Prohibited actions.
- Scope limits.
- Security boundaries.
- No secrets or Category 2 material.
- No execution or launcher changes unless explicitly approved.
- No infrastructure expansion.
- Should include only task-relevant constraints plus mandatory security boundaries.
- Should avoid duplicating the full governing docs.

### `05_Review_Checklist.md`

- Human or COOPER review checklist.
- Confirm expected files changed.
- Confirm no prohibited files changed.
- Confirm no sensitive content included.
- Confirm roadmap alignment.
- Confirm tests or checks run if applicable.
- Confirm commit message.

### `Output/`

- Destination for Codex-generated outputs, review notes, logs, drafts, or result artifacts when needed.
- Should not be used for canonical workflow evidence.
- Canonical workflow evidence remains under `State/Workflow_Evidence/` per [Docs/Workflow_Evidence_Standard.md](Docs/Workflow_Evidence_Standard.md).
- For larger WF-002 tasks, `Output/` may coexist with optional `20_Working/`, `30_Output/`, and `40_Review/` folders, but the required WF-002 files remain mandatory.

## Optional Files

Optional later files for future use:

- `06_Implementation_Notes.md`
- `07_Test_Plan.md`
- `08_Codex_Run_Log.md`

## Evidence Compatibility

- WF-002 workflow package folders are artifacts.
- Canonical workflow evidence must reference the package folder path in `artifact_paths`.
- Do not store canonical workflow completion records inside the package.
- Canonical workflow evidence remains governed by [Docs/Workflow_Evidence_Standard.md](Docs/Workflow_Evidence_Standard.md).

Example artifact reference:

```json
"artifact_paths": [
  "Codex_Tasks/TASK-123_workflow-package-standard/"
]
```

## Security Rules

- WF-002 packages are Open Workshop / Category 1 artifacts.
- Do not include secrets, API keys, credentials, private keys, tokens, client-sensitive data, investigative material, restricted logs, unredacted sensitive reports, or Category 2 material.
- If source material is Category 2, the user must sanitize it before it enters WF-002.
- If the task cannot be sanitized, do not create a WF-002 package; redirect to Private Workshop planning instead.
- WF-002 packages must not be written to Obsidian unless intentionally sanitized and moved by the user as Category 1 material.
- WF-002 packages must not weaken Private Workshop boundaries.

## Approval and Permission Rules

- Creating a WF-002 package is a Level 2 local write and requires approval.
- Launching Codex CLI or app context remains Level 4 and requires separate approval.
- Package creation does not authorize launcher execution.
- Package creation does not authorize code changes.
- The user remains responsible for starting or confirming Codex work.

## Backward Compatibility

- Single-file `TASK-###_short-title.md` remains allowed as a legacy or fallback format.
- Preferred format going forward is the package folder.
- Existing task files do not need migration unless useful.
- Optional folder-state subfolders may be added for larger tasks, but they do not replace the required WF-002 files.

## Future WF-002 Generator Requirements

These are future requirements for generator work, not implementation in this phase.

- WF-002 generator should eventually create the package folder.
- Generator should populate required markdown files.
- Generator should create `Output/`.
- Generator should reject or warn on Category 2 content.
- Generator should record the package folder path as an artifact in canonical evidence when evidence emitters exist.
- Generator changes are deferred until separately approved.
- Generator should keep context sections minimal and reference [Docs/Minimal_Context_Doctrine.md](Docs/Minimal_Context_Doctrine.md) rather than duplicating governance.
- Generator may optionally create folder-state subfolders for larger tasks per [Docs/Folder_Based_Workflow_State_Standard.md](Docs/Folder_Based_Workflow_State_Standard.md).

## Definition of Done

Phase 7A.1 is complete when:

- `Docs/WF002_Workflow_Package_Standard.md` exists.
- Required package structure is defined.
- Required file purposes are defined.
- `Output/` usage is defined.
- Security rules prohibit Category 2 content and secrets.
- Approval and launcher boundaries are preserved.
- Evidence compatibility is defined.
- Single-file task format is marked legacy or fallback.
- Workflow catalog is updated.
- COOPER System Specification is updated.
- No workflow execution code is changed.
- No new infrastructure is introduced.
