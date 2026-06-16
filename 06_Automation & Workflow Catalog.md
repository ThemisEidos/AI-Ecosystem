# Automation & Workflow Catalog

## Purpose

This document catalogs proven workflows that COOPER can route to approved execution paths.

The intent is to keep the first workflow set useful and small.

Storage rules:

- Open Workshop writes to Obsidian or Project Workspace with approval.
- Private Workshop writes only to the Restricted DMZ Workspace.
- COOPER Private never writes directly to Secure Vault or StandardNotes.
- Fabric is the reusable prompt-pattern layer.
- Open WebUI Workspace is the knowledge and reference-asset layer.
- Workspace should not hold registries, approval rules, runtime state, secrets, private data, or personality state.

## WF-001 Research Summary

- Purpose: turn source material into a concise research brief
- Workshop: Open Workshop
- Trigger: user requests a summary of public or sanitized material
- Inputs: notes, links, source excerpts
- Tools Used: COOPER, research tool, writing model, Obsidian
- Execution Method: approved general workflow
- Permission Level: 1
- Approval Requirement: required if external execution or side effects are involved
- Output: structured research summary
- Storage Location: Obsidian
- Security Notes: sanitize before cloud use if needed
- Status: Planned
- Next Step: define the summary template

## WF-002 Codex Task Generator

- Purpose: turn COOPER project discussion, decisions, and requirements into a structured Codex task file and optionally launch Codex CLI with user approval
- Workshop: Open Workshop
- Trigger: project discussion, decisions, or implementation requirements
- Inputs: project context, requirements, target repo, desired outcome
- Tools Used: COOPER, writing model, task template, Codex_Tasks folder, governed workbench
- Execution Method: governed task file generation
- Permission Level: 2 for task file creation; 4 for launcher invocation
- Approval Requirement: required
- Output: Codex task file, optional launcher start
- Storage Location: Project Workspace Codex_Tasks/
- Security Notes: do not include secrets, API keys, credentials, private keys, or Category 2 material
- Status: Operational
- Next Step: keep launcher invocation optional and defer it until explicitly requested
- Suggested File Format: `TASK-###_<short-title>.md`
- Suggested Path: `Codex_Tasks/`

### WF-002 Phases

- Phase 1 - Manual
  - COOPER generates a Codex prompt.
  - User manually copies or pastes it into Codex.
  - No execution.
- Phase 2 - Semi-Automated
  - COOPER writes a task file to `Codex_Tasks/`.
  - User approves launcher.
  - Launcher opens Codex CLI or app context in the target repo.
  - User remains responsible for starting or confirming Codex work.
  - This is the selected near-term target.
- Phase 3 - Integrated / Deferred
  - COOPER directly invokes Codex CLI.
  - Treat as Level 4 execution.
  - Requires explicit approval.
  - Deferred until Phase 2 is stable.

### Future Workspace and Fabric Phases

- Open WebUI Workspace Knowledge Layer
  - Purpose: organize governance documents, reference libraries, and project knowledge collections.
  - Status: future
  - Notes: cloud-connected collections remain Category 1 only unless the Workspace is confirmed local-only and Private Workshop safe.
- Fabric Prompt Pattern Layer
  - Purpose: store reusable prompt patterns for analysis, summarization, report review, threat analysis, and decision support.
  - Status: future
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
- Status: Planned
- Next Step: keep as a fallback only

## WF-004 System Status Check

- Purpose: summarize the health and readiness of the ecosystem
- Workshop: Open Workshop
- Trigger: user asks for status
- Inputs: service health, approvals, workflow state, mode state
- Tools Used: COOPER, status sources, dashboard data
- Execution Method: read-only status aggregation
- Permission Level: 1
- Approval Requirement: none for read-only status
- Output: operational status summary
- Storage Location: Obsidian or dashboard notes
- Security Notes: do not include secrets
- Status: Planned
- Next Step: define status fields

## WF-005 Obsidian Note Creation

- Purpose: create a structured note in the vault
- Workshop: Open Workshop or Private Workshop
- Trigger: new idea, decision, summary, or reusable reference
- Inputs: title, body, tags, target folder
- Tools Used: COOPER, note template, Obsidian
- Execution Method: approved note creation workflow
- Permission Level: 2
- Approval Requirement: required if the note creation writes to a governed location
- Output: new note
- Storage Location: Obsidian
- Security Notes: private notes must stay in the restricted compartment
- Status: Planned
- Next Step: define naming and template conventions

## WF-006 Image Generation

- Purpose: generate an image from a prompt
- Workshop: Open Workshop
- Trigger: user requests image creation
- Inputs: prompt, style, size, usage constraints
- Tools Used: COOPER, image generation tool, execution gateway
- Execution Method: approved external or local image generation workflow
- Permission Level: 3
- Approval Requirement: true
- Output: image file
- Storage Location: Project Workspace or Restricted DMZ Workspace, depending on workshop
- Security Notes: do not send sensitive prompts to cloud image tools
- Status: Planned
- Next Step: define approved image tool entries

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
- Status: Planned
- Next Step: define the approved local analysis pipeline

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
