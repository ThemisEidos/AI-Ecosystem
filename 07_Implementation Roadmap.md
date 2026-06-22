# Implementation Roadmap

## Purpose

This roadmap tracks the staged implementation of the COOPER-centered AI Ecosystem.

The roadmap exists to preserve sequence discipline, prevent scope creep, and identify the current build artifact before new work begins.

The ecosystem should continue to prioritize:

- working workflows
- operational usefulness
- governance compliance
- security boundaries
- maintainability
- incremental implementation

The roadmap should not be used to justify premature agents, new orchestration layers, databases, or tool accumulation.

---

## Current Project State

The following phases are complete:

```text
Phase 0 - Documentation Foundation
Phase 1 - Tool Registry Foundation
Phase 2 - Quartermaster / Tool Router
Phase 3 - Safety Officer / Approval Gate
Phase 4 - First Workbench / Execution Gateway
Phase 5 - Operational Workflows
Phase 6 - Private Workshop Hardening
Phase 7A - Workflow Evidence Standardization
Phase 7A.1 - WF-002 Workflow Package Standard
Phase 7A.2 - Minimal Context Doctrine
```

Current operational model:

```text
Open Workshop   = COOPER
Private Workshop = COOPER - Private
```

Operational workflows:

```text
WF-001 Research Summary
WF-002 Codex Task Generator
WF-004 Operational Status
WF-005 Note Creation
WF-006 Knowledge Collection Import Draft
WF-007 Private Local Analysis
```

Operational workflow chains:

```text
WF-001 -> WF-006
WF-001 -> WF-006 -> WF-002
```

Phase 6 conclusion:

```text
Execution capability is no longer the bottleneck.
Operational visibility is the bottleneck.
```

Phase 7A created the canonical workflow evidence standard so future status reporting can rely on consistent file-based evidence instead of scattered artifacts and mixed state sources.
Phase 7A.1 created the WF-002 workflow package standard so task handoffs can use structured package folders instead of a single markdown file.
Phase 7A.2 created the minimal context doctrine so context files stay short, scoped, and task-relevant.
Phase 7A.3 is creating the folder-based workflow state standard so visible folders can organize early-phase workflow progress without introducing databases or orchestration layers.

---

## Current Focus

### Current Phase

```text
Phase 7A.3 - Folder-Based Workflow State
```

### Current Objective

Adopt a folder-based workflow state standard for early-phase workflow progress and artifact organization.

This is a governance and documentation improvement only. It is not a new orchestration layer, agent system, database, task queue, or execution framework.

### Why This Comes Next

Recent work introduced canonical evidence, WF-002 package folders, and a minimal context doctrine. The next improvement is to use visible workflow-state folders for simple workflows so progress is easier to review without adding heavier infrastructure.

This improves workflow visibility without changing the existing approval model, launcher boundary, or evidence standard.

### Next Build Artifacts

```text
Docs/Folder_Based_Workflow_State_Standard.md
06_Automation & Workflow Catalog.md
02_COOPER System Specification.md
Docs/WF002_Workflow_Package_Standard.md
```

Optional later artifacts after the standard is accepted:

```text
Templates/WF002_Workflow_Package/
Scripts/Test-COOPERWF002WorkflowPackage.ps1
```

### Proposed WF-002 Package Structure

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

### Dependencies

- Phase 7A Workflow Evidence Standard complete
- WF-002 remains Open Workshop only
- `Codex_Tasks/` remains the default Project Workspace location
- user approval remains required for governed file writes and launcher invocation
- Category 2 material remains prohibited from WF-002 packages unless sanitized first

### Definition of Done

Phase 7A.2 is complete when:

- `Docs/Minimal_Context_Doctrine.md` exists
- the doctrine defines short, scoped, task-specific context rules
- roadmap, catalog, and spec reference the doctrine
- WF-002 package guidance is aligned to minimal context
- no giant global context file is created
- no launcher behavior is changed
- no workflow execution code is modified unless separately approved
- no database, agent framework, task queue, or orchestration subsystem is introduced

### Phase 7A.3 - Folder-Based Workflow State

- Status: Current
- Goal: Define a visible folder-based workflow state model for early-phase workflows.
- Build Artifacts:
  - `Docs/Folder_Based_Workflow_State_Standard.md`
- Success Criteria:
  - the standard folder model is defined
  - Open and Private folder-state handling is defined
  - WF-002 optional folder-state compatibility is defined
  - folder state remains separate from canonical workflow evidence
  - folder movement is not treated as approval
  - no database, queue, event bus, or orchestration system is introduced
  - no workflow execution code is changed

### After This, Build Next

