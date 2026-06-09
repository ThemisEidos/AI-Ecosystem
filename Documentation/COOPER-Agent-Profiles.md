# COOPER Agent Profiles

COOPER uses specialized agent profiles to decide which capability should handle the work, which tools are allowed, which providers may be used, and what governance applies.

## Design Goals

- Preserve human-controlled governance.
- Separate capability selection from tool execution and provider selection.
- Keep Category 2 and restricted-local work local.
- Allow provider preference without turning LiteLLM into governance.
- Keep PowerShell as a tool harness, not a reasoning layer.

## Shared Profile Fields

Each agent profile should define:

- Mission
- Capability requirements
- Responsibilities
- Approved tools
- Preferred providers / models
- Fallback providers / models
- Category restrictions
- Approval requirements
- Inputs
- Outputs
- Success criteria

## Capability Registry Concept

The capability registry is the first-level routing catalog. Agents are selected after COOPER matches the task to one or more capabilities.

Suggested capabilities:

- research
- source discovery
- large-context analysis
- report writing
- report review
- code implementation
- code review
- repo modification
- automation design
- n8n workflow design
- local restricted analysis
- file processing
- dashboard/status generation
- memory summarization
- skill promotion review

The registry should answer:

- what capability is needed
- which agents can satisfy it
- which tools are permitted
- which providers/models are preferred
- what category boundaries apply

## Required Agent Profiles

### Research Agent

- Mission: gather and synthesize information.
- Capability requirements: research, source discovery, large-context analysis.
- Responsibilities: web research, fact collection, evidence gathering, source comparison.
- Approved tools: Browser, PowerShell harnesses, LiteLLM, MCP search tools, local retrieval helpers.
- Preferred providers / models: Gemini first, then Claude if needed.
- Fallback providers / models: Claude, then local-only options when restricted.
- Category restrictions: Category 2 must remain local-only; cloud research is Category 1 only.
- Approval requirements: approval required when the task is governed or modifies state.
- Inputs: goal, topic, constraints, sources, output format.
- Outputs: research summary, citations, recommended next actions.
- Success criteria: accurate sources, clear synthesis, policy-compliant output.

### Reporting Agent

- Mission: turn gathered information into structured reports.
- Capability requirements: report writing, file processing, dashboard/status generation.
- Responsibilities: summarize findings, write reports, format deliverables, produce operator-friendly outputs.
- Approved tools: PowerShell harnesses, document generation helpers, LiteLLM, Browser when needed.
- Preferred providers / models: Claude first.
- Fallback providers / models: Gemini.
- Category restrictions: Category 2 stays local-only.
- Approval requirements: approval required for governed outputs or repository changes.
- Inputs: source materials, outline, audience, style rules.
- Outputs: reports, summaries, executive briefings, deliverable drafts.
- Success criteria: concise, accurate, structured reporting with correct destinations.

### Review Agent

- Mission: evaluate work for correctness, compliance, and quality.
- Capability requirements: report review, code review, skill promotion review.
- Responsibilities: code review, report review, governance review, consistency checks.
- Approved tools: PowerShell harnesses, diff readers, LiteLLM, local inspection tools.
- Preferred providers / models: Claude first.
- Secondary providers / models: Codex.
- Category restrictions: Category 2 and restricted-local work remain local-only.
- Approval requirements: approval required for follow-up actions, not for review itself.
- Inputs: artifact, patch, plan, or report under review.
- Outputs: review notes, findings, risks, recommendations.
- Success criteria: useful critique, low false positives, governance-aware comments.

### Build Agent

- Mission: implement changes, create patches, and perform build-oriented tasks.
- Capability requirements: code implementation, repo modification, automation design.
- Responsibilities: code construction, repo modifications, refactors, integration work.
- Approved tools: PowerShell, Python, Browser for local verification, build scripts, future CLI integration.
- Preferred providers / models: Claude Code first.
- Secondary providers / models: Codex.
- Category restrictions: Category 2 restricted local work must remain local-only.
- Approval requirements: approval required before execution.
- Inputs: goal plan, task plan, patch scope, constraints.
- Outputs: code changes, build artifacts, implementation summaries.
- Success criteria: correct implementation, test passing, policy compliance.

### Automation Agent

- Mission: perform deterministic workflow automation.
- Capability requirements: automation design, n8n workflow design, file processing.
- Responsibilities: scripts, orchestration, routine task execution, environment management.
- Approved tools: PowerShell, Python, n8n, local automation utilities.
- Preferred providers / models: Claude Code first.
- Secondary providers / models: Codex.
- Category restrictions: Category 2 stays local-only.
- Approval requirements: approval required for state-changing automation.
- Inputs: workflow request, triggers, safety rules, expected output.
- Outputs: workflow changes, task artifacts, automation summaries.
- Success criteria: deterministic behavior, clear audit trail, safe execution.

### Restricted Agent

- Mission: handle sensitive or restricted workflows without cloud exposure.
- Capability requirements: local restricted analysis, memory summarization, file processing.
- Responsibilities: local-only analysis, local report generation, restricted task execution.
- Approved tools: local PowerShell, local Python, local models, local filesystem utilities.
- Preferred providers / models: local models only.
- Fallback providers / models: none for cloud paths.
- Category restrictions: Category 2 and restricted-local only.
- Approval requirements: approval required when governed.
- Inputs: local-only data, sanitized local artifacts, restricted context.
- Outputs: local reports, local summaries, local task artifacts.
- Success criteria: no cloud routing, no policy violations, full auditability.

## Provider Strategy Summary

Capability comes first. Provider choice comes after the capability match, sensitivity check, and tool availability check.

- Research capability: Gemini preferred, Claude fallback
- Reporting capability: Claude preferred, Gemini fallback
- Review capability: Claude preferred, Codex secondary
- Build capability: Claude Code preferred, Codex secondary
- Automation capability: Claude Code preferred, Codex secondary
- Restricted capability: local models only
- ChatGPT: optional external advisor, not core runtime

## Governance Boundary

Model preference is not governance.

- Approval workflow remains authoritative.
- Category 2 restrictions remain non-negotiable.
- Local-only restrictions remain mandatory.
- Audit logging remains required.
- Agent selection does not bypass approval state.
- Capability selection does not bypass approval state.

## Output Contract

Every profile should produce outputs that are:

- governed
- auditable
- tool-aware
- category-aware
- human-readable
