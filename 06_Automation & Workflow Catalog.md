# Automation & Workflow Catalog

## Purpose

This document catalogs proven workflows that COOPER can route to approved execution paths.

The intent is to keep the first workflow set useful and small.

Phase 5 workflows are operational. Phase 6 Private Workshop Hardening is complete. Phase 7A workflow evidence standardization is now the documentation focus for deterministic WF-004 reporting.
Phase 7A workflow evidence standardization is documented in `Docs/Workflow_Evidence_Standard.md`.
Phase 7A.1 WF-002 workflow package standard is documented in `Docs/WF002_Workflow_Package_Standard.md`.
Phase 7A.2 minimal context doctrine is documented in `Docs/Minimal_Context_Doctrine.md`.
Phase 7A.3 folder-based workflow state is documented in `Docs/Folder_Based_Workflow_State_Standard.md`.
Phase 7A.4 AI judgment / mechanical work separation is documented in `Docs/AI_Judgment_Mechanical_Work_Separation.md`.
Phase 7A.5 lightweight workflow linting is documented in `Docs/Workflow_Linting_Standard.md`.
WF-001 through WF-007 must eventually emit canonical workflow evidence records that conform to the Phase 7A standard.
Workflows should keep AI judgment separate from deterministic script work.
WF-002 packages should eventually be lintable before execution or acceptance.

Storage rules:

- Open Workshop writes to Obsidian or Project Workspace with approval.
- Private Workshop writes only to the Restricted DMZ Workspace.
- COOPER Private never writes directly to Secure Vault or StandardNotes.
- Fabric is the reusable prompt-pattern layer.
- Open WebUI Workspace is the knowledge and reference-asset layer.
- Workspace should not hold registries, approval rules, runtime state, secrets, private data, or personality state.

## Workflow Approval Matrix

Higher-risk workflows continue to require explicit confirmation. The approved low-risk workflows below may use governed routing and, where policy allows, low-friction dispatch.

| Workflow                                 | Behavior                                       | Risk | Write Location                             | External Access             |
| ---------------------------------------- | ---------------------------------------------- | ---- | ------------------------------------------ | --------------------------- |
| WF-001 Research Summary                  | Direct execution after governed routing/review | Low  | Obsidian Agent Findings/Research           | Approved official docs only |
| WF-002 Codex Task Generator              | Auto-dispatch for task file generation         | Low  | Codex_Tasks/                               | None                        |
| WF-005 Note Creation                     | Direct execution after governed routing/review | Low  | Obsidian Agent Findings/Drafts             | None                        |
| WF-006 Knowledge Collection Import Draft | Chained after WF-001 review pass               | Low  | Obsidian Agent Findings/Collection Imports | None                        |
| WF-007 Private Local Analysis            | Private Workshop local-only execution          | Med  | Restricted DMZ Workspace                   | None                        |

## WF-001 Research Summary

- Purpose: turn source material into a concise research brief
- Workshop: Open Workshop
- Trigger: user requests research, summary, analysis, or a source-backed brief
- Inputs: approved official sources, notes, links, source excerpts
- Tools Used: COOPER, approved source retrieval, writing model, Obsidian
- Execution Method: direct execution after governed routing and review
- Permission Level: 1
- Approval Requirement: required if external execution or side effects are involved
- Output: structured research summary
- Storage Location: Obsidian Agent Findings/Research
- Security Notes: approved official docs only
- Status: Operational
- Next Step: keep source collection, review enforcement, and artifact-path reporting stable
- Folder State: may use the standard visible folder layout where useful
- Mechanical Work: AI should handle interpretation and review while scripts perform repeatable mechanical work when automation is used

## WF-002 Codex Task Generator

