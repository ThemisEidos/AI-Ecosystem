# Phase 8 Workspace Knowledge Layer Scope

## Purpose

This document defines the scope, boundaries, security rules, and definition of done for Phase 8.

It is a scope and readiness document, not implementation work.

## Phase 8 Objective

Phase 8 defines the Open WebUI Workspace as the operational AI retrieval layer for approved project knowledge.

Obsidian remains the durable human knowledge vault.

Private Workshop data remains excluded from Open Workspace.

## Current State

- Open Workshop and Private Workshop are already separated.
- Workflow evidence and roadmap state are operational.
- WF-006 Knowledge Collection Import Draft exists.
- Workspace knowledge boundaries need to be defined before import or collection work expands.

## Responsibilities

### Open WebUI Workspace

- AI-facing retrieval context
- approved project documentation
- approved sanitized collections
- operational reference material for workflows

### Obsidian

- durable human notes
- long-form planning
- personal knowledge management
- source-of-truth human vault structure

### Restricted DMZ / Private Workshop

- private local analysis outputs
- sensitive or private artifacts
- no Open Workspace import

## Allowed Workspace Content

Allowed content includes:

- Category 1 public or project governance docs
- sanitized workflow documentation
- approved non-sensitive technical references
- approved collection summaries
- generated notes only if explicitly approved and non-sensitive

## Prohibited Workspace Content

The following must not enter Open WebUI Workspace:

- credentials
- secrets
- tokens
- API keys
- private client material
- restricted or private analysis inputs or outputs
- Restricted DMZ content
- StandardNotes content
- Secure Vault content
- unsanitized personal or private notes
- local model weights
- raw runtime `State/`
- approval records containing sensitive details
- anything requiring Private Workshop

## Workspace Import Rule

Material should enter Open WebUI Workspace through WF-006 or a future governed import path.

Direct manual imports should be documented.

Imports must record:

- source
- category
- approval
- sanitization status

No bulk imports are allowed without review.

## Relationship To WF-006

- WF-006 drafts collection imports.
- WF-006 does not automatically approve material for Workspace.
- Human review remains required before Workspace ingestion.

## Security And Compartmentalization

- Open WebUI Workspace is Open Workshop only.
- Private data never enters Open WebUI Workspace.
- Use the least-exposed tool principle.
- Workspace content should be assumed visible to Open Workshop retrieval.
- Sensitive material must stay in Private Workshop or Restricted DMZ Workspace.

## Initial Phase 8 Build Sequence

1. Create this scope document.
2. Define Workspace collection taxonomy.
3. Create Workspace import checklist.
4. Create first approved low-risk collection.
5. Validate retrieval behavior.
6. Document Phase 8 exit criteria.

## Definition Of Done

Phase 8 is done when:

- Workspace scope is documented.
- Allowed and prohibited content rules are documented.
- Collection taxonomy exists.
- Import checklist exists.
- At least one approved low-risk collection is created or imported.
- Retrieval behavior is validated.
- Security boundaries are verified.
- No Private Workshop content enters Open Workspace.

## Non-Goals

- no new knowledge system
- no replacement for Obsidian
- no frontend or dashboard
- no Claude Design integration
- no Codex loop
- no autonomous ingestion
- no bulk sync from Obsidian
- no database, event bus, or orchestration layer
- no Private Workshop ingestion into Open Workspace

## Risks

- knowledge sprawl
- duplicate sources of truth
- accidental sensitive import
- stale Workspace content
- unsanitized notes entering retrieval
- overloading retrieval with low-quality documents

## Recommended Next Artifact

`Docs/Workspace_Collection_Taxonomy.md`
