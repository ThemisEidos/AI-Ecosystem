# AI Judgment / Mechanical Work Separation

## Phase 7A.4 Governance Artifact

This document defines the boundary between AI judgment work and deterministic mechanical script work.

AI should not perform uncontrolled mechanical operations when scripts can do them deterministically.

Scripts should not make judgment calls outside their defined validation logic.

This is a governance and documentation standard only.

- It does not create a new agent system.
- It does not create a new orchestration layer.
- It does not create a task queue.
- It does not create a database.
- It does not create autonomous execution loops.
- It does not change launcher behavior.
- It does not change approval policy.
- It does not change workflow execution code.

## Purpose

The ecosystem should keep judgment and mechanical work separate so COOPER can govern and interpret while scripts perform repeatable actions.

This improves auditability, reduces uncontrolled behavior, and keeps side effects deterministic and testable.

## Scope

This standard applies to:

- COOPER planning and workflow routing
- WF-001 through WF-007
- Codex task packages
- validation scripts
- status checks
- evidence validation
- future workflow automation

## Core Rule

```text
AI handles interpretation.
Scripts handle deterministic execution.
Approval governs side effects.
```

## AI Responsibilities

AI-owned work includes:

- interpret user intent
- identify workflow
- summarize context
- decompose tasks
- identify risks
- review outputs
- assess quality
- recommend next action
- flag ambiguity
- challenge assumptions

## Script Responsibilities

Script-owned work includes:

- create files and folders from approved templates
- validate schema
- validate paths
- validate registry entries
- run status checks
- format deterministic outputs
- check required fields
- enforce known path boundaries
- launch approved tools only after approval
- produce repeatable pass or fail results

## Boundary Rules

- AI may recommend file changes, but scripts should perform repeatable file operations when automation is used.
- AI may review evidence, but scripts should validate evidence schema.
- AI may select a workflow, but router and scripts enforce allowed workflow and tool combinations.
- AI may identify approval need, but approval logic enforces approval state.
- AI may summarize status, but deterministic checks should produce raw status facts.
- Scripts must not silently cross workshop boundaries.
- Scripts must not make open-ended judgment decisions.
- Scripts must fail closed when required inputs are missing.

## Security Benefits

- reduces uncontrolled agent behavior
- improves auditability
- limits accidental data exposure
- preserves Open and Private Workshop boundaries
- reduces risk from broad agent autonomy
- keeps mechanical side effects deterministic and testable

## Relationship to Existing Standards

- [Docs/Workflow_Evidence_Standard.md](Docs/Workflow_Evidence_Standard.md)
- [Docs/WF002_Workflow_Package_Standard.md](Docs/WF002_Workflow_Package_Standard.md)
- [Docs/Minimal_Context_Doctrine.md](Docs/Minimal_Context_Doctrine.md)
- [Docs/Folder_Based_Workflow_State_Standard.md](Docs/Folder_Based_Workflow_State_Standard.md)

Rules:

- folder state remains visible workflow state
- evidence records remain canonical status proof
- minimal context doctrine limits what AI receives
- WF-002 packages provide task-specific context
- scripts validate and create where deterministic

## Workflow Examples

- WF-002: AI drafts task package content; a script may create folders and files from the template.
- WF-004: scripts collect deterministic status; AI summarizes findings.
- WF-007: AI reviews restricted material locally; scripts enforce local path boundaries.
- Evidence validation: AI identifies meaning; scripts validate JSON schema and paths.

## Prohibited Patterns

- AI autonomously editing many files without a scoped task package
- AI deciding to bypass approval because a change seems minor
- scripts deciding content quality
- scripts sending Private Workshop material to cloud
- agent loops replacing governed workflow execution
- hidden side effects not visible to the user
- broad mechanical actions based only on AI judgment

## Roadmap Update

This standard corresponds to Phase 7A.4 in the implementation roadmap.

It is documentation and governance only.

## Workflow Catalog Update

WFs should keep AI judgment separate from deterministic script work.

## COOPER Specification Update

COOPER performs judgment, routing, review, and recommendations. Mechanical side effects should be handled by approved scripts and workflows through governed paths.

## Architecture Update

AI judgment and mechanical execution are separate concerns. COOPER governs and interprets, while scripts and tools perform deterministic work through the Execution Gateway.

## Definition of Done

Phase 7A.4 is complete when:

- `Docs/AI_Judgment_Mechanical_Work_Separation.md` exists
- roadmap references Phase 7A.4
- workflow catalog references the standard
- COOPER specification reflects the separation
- architecture reflects the separation
- no execution code is changed
- no launcher behavior is changed
- no approval logic is changed
- no new agent, orchestration, database, or queue system is introduced
