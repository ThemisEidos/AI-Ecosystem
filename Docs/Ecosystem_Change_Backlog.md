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

## Architectural Insight

Stop thinking in prompts. Start thinking in reusable operational capabilities.

## Proposed Future Layer

```text
User Goal -> Router -> Domain -> Task -> Skill -> Workflow -> Tool
```

## Initial Entries

### CHG-001 Skill Registry / Skill Library

- Status: Evaluating
- Category: Workflow / Architecture
- Added: 2026-06-24
- Scope: Build reusable operational skills instead of relying on large one-off prompts.
- ROI: 10/10
- Summary: Build reusable operational skills instead of relying on large one-off prompts.
- Ecosystem Fit: Strong fit with WF-002 packages, workflow standards, routing, and governance.
- Risks / Cautions: Must remain documentation-first and should not become a hidden execution layer or prompt dump.
- Recommendation: Adopt as a Phase 7A/7B candidate.
- Constraints: No workflow execution code, approval logic, or autonomous loops should be introduced by backlog tracking alone.
- Review Notes: Candidate aligns with the existing packaging and governance direction already documented for reusable workflow assets.
- Related Docs: [Docs/WF002_Workflow_Package_Standard.md](WF002_Workflow_Package_Standard.md), [Docs/Workflow_Linting_Standard.md](Workflow_Linting_Standard.md), [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md)

### CHG-002 Domain -> Task -> Skill Mapping

- Status: Evaluating
- Category: Workflow Architecture
- Added: 2026-06-24
- Scope: Introduce a hierarchy where user goals route into domains, tasks, reusable skills, workflows, and tools.
- ROI: 10/10
- Summary: Introduce a hierarchy where user goals route into domains, tasks, reusable skills, workflows, and tools.
- Ecosystem Fit: Strong fit with router, tool registry, WF-002, WF-001, WF-006.
- Risks / Cautions: Requires clear naming and routing boundaries so the hierarchy does not become an opaque agent abstraction.
- Recommendation: Adopt.
- Constraints: Do not replace existing approval, routing, or workflow definitions with an implicit agent framework.
- Review Notes: Strong organizing model for future routing, but it should remain subordinate to governed workflows and reviewable documentation.
- Related Docs: [07_Implementation_Roadmap.md](../07_Implementation%20Roadmap.md), [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md)

### CHG-003 Persistent Agent Memory

- Status: Evaluating
- Category: Memory / Operational State
- Added: 2026-06-24
- Scope: Track reusable operational lessons, known failures, preferred workflows, and prior decisions.
- ROI: 10/10
- Summary: Track reusable operational lessons, known failures, preferred workflows, and prior decisions.
- Ecosystem Fit: Partially implemented through workflow state and evidence standards, but needs an explicit memory layer if adopted.
- Risks / Cautions: High privacy and drift risk if memory is not compartmentalized and reviewable.
- Recommendation: Evaluate carefully with privacy boundaries.
- Constraints: Do not use backlog tracking to introduce silent state persistence, hidden memory stores, or cross-workshop leakage.
- Review Notes: The project already has canonical evidence and status readers; any persistent memory layer must not conflict with them.
- Related Docs: [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md), [Docs/Minimal_Context_Doctrine.md](Minimal_Context_Doctrine.md), [Docs/Folder_Based_Workflow_State_Standard.md](Folder_Based_Workflow_State_Standard.md)

### CHG-004 Knowledge Graph

- Status: Evaluating
- Category: Knowledge Management
- Added: 2026-06-24
- Scope: Model semantic relationships among tools, sources, workflows, people, projects, decisions, and documents.
- ROI: 9/10
- Summary: Model semantic relationships among tools, sources, workflows, people, projects, decisions, and documents.
- Ecosystem Fit: Strong future fit for research corpus growth and workflow intelligence.
- Risks / Cautions: Graph complexity can outgrow governance discipline and blur source-of-truth boundaries.
- Recommendation: Research before implementation.
- Constraints: Do not introduce graph infrastructure or automated inference through backlog tracking alone.
- Review Notes: This may be useful later for retrieval and reasoning, but current docs already favor lightweight, reviewable structure.
- Related Docs: [Docs/Workspace_Collection_Taxonomy.md](Workspace_Collection_Taxonomy.md), [Docs/OpenWebUI_Workspace_Design.md](OpenWebUI_Workspace_Design.md)

### CHG-005 Expanded MCP Registry

