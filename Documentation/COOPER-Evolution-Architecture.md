# COOPER Evolution Architecture Plan

## Progress

80%

## Current Position

COOPER is already the governed operator surface for the ecosystem. The next step is to evolve it from a conversational commander with planning and approval gates into a structured orchestration layer with stronger personality control, durable memory packets, reusable skills, and agent routing across specialized build, research, reporting, and review roles.

This plan is architecture only. It does not introduce runtime changes.

## 1. COOPER Personality

### Objectives

- Provide a TARS-inspired adjustable personality layer.
- Make the personality configurable, testable, and visible in operator output.
- Keep personality limited to tone and presentation.
- Prevent personality changes from weakening governance, category policy, routing controls, or audit logging.

### Personality Controls

- Humor %
- Honesty %
- Formality %
- Directness %
- Autonomy %
- Risk tolerance %

### Rules

- Personality affects response tone only.
- Personality must never override approval gates.
- Personality must never override Category 1 / Category 2 or local-only restrictions.
- Personality must never bypass dispatch governance or audit logging.

### Recommended File Surface

- `Scripts/COOPER_Personality.json`
- `Scripts/Get-COOPERIdentity.ps1`
- `Documentation/COOPER-Identity-and-Personality.md`

## 2. COOPER Operating Model

### Role Definition

COOPER should operate as the mission commander for the ecosystem:

- human-controlled
- approval-first
- one governed action at a time
- dashboard-aware
- chat-driven through Open WebUI
- conversational, not menu-driven

### Behavior

- Observe current system state.
- Recommend next actions.
- Select the best executor or tool.
- Wait for approval before execution.
- Track the active governed action to completion or cancellation.

### Operating Constraints

- One active governed action at a time.
- No autonomous dispatch without approval.
- Dashboard and status output must reflect pending approvals and blocked actions.
- Open WebUI remains the primary conversational surface.

## 3. Hermes-Inspired Features

### Bounded Memory Packet

COOPER should gain a bounded memory packet model for reusable operational knowledge:

- short, scoped context records
- goal and run summaries
- approval-relevant context
- execution outcomes
- lessons learned

### USER.md / SYSTEM.md Equivalent

Future memory packets should have a clear split between:

- user-facing intent and goals
- system-facing rules, policy, and operational guardrails

### Skill Seeds

Fabric patterns can become skill seeds for COOPER:

- research patterns
- reporting patterns
- review patterns
- security triage patterns
- workflow recipes

### COOPER Skill Library

Future reusable skill entries should support:

- skill name
- trigger conditions
- required tools
- allowed category scope
- output format
- safety constraints
- success criteria

### Learning Loop

Recommended loop:

1. execute
2. review
3. remember
4. promote skill

### Subagent Concepts

Future phases may add:

- subagent profiles
- isolated context windows
- restricted tool access
- task-specific memory boundaries

### Future Messaging Gateway

The architecture should allow a future message broker or task gateway to mediate between COOPER and specialized agents without bypassing governance.

### Scheduled Work

COOPER should eventually support scheduled briefings and routine tasks, but only after durable memory and approval workflow maturity improves.

## 4. AI-Powered Worker Model

### Architectural Shift

PowerShell scripts remain the tool harness layer. Agents become the reasoning layer that decides how to use those tools.

### Proposed Agent Roles

- Claude Code: primary build agent
- Codex: secondary implementation and review agent
- Gemini: research agent
- Claude: reporting and review agent
- Local-only restricted agent: mandatory for Category 2 work

### Principles

- Scripts execute tasks.
- Agents choose and justify tools.
- COOPER governs the workflow.
- Tool execution still requires approval when policy demands it.
- Local-only paths remain mandatory for restricted work.

## 5. Agent Routing Architecture

Routing should consider:

- task type
- sensitivity category
- required tools
- approval status
- preferred model or agent
- fallback agent

### Example Routing Matrix

| Task Type | Sensitivity | Preferred Agent | Fallback Agent | Notes |
| --- | --- | --- | --- | --- |
| Research | Category 1 | Gemini | Claude | Use local-only agent if restricted |
| Reporting | Category 1 | Claude | Codex | Prefer strong summarization |
| Review | Category 1 | Claude | Codex | Secondary review pass |
| Build / Code | Category 1 | Claude Code | Codex | Primary implementation path |
| Automation | Category 1 | Claude Code | Codex | Tool-heavy work |
| Restricted local work | Category 2 | Local-only agent | Local PowerShell | No cloud routing |

### Routing Rules

- Approved execution still must pass approval gates.
- Restricted work must remain local even if a cloud model is preferred for the task type.
- Fallback agents should never violate category policy.

## 6. Implementation Roadmap

Recommended order:

### A. COOPER Evolution Architecture doc

- Establish the shared design target.
- Define the future state before code changes.

### B. Personality settings expansion

- Add configurable personality parameters and display rules.

### C. Memory packet foundation

- Create bounded memory packet objects and storage conventions.

### D. Agent profiles / routing doc

- Formalize preferred agents, fallback agents, and category constraints.

### E. Claude Code + Codex routing

- Update routing policy to prefer Claude Code for build and Codex for secondary review.

### F. Fabric-to-Skill library

- Convert successful Fabric patterns into reusable COOPER skills.

### G. AI-powered worker-agent harness

- Let agents reason over tool harnesses without replacing governance.

### H. Subagent profiles

- Introduce isolated profile boundaries for specialized agents.

### I. Messaging gateway

- Add a future message broker or gateway after the orchestration model is stable.

## Risks

- Over-expanding agent autonomy before approvals and routing are fully stable.
- Mixing tone/personality changes with policy enforcement.
- Introducing cloud defaults that violate Category 2 restrictions.
- Turning skill libraries into implicit automation without audit controls.

## Dependencies

- Approval workflow foundation
- Agent loop foundation
- COOPER identity and personality layer
- Dashboard status and command center integrations
- Existing command interpreter and handoff logic
- Category policy and worker registry enforcement

## Suggested Commit Sequence

1. Commit the evolution architecture document.
2. Expand personality settings and tone controls.
3. Add memory packet foundation.
4. Add agent profile and routing policy docs.
5. Update Claude Code and Codex routing policy.
6. Add Fabric-to-Skill library design.
7. Introduce agent harness integration.
8. Add subagent profile architecture.
9. Add messaging gateway architecture last.

## Summary

COOPER’s next phase should preserve the current governed runtime while adding the architectural foundation for personality-aware orchestration, reusable memory, and specialized agent routing. Governance stays first; autonomy comes later.

