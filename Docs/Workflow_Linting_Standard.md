# Workflow Linting Standard

## Phase 7A.5 Governance Artifact

This document defines lightweight workflow linting as a pre-execution and pre-acceptance quality pattern.

Linting checks structure, metadata, and obvious security risks.

Linting does not replace human review, COOPER review, approval policy, or canonical workflow evidence.

This is a governance and documentation standard only.

- It does not create a linter implementation.
- It does not create a database.
- It does not create a queue.
- It does not create an event bus.
- It does not create an orchestration layer.
- It does not change launcher behavior.
- It does not change approval policy.
- It does not change workflow execution code.

## Purpose

The project should be able to check workflow packages and workflow-state folders for obvious structural and security problems before execution or acceptance.

Lightweight linting helps catch missing files, missing metadata, bad paths, and obvious secret exposure early.

Linting is not a substitute for human judgment, COOPER review, approval controls, or canonical workflow evidence.

## Scope

This standard applies to:

- WF-002 workflow packages
- folder-based workflow state folders
- future workflow packages
- future validation scripts

This standard does not apply to:

- unrestricted ad hoc notes
- Secure Vault contents
- StandardNotes
- human-only private notes

## Core Rule

```text
Workflow packages should be structurally valid before execution or acceptance.
```

## Required Lint Checks

### Structure

- required files exist
- required folders exist
- package path is valid
- naming pattern is valid

### Metadata

- workflow ID declared
- workflow name declared
- workshop declared
- permission level declared
- approval requirement declared
- target files or folders declared when applicable

### Task Quality

- objective exists
- requirements exist
- acceptance criteria exist
- constraints exist
- review checklist exists
- output expectations are clear

### Security

- no obvious secrets
- no API keys
- no credentials
- no private keys
- no tokens
- no Category 2 material in Open Workshop packages
- no Private Workshop material routed to cloud paths
- no unrestricted destructive instructions

### Governance

- workshop matches workflow
- permission level matches action type
- launcher action separated from package creation
- evidence compatibility is declared where relevant
- prohibited actions are listed

## WF-002 Lint Profile

WF-002 packages should eventually satisfy these checks:

- folder name matches `TASK-###_short-title`
- required files exist:
  - `00_Task.md`
  - `01_Context.md`
  - `02_Requirements.md`
  - `03_Acceptance_Criteria.md`
  - `04_Constraints.md`
  - `05_Review_Checklist.md`
  - `Output/`
- package declares Open Workshop
- package declares Level 2 for package creation
- launcher invocation remains Level 4 and separate
- package contains no secrets or Category 2 material
- acceptance criteria exist
- review checklist exists

## Folder-State Lint Profile

Workflow-state folders should eventually satisfy these checks:

- allowed folder names:
  - `00_Input/`
  - `10_Normalized/`
  - `20_Working/`
  - `30_Output/`
  - `40_Review/`
  - `90_Archive/`
- folder state does not replace canonical evidence
- private folder state remains inside Restricted DMZ Workspace
- archive folder use does not imply deletion authorization

## Lint Result Model

Future lint results should use these values:

```text
pass
warning
fail
blocked
```

Result meanings:

- `pass`: structure and required fields are present
- `warning`: non-blocking issue
- `fail`: missing required structure or metadata
- `blocked`: security or governance violation

## Security Handling

- secret detection is best-effort and not a guarantee
- suspected secrets should produce `blocked`
- suspected Category 2 content in Open Workshop packages should produce `blocked`
- linting must not print or copy suspected secret values into logs

## Relationship to Existing Standards

- [Docs/WF002_Workflow_Package_Standard.md](Docs/WF002_Workflow_Package_Standard.md)
- [Docs/Folder_Based_Workflow_State_Standard.md](Docs/Folder_Based_Workflow_State_Standard.md)
- [Docs/Workflow_Evidence_Standard.md](Docs/Workflow_Evidence_Standard.md)
- [Docs/Minimal_Context_Doctrine.md](Docs/Minimal_Context_Doctrine.md)
- [Docs/AI_Judgment_Mechanical_Work_Separation.md](Docs/AI_Judgment_Mechanical_Work_Separation.md)

Rules:

- linting validates package structure
- evidence proves workflow status
- folder state shows visible workflow progress
- AI judgment reviews quality
- scripts eventually perform deterministic lint checks

## Future Implementation Note

- actual lint scripts are deferred
- likely future artifacts:
  - `Scripts/Test-COOPERWorkflowPackageLint.ps1`
  - `Scripts/Test-COOPERWF002WorkflowPackage.ps1`
- script implementation should occur during Phase 7B or later
- this phase defines the standard only

## Roadmap Update

This standard corresponds to Phase 7A.5 in the implementation roadmap.

It is documentation and governance only.

## Workflow Catalog Update

WF-002 packages should eventually be lintable.

## WF-002 Package Standard Update

WF-002 packages should remain structured so a future lint script can validate them.

## Folder-State Standard Update

The standard folder names support future validation.

## Definition of Done

Phase 7A.5 is complete when:

- `Docs/Workflow_Linting_Standard.md` exists
- roadmap references Phase 7A.5
- workflow catalog references the standard
- WF-002 package standard references linting compatibility
- folder-state standard references linting compatibility
- no linter code is created
- no execution code is changed
- no launcher behavior is changed
- no new database, queue, agent, or orchestration system is introduced