- Purpose: turn project discussion, decisions, findings, and requirements into a structured Codex task file
- Workshop: Open Workshop
- Trigger: task requests, implementation requests, project decisions, findings, or workflow outputs
- Inputs: project context, requirements, target repo, desired outcome
- Tools Used: COOPER, writing model, task template, Codex_Tasks folder, governed workbench
- Execution Method: auto-dispatch for approved low-risk task generation
- Permission Level: 2 for package creation; 4 for launcher invocation
- Approval Requirement: required
- Output: Codex task package folder or legacy fallback task file
- Storage Location: Project Workspace Codex_Tasks/
- Security Notes: do not include secrets, API keys, credentials, private keys, or Category 2 material
- Status: Operational
- Next Step: keep launcher invocation separate from task generation unless explicitly requested
- Preferred Artifact Format: workflow package folder
- Preferred Package Path: `Codex_Tasks/TASK-###_short-title/`
- Legacy or Fallback File Format: `TASK-###_<short-title>.md`
- Standard Reference: `Docs/WF002_Workflow_Package_Standard.md`
- Package Structure: use the required folder layout defined in the standard
- Context Standard: keep `01_Context.md` minimal and task-specific; reference `Docs/Minimal_Context_Doctrine.md`
- Constraints File: keep `04_Constraints.md` limited to task-relevant constraints plus mandatory security boundaries
- Folder State: for larger tasks, optional `20_Working/`, `30_Output/`, and `40_Review/` folders may be added; keep the required WF-002 files intact
- Mechanical Work: AI drafts the package contents while scripts may create template-based files and folders
- Linting: WF-002 packages should be structured so future lint scripts can validate required files, metadata, and security boundaries

### WF-002 Phases

- Phase 1 - Manual
  - COOPER generates a Codex-ready task prompt.
  - User may manually copy or paste it into Codex if desired.
  - No workflow dispatch.
- Phase 2 - Semi-Automated
  - COOPER writes a task file to `Codex_Tasks/`.
  - Governed routing and approval determine whether dispatch can proceed automatically.
  - Task generation is the selected near-term target.
- Phase 3 - Integrated / Deferred
  - COOPER directly invokes Codex CLI.
  - Treat as Level 4 execution.
  - Requires explicit approval.
  - Deferred until Phase 2 is stable.

### Future Workspace and Fabric Phases

- Open WebUI Workspace Knowledge Layer
  - Purpose: organize governance documents, reference libraries, and project knowledge collections.
  - Status: Future
  - Notes: cloud-connected collections remain Category 1 only unless the Workspace is confirmed local-only and Private Workshop safe.
- Fabric Prompt Pattern Layer
  - Purpose: store reusable prompt patterns for analysis, summarization, report review, threat analysis, and decision support.
  - Status: Future
  - Notes: patterns must not contain secrets, runtime state, or registry logic.

## Workflow Definition of Done

A workflow is considered complete only when the resulting output has been reviewed and determined to satisfy the original objective, requirements, and success criteria.

Successful execution alone does not constitute completion.

A workflow should pass the following validation stages:

### 1. Execution Validation

The workflow completed without errors and produced the expected output artifact.

Examples:

- report generated
- note created
- presentation produced
- analysis completed
- workflow status returned

### 2. Requirement Validation

The output is evaluated against the original task request.

Validation should determine whether:

- the objective was achieved
- required deliverables were produced
- requested constraints were followed
- expected outputs were generated

### 3. Quality Review

COOPER should review the output using reasoning and contextual understanding.

The review should evaluate:

- completeness
- accuracy
- relevance
- consistency
- usefulness
- alignment with the original task

COOPER may identify deficiencies, risks, omissions, or opportunities for improvement.

### 4. Human Acceptance

The user remains the final authority for acceptance.

A workflow is considered Operationally Complete when:

- execution succeeded
- requirements were met
- quality review passed
- the user accepts the result

### Continuous Improvement

If validation identifies deficiencies, COOPER may recommend revisions, additional workflow steps, or a follow-on workflow.

Workflow completion is measured by outcome quality, not by workflow execution alone.

## WF-003 Codex Prompt Helper

- Purpose: generate a short manual Codex prompt when a task file is not needed
- Workshop: Open Workshop
- Trigger: user wants a quick prompt only
- Inputs: objective, constraints, desired output
- Tools Used: COOPER, writing model, prompt template
- Execution Method: human-reviewed prompt generation
- Permission Level: 0
- Approval Requirement: required if the generated prompt includes side effects
- Output: Codex-ready prompt text
- Storage Location: Project Workspace or temporary working notes
- Security Notes: keep sensitive details out of the prompt
- Status: Future
- Next Step: keep as a fallback only

## WF-004 Operational Status