- Status: Evaluating
- Category: Tooling / Integration
- Added: 2026-06-24
- Scope: Evaluate high-value MCP servers such as Playwright, Firecrawl, Perplexity, and other controlled integrations.
- ROI: 9/10
- Summary: Evaluate high-value MCP servers such as Playwright, Firecrawl, Perplexity, and other controlled integrations.
- Ecosystem Fit: Strong fit with the tool registry and Open Workshop.
- Risks / Cautions: Each integration must be individually reviewed for security, reliability, and permission scope.
- Recommendation: Adopt selectively.
- Constraints: No broad tool sprawl, no approval bypass, and no private-workshop leakage.
- Review Notes: Useful only if each server is mapped to an explicit workflow need and constrained to the correct workshop.
- Related Docs: [03_AI Tool Stack & Roles.md](../03_AI%20Tool%20Stack%20%26%20Roles.md), [01_AI Ecosystem Architecture.md](../01_AI%20Ecosystem%20Architecture.md)

### CHG-006 Firecrawl Integration

- Status: Evaluating
- Category: Research Ingestion
- Added: 2026-06-24
- Scope: Use Firecrawl-style website ingestion for WF-001 research and WF-006 knowledge collection import drafting.
- ROI: 10/10
- Summary: Use Firecrawl-style website ingestion for WF-001 research and WF-006 knowledge collection import drafting.
- Ecosystem Fit: Strong.
- Risks / Cautions: Must keep source capture bounded so the import path does not become a general-purpose scraping pipeline.
- Recommendation: High-priority candidate.
- Constraints: Only approved research sources should be carried forward; no blind crawling into sensitive or private contexts.
- Review Notes: This is a high-value ingestion pattern if it remains reviewable and source-limited.
- Related Docs: [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md), [Docs/Workspace_Governance_Core_Manual_Import_Runbook.md](Workspace_Governance_Core_Manual_Import_Runbook.md)

### CHG-007 Playwright MCP Integration

- Status: Evaluating
- Category: Browser Automation / Testing
- Added: 2026-06-24
- Scope: Add browser automation for testing, scraping, UI validation, and controlled web workflows.
- ROI: 9/10
- Summary: Add browser automation for testing, scraping, UI validation, and controlled web workflows.
- Ecosystem Fit: Strong with the approval layer and execution gateway.
- Risks / Cautions: Browser automation can easily overreach if not sandboxed and approval-gated.
- Recommendation: Adopt with safeguards.
- Constraints: No uncontrolled browsing, no credential exposure, and no private-data workflows through public browser sessions.
- Review Notes: Best treated as a controlled execution aid for explicit workflows rather than a universal automation surface.
- Related Docs: [01_AI Ecosystem Architecture.md](../01_AI%20Ecosystem%20Architecture.md), [04_Security & Compartmentalization Policy.md](../04_Security%20%26%20Compartmentalization%20Policy.md)

### CHG-008 Perplexity MCP Integration

- Status: Evaluating
- Category: Research
- Added: 2026-06-24
- Scope: Add Perplexity as a research provider option, not as a replacement for existing research workflows.
- ROI: 8/10
- Summary: Add Perplexity as a research provider option, not as a replacement for existing research workflows.
- Ecosystem Fit: Moderate to strong.
- Risks / Cautions: External research providers can introduce citation drift, prompt leakage, and inconsistent policy boundaries.
- Recommendation: Optional/selective.
- Constraints: Keep it optional, approved, and subordinate to existing research and review workflows.
- Review Notes: Useful only if it adds distinct value over current research sources and remains compatible with governance rules.
- Related Docs: [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md), [03_AI Tool Stack & Roles.md](../03_AI%20Tool%20Stack%20%26%20Roles.md)

### CHG-009 Workflow Observability / Metrics

- Status: Evaluating
- Category: Operations
- Added: 2026-06-24
- Scope: Track workflow duration, failures, retries, approval outcomes, stale items, and quality review signals.
- ROI: 9/10
- Summary: Track workflow duration, failures, retries, approval outcomes, stale items, and quality review signals.
- Ecosystem Fit: Strong fit with WF-004.
- Risks / Cautions: Metrics can become misleading if they are not tied to canonical evidence and well-defined review criteria.
- Recommendation: Adopt.
- Constraints: Do not add opaque telemetry or autonomous operational control through this backlog item.
- Review Notes: This belongs next to WF-004-style status reporting and should remain evidence-based.
- Related Docs: [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md), [06_Automation & Workflow Catalog.md](../06_Automation%20%26%20Workflow%20Catalog.md)

### CHG-010 Red Team / Self-Review Workflow

- Status: Evaluating
- Category: Governance / Quality Control
- Added: 2026-06-24
- Scope: Add structured adversarial review for research summaries, Codex task prompts, architecture proposals, and workflow outputs.
- ROI: 9/10
- Summary: Add structured adversarial review for research summaries, Codex task prompts, architecture proposals, and workflow outputs.
- Ecosystem Fit: Strong with the governance and approval layer.
- Risks / Cautions: Needs strict separation from execution so review does not become hidden auto-remediation.
- Recommendation: Adopt soon.
- Constraints: No autonomous repair loop, no hidden approval bypass, and no mutation of source artifacts as part of review.
- Review Notes: A lightweight adversarial review process would strengthen report quality and reduce unchallenged assumptions.
- Related Docs: [Docs/Workflow_Evidence_Standard.md](Workflow_Evidence_Standard.md), [Docs/Workflow_Linting_Standard.md](Workflow_Linting_Standard.md)

