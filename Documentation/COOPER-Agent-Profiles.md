# COOPER Agent Profiles

COOPER uses specialized agent profiles to decide who should do the work, which tools are allowed, which models are preferred, and what governance applies.

## Design Goals

- Preserve human-controlled governance.
- Separate reasoning roles from tool execution.
- Keep Category 2 and restricted-local work local.
- Allow model preference without turning LiteLLM into governance.
- Keep PowerShell as a tool harness, not a reasoning layer.

## Shared Profile Fields

Each agent profile should define:

- Mission
- Responsibilities
- Approved tools
- Preferred models
- Fallback models
- Category restrictions
- Approval requirements
- Inputs
- Outputs
- Success criteria

## Required Agent Profiles

### Research Agent

- Mission: gather and synthesize information.
- Responsibilities: web research, fact collection, evidence gathering, source comparison.
- Approved tools: Browser, PowerShell harnesses, LiteLLM, MCP search tools, local retrieval helpers.
- Preferred models: Gemini.
- Fallback models: Claude.
- Category restrictions: Category 2 must remain local-only; cloud research is Category 1 only.
- Approval requirements: approval required when the task is governed or modifies state.
- Inputs: goal, topic, constraints, sources, output format.
- Outputs: research summary, citations, recommended next actions.
- Success criteria: accurate sources, clear synthesis, policy-compliant output.

### Reporting Agent

- Mission: turn gathered information into structured reports.
- Responsibilities: summarize findings, write reports, format deliverables, produce operator-friendly outputs.
- Approved tools: PowerShell harnesses, document generation helpers, LiteLLM, Browser when needed.
- Preferred models: Claude.
- Fallback models: Gemini.
- Category restrictions: Category 2 stays local-only.
- Approval requirements: approval required for governed outputs or repository changes.
- Inputs: source materials, outline, audience, style rules.
- Outputs: reports, summaries, executive briefings, deliverable drafts.
- Success criteria: concise, accurate, structured reporting with correct destinations.

### Review Agent

- Mission: evaluate work for correctness, compliance, and quality.
- Responsibilities: code review, report review, governance review, consistency checks.
- Approved tools: PowerShell harnesses, diff readers, LiteLLM, local inspection tools.
- Preferred models: Claude.
- Secondary models: Codex.
- Category restrictions: Category 2 and restricted-local work remain local-only.
- Approval requirements: approval required for follow-up actions, not for review itself.
- Inputs: artifact, patch, plan, or report under review.
- Outputs: review notes, findings, risks, recommendations.
- Success criteria: useful critique, low false positives, governance-aware comments.

### Build Agent

- Mission: implement changes, create patches, and perform build-oriented tasks.
- Responsibilities: code construction, repo modifications, refactors, integration work.
- Approved tools: PowerShell, Python, Browser for local verification, build scripts, future CLI integration.
- Preferred models: Claude Code.
- Secondary models: Codex.
- Category restrictions: Category 2 restricted local work must remain local-only.
- Approval requirements: approval required before execution.
- Inputs: goal plan, task plan, patch scope, constraints.
- Outputs: code changes, build artifacts, implementation summaries.
- Success criteria: correct implementation, test passing, policy compliance.

### Automation Agent

- Mission: perform deterministic workflow automation.
- Responsibilities: scripts, orchestration, routine task execution, environment management.
- Approved tools: PowerShell, Python, n8n, local automation utilities.
- Preferred models: Claude Code.
- Secondary models: Codex.
- Category restrictions: Category 2 stays local-only.
- Approval requirements: approval required for state-changing automation.
- Inputs: workflow request, triggers, safety rules, expected output.
- Outputs: workflow changes, task artifacts, automation summaries.
- Success criteria: deterministic behavior, clear audit trail, safe execution.

### Restricted Agent

- Mission: handle sensitive or restricted workflows without cloud exposure.
- Responsibilities: local-only analysis, local report generation, restricted task execution.
- Approved tools: local PowerShell, local Python, local models, local filesystem utilities.
- Preferred models: local models only.
- Fallback models: none for cloud paths.
- Category restrictions: Category 2 and restricted-local only.
- Approval requirements: approval required when governed.
- Inputs: local-only data, sanitized local artifacts, restricted context.
- Outputs: local reports, local summaries, local task artifacts.
- Success criteria: no cloud routing, no policy violations, full auditability.

## Model Strategy Summary

- Research: Gemini preferred, Claude fallback
- Reporting: Claude preferred, Gemini fallback
- Review: Claude preferred, Codex secondary
- Build: Claude Code preferred, Codex secondary
- Automation: Claude Code preferred, Codex secondary
- Restricted: local models only
- ChatGPT: optional external advisor, not core runtime

## Governance Boundary

Model preference is not governance.

- Approval workflow remains authoritative.
- Category 2 restrictions remain non-negotiable.
- Local-only restrictions remain mandatory.
- Audit logging remains required.
- Agent selection does not bypass approval state.

## Output Contract

Every profile should produce outputs that are:

- governed
- auditable
- tool-aware
- category-aware
- human-readable