```text
Phase 7B - Workflow Evidence Validation
```

Phase 7B should validate canonical evidence schemas before workflow emitters are modified.

---

## Roadmap Sequence

The current near-term sequence is:

```text
Phase 7A   - Define workflow evidence standard                 COMPLETE
Phase 7A.1 - Define WF-002 workflow package standard            COMPLETE
Phase 7A.2 - Define minimal context doctrine                    COMPLETE
Phase 7A.3 - Define folder-based workflow state                 CURRENT
Phase 7B   - Validate workflow evidence schemas                 NEXT TECHNICAL STEP
Phase 7C   - Update workflows to emit canonical evidence         FUTURE
Phase 7D   - Update WF-004 to consume canonical evidence         FUTURE
```

Do not skip directly to Phase 7C or Phase 7D before validation exists.

Do not expand into agents, Hermes integration, multi-intent execution, or new orchestration layers while evidence validation and WF-004 visibility remain unresolved.

---

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

---

### Phase 1 - Tool Registry Foundation

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
  - Private Workshop excludes Level 3 external-service tools
  - registry validation passes

---

### Phase 2 - Quartermaster / Tool Router

- Status: Complete
- Goal: Allow COOPER to identify which approved tool or workflow should be used.
- Build Artifacts:
  - tool routing logic
  - dry-run routing behavior
  - workflow selection behavior
  - workshop validation
  - permission validation
- Success Criteria:
  - approved tool selection works
  - invalid workshop/tool combinations are blocked
  - approval requirement is reported
  - COOPER prefers approved workflows over ad hoc invention

---

### Phase 3 - Safety Officer / Approval Gate

- Status: Complete
- Goal: Enforce permission levels and approval requirements before execution.
- Build Artifacts:
  - approval validation logic
  - permission policy tests
  - approval workflow tests
- Success Criteria:
  - Level 0-1 auto-run behavior represented
  - Level 2-4 approval requirements represented
  - Level 3 blocked in Private Workshop
  - Level 5 blocked by default
  - governed actions require explicit approval

---

### Phase 4 - First Workbench / Execution Gateway

- Status: Complete
- Goal: Route approved execution through a governed workbench boundary.
- Build Artifacts:
  - execution gateway
  - controlled script/workflow execution path
  - status and approval integration
- Success Criteria:
  - approved low-risk execution paths operate successfully
  - output is stored correctly
  - workflow definition of done is applied
  - execution does not bypass approval policy

---

### Phase 5 - Operational Workflows

- Status: Complete
- Goal: Implement practical user-facing workflows.
- Operational Workflows:
  - `WF-001 Research Summary`
  - `WF-002 Codex Task Generator`
  - `WF-004 Operational Status`
  - `WF-005 Note Creation`
  - `WF-006 Knowledge Collection Import Draft`
- Success Criteria:
  - workflows have defined input/output behavior
  - permission model enforced
  - storage boundaries enforced
  - COOPER review step included
  - operational workflow chains are supported

---

### Phase 6 - Private Workshop Hardening

- Status: Complete
- Goal: Make COOPER Private safe enough for restricted DMZ workflows.
- Build Artifacts:
  - private registry hardening
  - Restricted DMZ path validation
  - local-only workflow checks
  - `WF-007 Private Local Analysis`
  - Open WebUI identity persistence validation
- Success Criteria:
  - Private Workshop uses local-only tools
  - no cloud fallback possible
  - outputs remain in Restricted DMZ Workspace
  - Open WebUI exposes exactly one `COOPER` and one `COOPER - Private`
  - hidden implementation models are not exposed as user-facing workshop choices

---

### Phase 7A - Workflow Evidence Standardization

- Status: Complete
- Goal: Define canonical file-based workflow evidence records for workflow completion and approval lifecycle reporting.
- Build Artifact:
  - `Docs/Workflow_Evidence_Standard.md`
- Success Criteria:
  - canonical JSON serialization defined
  - exact Open and Private evidence paths defined
  - filename patterns defined
  - ISO 8601 UTC timestamp format defined
  - workflow status values defined
  - approval status values defined
  - WF-004 precedence and conflict rules defined
  - retention and archival rules are testable
  - Open/Private evidence separation preserved
  - no database, event bus, agent framework, or orchestration layer introduced
  - no workflow execution code changed

---

### Phase 7A.1 - WF-002 Workflow Package Standard

- Status: Current
- Goal: Improve WF-002 Codex handoff quality using a lightweight workflow package folder structure.
- Build Artifacts:
  - `Docs/WF002_Workflow_Package_Standard.md`
  - updated WF-002 section in `06_Automation & Workflow Catalog.md`
  - updated WF-002 section in `02_COOPER System Specification.md`
