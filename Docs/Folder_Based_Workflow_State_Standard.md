# Folder-Based Workflow State Standard

## Phase 7A.3 Governance Artifact

This document defines the preferred early-phase workflow state model for using visible folders to organize progress and artifacts.

Folder-based state makes workflow progress visible, reviewable, and easy to maintain without introducing a database, queue, event bus, or orchestration system.

This is a governance and documentation standard only.

- It does not create a database.
- It does not create a queue.
- It does not create an event bus.
- It does not create an orchestration layer.
- It does not create a new execution runner.
- It does not replace canonical workflow evidence, approval policy, security policy, or workflow runtime code.

## Purpose

Folder-based workflow state is the preferred early-phase state model when the workflow can be managed with visible filesystem folders.

Folders make workflow progress easy to inspect, simplify handoff review, and keep state artifacts human-readable.

This standard is not a replacement for canonical workflow evidence in `State/Workflow_Evidence/`.

## Scope

This standard applies to:

- WF-001 Research Summary
- WF-002 Codex Task Generator
- WF-005 Note Creation
- WF-006 Knowledge Collection Import Draft
- WF-007 Private Local Analysis
- future workflows when folder state is sufficient

## Standard Folder Model

```text
00_Input/       raw inputs or source material
10_Normalized/  cleaned or normalized working material
20_Working/     drafts, intermediate work, task prep
30_Output/      generated outputs or deliverables
40_Review/      review notes, checklists, acceptance notes
90_Archive/     completed or superseded materials
```

## Rules

- Use folders before databases unless the workflow proves it needs more.
- Folder state is human-readable and reviewable.
- Folder state does not replace canonical workflow evidence.
- Canonical workflow evidence remains in `State/Workflow_Evidence/`.
- Folder paths may be referenced in workflow evidence `artifact_paths`.
- Do not automate deletion in this phase.
- Do not treat folder movement as approval unless approval is recorded separately.
- Do not infer completion from folder names alone when canonical evidence exists.

## Open vs Private Handling

### Open Workshop

- Folder state may live in Project Workspace locations.
- Open Workshop folder state is Category 1 only.
- No secrets or Category 2 material may be stored there.

### Private Workshop

- Folder state must remain inside the Restricted DMZ Workspace.
- No cloud sync.
- No cloud AI routing.
- No Obsidian writes unless the user sanitizes the material first.
- Private folder state stays local-only.

## WF-002 Integration

- WF-002 package folders remain under `Codex_Tasks/TASK-###_short-title/`.
- `Output/` remains compatible with the folder-state model.
- Full folder-state layout is optional for larger Codex tasks.
- Do not require the full folder-state structure inside every WF-002 package unless it is useful.
- Keep the existing required WF-002 package files.
- Do not break the existing WF-002 package standard.

For larger WF-002 tasks, folder state may extend as follows:

```text
Codex_Tasks/TASK-###_short-title/
├── 00_Task.md
├── 01_Context.md
├── 02_Requirements.md
├── 03_Acceptance_Criteria.md
├── 04_Constraints.md
├── 05_Review_Checklist.md
├── 20_Working/
├── 30_Output/
└── 40_Review/
```

## Relationship to Evidence Standard

- Folder state shows workflow progress.
- Evidence records prove workflow status.
- WF-004 should eventually read canonical evidence, not infer status from folder names alone.
- Folder paths can support status reporting only as artifact references or transition fallback.

## Lint Compatibility

- The standard folder names support future structural validation.
- Future lint checks should be able to confirm the presence of the expected folder names.
- This compatibility note does not add any lint implementation.

## Security Rules

- No secrets in Open Workshop folder state.
- No Category 2 data in Open Workshop folder state.
- Private folder state remains local-only.
- Restricted material stays in the Restricted DMZ Workspace or Secure Vault through human transfer.

## Roadmap Update

This standard corresponds to Phase 7A.3 in the implementation roadmap.

It is documentation and governance only.

## Workflow Catalog Update

WF-001, WF-002, WF-005, WF-006, and WF-007 may use folder state where appropriate.

## COOPER Specification Update

COOPER should prefer visible folder state over introducing new databases, queues, or orchestration layers when the workflow is simple enough for folder-based progress tracking.

## WF-002 Package Standard Update

WF-002 package folders may optionally include folder-state subfolders for larger tasks, but the required package files remain unchanged.

## Definition of Done

Phase 7A.3 is complete when:

- `Docs/Folder_Based_Workflow_State_Standard.md` exists
- roadmap references Phase 7A.3
- workflow catalog references the standard
- COOPER specification reflects folder-state preference
- WF-002 package guidance is aligned
- no execution code is changed
- no launcher behavior is changed
- no database, queue, event bus, or orchestration system is introduced