- Purpose: summarize the health and readiness of the ecosystem from runtime state
- Workshop: Open Workshop
- Trigger: user asks what is operational, what can you do, or show system status
- Inputs: roadmap phase, workflow definitions, project memory, skill state, recent activity
- Tools Used: COOPER, status sources, dashboard data, workflow definitions
- Execution Method: read-only status aggregation
- Permission Level: 1
- Approval Requirement: none for read-only status
- Output: operational status summary
- Storage Location: read-only summary only
- Security Notes: do not include secrets
- Status: Operational
- Next Step: keep the runtime summary aligned with state files, workflow definitions, and approval lifecycle categories
- Operational Chains: WF-001 → WF-006 and WF-001 → WF-006 → WF-002
- Private Workshop hardening: private-tool routing remains local-only and registry-separated from Open Workshop
- Evidence standard: `Docs/Workflow_Evidence_Standard.md`
- WF-004 should eventually treat canonical workflow evidence records as the primary source of truth

## WF-005 Note Creation

- Purpose: create a structured note in the vault
- Workshop: Open Workshop or Private Workshop
- Trigger: new idea, decision, summary, or reusable reference
- Inputs: title, body, tags, target folder
- Tools Used: COOPER, note template, Obsidian
- Execution Method: direct execution after governed routing and review
- Permission Level: 2
- Approval Requirement: required if the note creation writes to a governed location
- Output: new note
- Storage Location: Obsidian Agent Findings/Drafts
- Security Notes: private notes must stay in the restricted compartment
- Status: Operational
- Next Step: keep the note workflow aligned with governed storage boundaries
- Folder State: may use the standard visible folder layout where useful
- Mechanical Work: scripts should gather deterministic status facts while AI summarizes findings
- Linting: folder state should use standard folder names so future validation is straightforward

## WF-006 Knowledge Collection Import Draft

- Purpose: turn approved research output into a collection import draft
- Workshop: Open Workshop
- Trigger: approved research summary, collection curation request, or follow-on import drafting
- Inputs: source-backed research summary, source list, target collection
- Tools Used: COOPER, writing model, governed workbench, Obsidian
- Execution Method: chained after WF-001 review pass
- Permission Level: 2
- Approval Requirement: required if governed write is involved
- Output: knowledge collection import draft
- Storage Location: Obsidian Agent Findings/Collection Imports
- Security Notes: only approved sources and source URLs should be carried forward
- Status: Operational
- Next Step: keep the WF-001 -> WF-006 chain stable
- Folder State: may use the standard visible folder layout where useful
- Mechanical Work: AI can recommend the analysis approach while scripts enforce local path boundaries and repeatable file operations
- Linting: workflow folders should remain predictable enough for future structural validation

## WF-007 Private Local Analysis

- Purpose: analyze restricted data without leaving the local environment
- Workshop: Private Workshop
- Trigger: user provides restricted local material
- Inputs: local files, notes, logs, or exports
- Tools Used: COOPER Private, local scripts, local models, encrypted storage
- Execution Method: local-only workflow
- Permission Level: 4
- Approval Requirement: required for governed actions
- Output: restricted analysis note or local summary
- Storage Location: Restricted DMZ Workspace
- Security Notes: no cloud AI, no external webhooks, no plain-text sensitive logging
- Status: Operational
- Next Step: keep routing local-only, approval-gated, and restricted to the private registry
- Folder State: may use the standard visible folder layout inside the Restricted DMZ Workspace
- Mechanical Work: AI may review restricted material locally while scripts enforce path and boundary checks
- Linting: private folder state should remain local-only and use standard folder names when possible

## Glossary

- Workshop: the selected operating environment
- Tool Box: the approved capability set for a workshop
- Drawer: a grouped capability area
- Tool: a callable capability, model, script, or workflow
- Quartermaster: the organizer of approved tools and storage
- Safety Officer: the policy control that blocks unsafe paths
- Workbench: the active execution surface
- Knowledge Shelf: general-reference storage
- Project Workspace: general working files
- Restricted DMZ Workspace: active private processing area
- Secure Vault: VeraCrypt long-term encrypted storage, human-managed
- StandardNotes: human-only secure notes
- Codex Task Queue: Project Workspace folder for WF-002 task files
- Open WebUI Workspace: knowledge and reference-asset layer
- Fabric: reusable prompt-pattern and cognitive workflow layer