- Success Criteria:
  - WF-002 package structure is documented
  - required files are defined
  - review checklist expectations are defined
  - `Output/` folder purpose is defined
  - evidence compatibility is defined through artifact path references
  - Category 2 material is prohibited unless sanitized first
  - no execution or launcher behavior changes are made

---

### Phase 7B - Workflow Evidence Validation

- Status: Next
- Goal: Add tests that validate the Phase 7A evidence standard before workflows are modified to emit records.
- Candidate Build Artifacts:
  - `Scripts/Test-COOPERWorkflowEvidenceStandard.ps1`
  - `Scripts/Test-COOPERWorkflowEvidenceSchemas.ps1`
  - `Scripts/Test-COOPERApprovalLifecycleEvidence.ps1`
- Success Criteria:
  - required fields validate
  - JSON record format validates
  - filename patterns validate
  - timestamp format validates
  - Open/Private evidence paths validate
  - approval and workflow record links validate
  - invalid statuses are rejected
  - Private evidence path violations are detected

---

### Phase 7C - Workflow Evidence Emitters

- Status: Future
- Goal: Update operational workflows to emit canonical workflow completion and approval lifecycle evidence records.
- Candidate Build Artifacts:
  - workflow completion record writers
  - approval lifecycle record writers
  - workflow-specific evidence integration for WF-001 through WF-007
- Success Criteria:
  - each operational workflow emits canonical evidence
  - governed workflows link approval records
  - evidence records reference output artifacts
  - workflows fail visibly if evidence cannot be written
  - Open and Private storage boundaries are preserved

---

### Phase 7D - WF-004 Canonical Evidence Consumption

- Status: Future
- Goal: Update WF-004 to consume canonical evidence records as the primary source of truth for operational status.
- Candidate Build Artifacts:
  - WF-004 evidence reader
  - conflict detection logic
  - approval/evidence mismatch reporting
  - transition fallback labeling
- Success Criteria:
  - canonical evidence records are authoritative when present
  - artifact fallback is transition-only
  - conflicting records are surfaced instead of silently resolved
  - approval/completion mismatches are reported
  - workflow chain formatting is preserved
  - WF-004 does not mutate evidence records

---

### Phase 8 - Open WebUI Workspace Knowledge Layer

- Status: Future
- Goal: Add organized knowledge and reference-asset collections in Open WebUI Workspace.
- Build Artifacts:
  - governance collection
  - project documentation collections
  - technical reference collections
- Success Criteria:
  - Workspace stays knowledge-focused
  - Workspace does not hold registries, approval rules, runtime state, secrets, private data, or personality state
  - cloud-connected collections stay Category 1 only

---

### Phase 9 - Fabric Prompt Pattern Layer

- Status: Future
- Goal: Make reusable prompt patterns available as explicit planning inputs.
- Build Artifacts:
  - prompt-pattern library
  - cognitive workflow patterns
  - pattern naming and selection rules
- Success Criteria:
  - Fabric patterns remain reusable and versionable
  - patterns do not contain secrets or runtime state
  - COOPER can consult patterns without weakening governance

---

### Future Backlog - Deferred Capability Expansion

- Status: Deferred
- Candidate Items:
  - Hermes integration review
  - agentic loop experiments
  - multi-intent execution queue
  - broader toolbox expansion
  - richer workflow chaining
- Entry Criteria:
  - Phase 7 evidence validation is complete
  - workflows emit canonical evidence
  - WF-004 consumes canonical evidence reliably
  - proposed capability has a defined workflow need
  - security and maintenance burden are acceptable

Do not promote backlog items into active build work until the current evidence and workflow-package sequence is complete.

---

## Operating Rules

- Always identify the current phase before recommending work.
- Do not skip phases.
- Prefer extending existing workflows over adding tools.
- Do not add infrastructure until a workflow justifies it.
- Keep Private Workshop local-only.
- Keep Category 2 material out of Open Workshop artifacts.
- WF-002 packages are Open Workshop / Category 1 artifacts only unless sanitized.
- Workflow evidence remains file-based.
- WF-004 reads evidence but does not mutate it.
- User approval remains required for governed writes and launcher execution.

---

## Current Next Action

Create the Minimal Context Doctrine.

Recommended Codex task:

```text
Create Docs/Minimal_Context_Doctrine.md and update the WF-002 references in 06_Automation & Workflow Catalog.md, 02_COOPER System Specification.md, and Docs/WF002_Workflow_Package_Standard.md.

Do not modify workflow execution code or launcher behavior.

Define the minimal context doctrine and align the WF-002 package standard to it.
```
