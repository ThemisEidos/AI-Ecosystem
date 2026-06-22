# Minimal Context Doctrine

## Phase 7A.2 Governance Artifact

This document defines the project standard for keeping AI context files minimal, scoped, and task-relevant.

Context exists to reduce ambiguity, not to duplicate governing documents.

This is a governance and documentation standard only.

- It does not create a new loader system.
- It does not create a new orchestration layer.
- It does not create a new agent framework.
- It does not replace governing documents, tool registries, approval policy, security policy, or runtime config.

## Purpose

The project should avoid giant global context files and instead use short, scoped, task-specific context.

Minimal context reduces prompt noise, keeps handoffs reviewable, and makes it easier to see which document is authoritative for which decision.

## Scope

- Applies to Codex task packages.
- Applies to future AI coding handoffs.
- Applies to workflow documentation and project-level context files.
- Does not replace governing documents, tool registries, approval policy, security policy, or runtime config.

## Core Doctrine

```text
Global instructions = short
Project context = scoped
Task context = specific
Workflow context = loaded only when needed
Security rules = authoritative and non-negotiable
```

## Context Layer Rules

### Global Instructions

- Short.
- Stable.
- No duplicated roadmap, workflow catalog, or security policy content.
- Should point to source docs instead of copying them.

### Project Context

- Scoped to the current project.
- Should summarize only current phase, current objective, relevant constraints, and next artifact.
- Should avoid full-history dumps.

### Task Context

- Specific to one task.
- Should include objective, files to inspect, files to change, requirements, constraints, and definition of done.
- Should avoid unrelated project history.

### Workflow Context

- Loaded only when needed.
- WF-specific context should live in relevant workflow package files or docs.
- Do not globally load every workflow rule for every task.

### Security Context

- Authoritative.
- Non-negotiable.
- May be repeated when needed to prevent unsafe handling.
- Must not be weakened for brevity.

## Prohibited Patterns

- giant `AGENTS.md`
- giant `CLAUDE.md`
- giant `COOPER_CONTEXT.md`
- dumping all governance docs into task prompts
- duplicating security rules inconsistently
- mixing Open and Private Workshop context
- including secrets or Category 2 data in Open Workshop task context
- adding broad always/never rules that do not apply to the task
- copying stale roadmap history into task files
- context files that conflict with governing docs

## Preferred Patterns

- cite or reference governing docs instead of duplicating them
- include only relevant sections
- use WF-002 package files for task-specific context
- keep `01_Context.md` focused on current state and dependencies
- keep `04_Constraints.md` focused on applicable constraints
- keep security constraints explicit when the task touches boundaries
- link to source docs where practical

## WF-002 Package Integration

WF-002 package files should reflect minimal context discipline.

- `01_Context.md` must be scoped and minimal.
- `04_Constraints.md` must include only task-relevant constraints plus mandatory security boundaries.
- Package files should not duplicate full governing documents.
- Package files should reference source docs instead of copying them.
- Package context must remain Category 1 unless sanitized.

## Security Rules

- Category 2 material must not enter Open Workshop task context.
- WF-002 packages are Open Workshop / Category 1 artifacts.
- Private Workshop context remains local-only.
- Security policy remains authoritative even when context is minimized.

## Definition of Done

Phase 7A.2 is complete when:

- `Docs/Minimal_Context_Doctrine.md` exists.
- Roadmap references Phase 7A.2.
- Workflow catalog references the doctrine.
- COOPER specification reflects minimal context behavior.
- WF-002 package standard is aligned.
- No global `AGENTS.md`, `CLAUDE.md`, or giant context file is created.
- No execution code is changed.
- No new system or orchestration layer is introduced.