### CHG-011 Parallel Agents

- Status: Deferred
- Category: Agent Architecture
- Added: 2026-06-24
- Scope: Future pattern where separate agents perform research, coding, testing, documentation, and review in parallel.
- ROI: 9/10
- Summary: Future pattern where separate agents perform research, coding, testing, documentation, and review in parallel.
- Ecosystem Fit: Long-term fit.
- Risks / Cautions: High coordination and governance complexity; can multiply failure modes if introduced too early.
- Recommendation: Defer until the current workflow layer is more mature.
- Constraints: Do not introduce agent swarms or parallel execution orchestration through backlog tracking.
- Review Notes: This is plausible future architecture, but it depends on stronger observability and governance than the current layer provides.
- Related Docs: [07_Implementation_Roadmap.md](../07_Implementation%20Roadmap.md), [02_COOPER System Specification.md](../02_COOPER%20System%20Specification.md)

### CHG-012 Autonomous Goal Execution Loop

- Status: Deferred
- Category: Agentic Automation
- Added: 2026-06-24
- Scope: Agent plans, acts, evaluates, and repeats toward a goal.
- ROI: 8/10
- Summary: Agent plans, acts, evaluates, and repeats toward a goal.
- Ecosystem Fit: High potential but requires strong safeguards.
- Risks / Cautions: Autonomous loops create significant approval, safety, and drift risks without mature controls.
- Recommendation: Long-term candidate only.
- Constraints: No autonomous execution, no automatic phase advancement, and no self-directed task loops should be introduced by backlog tracking.
- Review Notes: The roadmap currently favors reviewable workflow discipline over autonomous repetition.
- Related Docs: [07_Implementation_Roadmap.md](../07_Implementation%20Roadmap.md), [Docs/Phase_7E_Exit_Review.md](Phase_7E_Exit_Review.md)

### CHG-013 Claude Code / Claude Skill Repositories

- Status: Researching
- Category: External Reference / Prompt Libraries
- Added: 2026-06-24
- Scope: Mine public Claude Code and Claude skill repositories for patterns, not wholesale adoption.
- ROI: 7/10
- Summary: Mine public Claude Code and Claude skill repositories for patterns, not wholesale adoption.
- Ecosystem Fit: Useful reference material.
- Risks / Cautions: Public patterns may not fit the project's governance, storage, or workshop boundaries.
- Recommendation: Evaluate and extract reusable practices.
- Constraints: No direct import of external repository structure, secrets, or unreviewed prompt artifacts.
- Review Notes: Treat as pattern-mining only; do not import without translation into the project's standards.
- Related Docs: [Docs/Minimal_Context_Doctrine.md](Minimal_Context_Doctrine.md), [Docs/Workflow_Linting_Standard.md](Workflow_Linting_Standard.md)

### CHG-014 Obsidian-style Knowledge Base Patterns

- Status: Evaluating
- Category: Knowledge Management
- Added: 2026-06-24
- Scope: Borrow useful folder/wiki/relationship patterns without replacing Proton Drive as the primary storage location.
- ROI: 6/10
- Summary: Borrow useful folder/wiki/relationship patterns without replacing Proton Drive as the primary storage location.
- Ecosystem Fit: Partial.
- Risks / Cautions: May create redundant structure if adopted without clear separation from the existing vault and workspace model.
- Recommendation: Borrow concepts only.
- Constraints: Do not re-home primary storage or turn the backlog into a replacement vault design.
- Review Notes: This is primarily a structural inspiration item, not a near-term implementation target.
- Related Docs: [Docs/Workspace_Collection_Taxonomy.md](Workspace_Collection_Taxonomy.md), [08_Obsidian Vault Structure.md](../08_Obsidian%20Vault%20Structure.md)

### CHG-015 Marketing Prompt Personas

- Status: Evaluating
- Category: Prompting
- Added: 2026-06-24
- Scope: Prompt persona names like "Caveman," "Million Dollar," or "Ghost" are mostly packaging around reusable prompt templates.
- ROI: 5/10
- Summary: Prompt persona names like "Caveman," "Million Dollar," or "Ghost" are mostly packaging around reusable prompt templates.
- Ecosystem Fit: Low.
- Risks / Cautions: Persona marketing can distract from durable workflow design and encourage prompt theater over reusable capability.
- Recommendation: Do not build architecture around these.
- Constraints: Do not normalize persona branding as an architectural primitive.
- Review Notes: These may be useful as surface-level prompt wrappers, but they do not justify structural changes to the ecosystem.
- Related Docs: [Docs/Minimal_Context_Doctrine.md](Minimal_Context_Doctrine.md), [03_AI Tool Stack & Roles.md](../03_AI%20Tool%20Stack%20%26%20Roles.md)

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
