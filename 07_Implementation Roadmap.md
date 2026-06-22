# Implementation Roadmap

## Purpose

This roadmap tracks the staged implementation of the COOPER-centered AI Ecosystem.

## Current Focus

- Phase 5 workflows are operational and stabilized.
- Phase 7A Workflow Evidence Standardization is now the current documentation and governance focus.
- Phase 6 Private Workshop Hardening remains complete and operational.
- Workspace and Fabric integration remain deferred until evidence standardization is validated and committed.
- Current Phase: Phase 7A - Workflow Evidence Standardization
- Status: In Progress
- Current Objective: Define canonical workflow completion and approval evidence so WF-004 can consume deterministic records.
- Next Build Artifact:
  - `Docs/Workflow_Evidence_Standard.md`
- Why This Comes Next: Phase 1 through Phase 6 foundations are complete enough to support the first operational workflows and private-workshop containment. The remaining work is to standardize the evidence records that WF-004 and later workflow consumers rely on so reporting becomes deterministic instead of inferred from mixed runtime sources.
- Dependencies:
  - governed routing remains registry-driven
  - approval gate remains required before execution
  - review gate remains required before state updates
  - runtime artifacts stay separated from source and docs
  - evidence schemas remain file-based and deterministic
- Definition of Done:
  - canonical evidence standard is documented
  - exact storage paths and filename patterns are defined
  - timestamp format is defined
  - WF-004 precedence and conflict rules are defined
  - roadmap and workflow catalog cross-references are updated
  - WF-001 Research Summary remains operational
  - WF-002 Codex Task Generator remains operational
  - WF-004 Operational Status remains operational
  - WF-005 Note Creation remains operational
  - WF-006 Knowledge Collection Import Draft remains operational
  - WF-007 Private Local Analysis remains operational
  - WF-001 -> WF-006 chain remains operational
  - milestone status is recorded
  - runtime noise is not treated as source of truth

### Phase 7A - Workflow Evidence Standardization

- Status: In Progress
- Goal: define canonical workflow evidence records for WF-004 and future workflow status reporting.
- Build Artifacts:
  - `Docs/Workflow_Evidence_Standard.md`
- Success Criteria:
  - canonical workflow completion records are defined
  - canonical approval lifecycle records are defined
  - exact file paths and filename patterns are defined
  - WF-004 consumption precedence is defined
  - retention and archival rules are testable
  - Open and Private evidence separation remains preserved
  - Phase 7B can validate schemas before workflow emitters are modified

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

### Phase 1 - Tool Registry Inventory

- Status: Complete
- Goal: Create runtime-readable Open and Private Tool Box inventories.
- Build Artifacts:
  - `Config/general_tool_registry.yaml`
  - `Config/private_tool_registry.yaml`
  - `Scripts/Test-COOPERToolRegistry.ps1`
- Success Criteria:
  - registries validate
  - Open and Private tools separated
  - permission levels assigned
  - no execution was implemented at this stage

### Phase 2 - Quartermaster / Tool Router

- Status: Complete
- Goal: Allow COOPER to identify which tool should be used without executing it.
- Build Artifacts:
  - `Scripts/Invoke-COOPERTool.ps1`
  - dry-run routing mode
  - tool lookup by id, drawer, and workshop
- Success Criteria:
  - tool selection works
  - invalid workshop/tool combinations are blocked
  - approval requirement is reported
  - no real execution was implemented at this stage

### Phase 3 - Safety Officer / Approval Gate

- Status: Complete
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

- Status: Complete
- Goal: Add one harmless execution pathway.
- Build Artifacts:
  - one safe local workbench
  - dry-run first, then real execution
- Success Criteria:
  - one low-risk tool executes successfully
  - output is stored correctly
  - workflow definition of done is applied

### Phase 5 - First Operational Workflows

- Status: Operational
- Goal: Keep the first practical governed workflows stable and documented.
- Operational:
  - WF-001 Research Summary
  - WF-002 Codex Task Generator
  - WF-004 Operational Status
  - WF-005 Note Creation
  - WF-006 Knowledge Collection Import Draft
  - First workflow chain: WF-001 → WF-006
  - Confirmed chained path: WF-001 → WF-006 → WF-002
- Success Criteria:
  - each workflow has defined input/output
  - permission model enforced
  - storage boundaries enforced
  - COOPER review step included
  - workflow outputs are recorded without conflating runtime state with source documentation

### Phase 6 - Private Workshop Hardening

- Status: Complete
- Goal: Make COOPER Private safe enough for restricted DMZ workflows.
- Build Artifacts:
  - WF-007 Private Local Analysis
  - private registry hardening
  - Restricted DMZ path validation
  - local-only workflow checks
  - approval lifecycle transition validation
- Success Criteria:
  - Private Workshop uses local-only tools
  - no cloud fallback possible
  - outputs remain in Restricted DMZ Workspace
  - Open Workshop and Private Workshop routing remain separated
  - private-tool routing originates from the private registry only
  - WF-007 reports completion status through WF-004

### Phase 7 - PDA Evolution

- Status: Future
- Goal: Expand toward richer AI-assisted project execution.
- Build Artifacts:
  - agentic loop experiments
  - workflow chaining
  - broader toolbox expansion
  - backlog: implement governed multi-intent execution queue
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
