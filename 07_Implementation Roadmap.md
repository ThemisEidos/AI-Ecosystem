# Implementation Roadmap

## Purpose

This roadmap tracks the staged implementation of the COOPER-centered AI Ecosystem.

## Current Focus

- Current priority remains status governance cleanup and Git alignment.
- Workspace and Fabric integration is deferred until the current governed-status work is committed and stable.
- Current Phase: Phase 1 - Tool Registry Foundation
- Current Objective: Create the first runtime-readable version of the COOPER Tool Box inventory for both workshops.
- Next Build Artifact:
  - `Config/general_tool_registry.yaml`
  - `Config/private_tool_registry.yaml`
  - `Scripts/Test-COOPERToolRegistry.ps1`
- Why This Comes Next: COOPER cannot select tools until it has a validated list of approved tools, drawers, workshops, permission levels, and executor types. The registry must exist before the Quartermaster, Safety Officer, or Workbench can operate.
- Dependencies:
  - numbered guidance documents complete
  - Two Workshop model defined
  - permission levels defined
  - storage boundaries defined
  - workflow catalog defined
- Definition of Done:
  - `general_tool_registry.yaml` exists
  - `private_tool_registry.yaml` exists
  - each tool entry includes `id`, `name`, `drawer`, `workshop`, `description`, `permission_level`, `approval_required`, `executor_type`, `enabled`, `inputs`, `outputs`, and `notes`
  - private registry contains only local/private-safe tools
  - general registry contains only Open Workshop tools
  - validation script loads both registries
  - validation script checks required fields
  - validation script checks invalid workshop/tool combinations
  - validation script confirms Private Workshop has no Level 3 external-service tools
  - validation script exits cleanly with pass/fail output
  - no real tool execution is implemented yet
- After This, Build Next:
  - Phase 2 - Quartermaster / Tool Router
  - `Scripts/Invoke-COOPERTool.ps1`
  - dry-run tool selection
  - workshop validation
  - permission validation
  - no real execution yet

## Phase Map

### Phase 0 - Documentation Foundation

- Status: Complete
- Goal: Establish the governing documentation and source of truth.
- Build Artifacts:
  - `00_Project Charter.md`
  - `01_AI Ecosystem Architecture.md`
  - `02_COOPER System Specification.md`
  - `03_AI Tool Stack & Roles.md`
  - `04_Security & Compartmentalization Policy.md`
  - `05_Reporting Workflow Standards.md`
  - `06_Automation & Workflow Catalog.md`
  - `07_Implementation Roadmap.md`
  - `08_Obsidian Vault Structure.md`
- Success Criteria:
  - legacy docs archived
  - numbered docs are source of truth
  - Two Workshop model documented
  - permission model documented
  - storage model documented
  - workflow definition of done documented

### Phase 1 - Tool Registry Foundation

- Status: Current
- Goal: Create runtime-readable Open and Private Tool Box inventories.
- Build Artifacts:
  - `Config/general_tool_registry.yaml`
  - `Config/private_tool_registry.yaml`
  - `Scripts/Test-COOPERToolRegistry.ps1`
- Success Criteria:
  - registries validate
  - Open and Private tools separated
  - permission levels assigned
  - no execution implemented

### Phase 2 - Quartermaster / Tool Router

- Status: Next
- Goal: Allow COOPER to identify which tool should be used without executing it.
- Build Artifacts:
  - `Scripts/Invoke-COOPERTool.ps1`
  - dry-run routing mode
  - tool lookup by id, drawer, and workshop
- Success Criteria:
  - tool selection works
  - invalid workshop/tool combinations are blocked
  - approval requirement is reported
  - no real execution implemented

### Phase 3 - Safety Officer / Approval Gate

- Status: Planned
- Goal: Enforce permission levels and approval requirements before execution.
- Build Artifacts:
  - approval validation logic
  - permission policy tests
- Success Criteria:
  - Level 0-1 auto-run behavior represented
  - Level 2-4 approval requirements represented
  - Level 3 blocked in Private Workshop
  - Level 5 blocked by default

### Phase 4 - First Workbench / Execution Gateway

- Status: Planned
- Goal: Add one harmless execution pathway.
- Build Artifacts:
  - one safe local workbench
  - dry-run first, then real execution
- Success Criteria:
  - one low-risk tool executes successfully
  - output is stored correctly
  - workflow definition of done is applied

### Phase 5 - First Operational Workflows

- Status: Planned
- Goal: Implement the first practical workflows.
- Build Artifacts:
  - WF-001 COOPER Status Check
  - WF-002 Codex Task Generator, semi-automated
  - WF-003 Codex Prompt Helper
- Success Criteria:
  - each workflow has defined input/output
  - permission model enforced
  - storage boundaries enforced
  - COOPER review step included

### Phase 6 - Private Workshop Hardening

- Status: Planned
- Goal: Make COOPER Private safe enough for restricted DMZ workflows.
- Build Artifacts:
  - private registry hardening
  - Restricted DMZ path validation
  - local-only workflow checks
- Success Criteria:
  - Private Workshop uses local-only tools
  - no cloud fallback possible
  - outputs remain in Restricted DMZ Workspace

### Phase 7 - PDA Evolution

- Status: Future
- Goal: Expand toward richer AI-assisted project execution.
- Build Artifacts:
  - agentic loop experiments
  - workflow chaining
  - broader toolbox expansion
- Success Criteria:
  - only after core workflows are stable
  - no premature agent complexity

### Phase 8 - Open WebUI Workspace Knowledge Layer

- Status: Future
- Goal: add an organized knowledge and reference-asset layer in Open WebUI Workspace.
- Build Artifacts:
  - governance collection
  - project documentation collections
  - technical reference collections
- Success Criteria:
  - Workspace stays knowledge-focused
  - no registries, approval rules, runtime state, secrets, or private data are stored there
  - cloud-connected collections stay Category 1 only

### Phase 9 - Fabric Prompt Pattern Layer

- Status: Future
- Goal: make reusable prompt patterns available as explicit planning inputs.
- Build Artifacts:
  - prompt-pattern library
  - cognitive workflow patterns
  - pattern naming and selection rules
- Success Criteria:
  - Fabric patterns remain reusable and versionable
  - patterns do not contain secrets or runtime state
  - COOPER can consult patterns without weakening governance
