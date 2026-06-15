# AI Ecosystem Architecture

## Purpose

This document defines the executive architecture for the AI Ecosystem.

The ecosystem is organized around COOPER as the controlled operations foreman, not as the worker. COOPER receives a user request and routes work through the workshop the user selected.

The architecture is intended to be:

- operational rather than abstract
- modular rather than monolithic
- secure by default
- local-first for private work
- cloud-enabled for general work
- easy to extend without overengineering

## Design Philosophy

The system should favor working workflows over speculative infrastructure.

Core principles:

- build fewer systems
- build more working workflows
- route by task role, not by brand loyalty
- keep private data local
- make approved capability visible and reusable
- require a clear workflow before adding a new tool

## Workshop Model

```text
User
 ↓
Workshop selection
 ↓
COOPER or COOPER Private
 ↓
Tool Registry
 ↓
Tool Router / Execution Gateway
 ↓
Tools / Models / Automations / Scripts
 ↓
Results
 ↓
Obsidian or Restricted Storage
```

COOPER should:

- understand user intent
- respect the selected workshop
- select the correct capability or workflow
- request approval when needed
- execute through the gateway
- summarize results
- store output in the correct location
- recommend the next action

## Major Layers

### 1. COOPER Layer

The operator layer that interprets the request, applies policy, and governs execution.

### 2. Tool Registry

A catalog of approved capabilities. The registry describes what can be done, under what mode, and with what approval requirements.

### 3. Tool Router

Decision logic that selects the right approved capability for the task.

### 4. Execution Gateway

The mechanism that actually invokes tools, scripts, workflows, or model calls.

### 5. Tool and Model Layer

Cloud models, local models, scripts, APIs, automations, and content tools.

### 6. Storage Layer

Storage is split by workshop and role:

- Knowledge Shelf = Obsidian
- Project Workspace = normal project folders
- Restricted DMZ Workspace = active private processing area
- Secure Vault = VeraCrypt long-term encrypted storage, human-managed
- StandardNotes = human-only secure notes

COOPER does not directly manage VeraCrypt or StandardNotes.
COOPER Private reads and writes only inside the approved Restricted DMZ Workspace.

## Workshops

COOPER is the open workshop.

COOPER Private is the private workshop.

Workshop selection is a human decision, not an inference.

## Toolbox Permission Model

The toolbox architecture maps to the two workshops through a shared permission ladder.

Mappings:

- Toolbox Architecture = Two Workshops
- Tool Registry = Tool Box inventory
- Tool Router = Quartermaster
- Approval Layer = Safety Officer
- Execution Gateway = Workbench

Phase 1 approval rule:

- approval is one-time per workflow or action
- remembered permissions are not stored
- each governed action is approved explicitly

Permission levels:

### Level 0 - Inform Only

- No external action
- No file read or write
- Example: explain, summarize current chat context, recommend next step
- May auto-run

### Level 1 - Read Local Info

- Reads approved local files, configs, or status only
- No writes
- Example: inspect registry, read system status, list approved workflows
- May auto-run inside the correct workshop

### Level 2 - Draft / Write Local Output

- Creates or updates local non-sensitive output
- Example: create Obsidian note, draft markdown, write report draft
- Requires approval
- No remembered permissions in Phase 1

### Level 3 - Call External Service

- Uses cloud AI, web APIs, external webhooks, image generation providers, or research APIs
- Requires approval
- Forbidden in COOPER Private

### Level 4 - Execute Script / Workflow

- Runs PowerShell, Python, n8n, Docker, or local workflow automation
- Requires approval
- Use dry-run where practical

### Level 5 - Destructive or Sensitive Action

- Deletes files, overwrites protected data, modifies credentials, changes security settings, sends restricted data externally, alters the Restricted DMZ Workspace or Secure Vault, installs software, or changes firewall/DNS/security settings
- Blocked by default in Phase 1

### Open Workshop

User-facing model entry:

- COOPER

Purpose:

- capability-first

Default model:

- Claude Sonnet

Allowed:

- cloud AI
- LiteLLM
- n8n general workflows
- web research
- image generation tools
- Obsidian
- cloud APIs
- general automation

Purpose:

- planning
- research
- writing
- coding
- analysis
- report drafting
- tool selection
- non-sensitive automation

Storage:

- Obsidian
- general project folders

### Private Workshop

User-facing model entry:

- COOPER Private

Purpose:

- containment-first

Default model:

- Qwen local via Ollama

Allowed:

- local models only
- local scripts
- local files
- encrypted storage
- restricted workflows
- local-only Open WebUI

Forbidden:

- cloud AI
- third-party providers
- cloud APIs
- external webhooks
- unencrypted storage
- plain-text logging of sensitive material

Storage:

- Restricted DMZ Workspace

Human-managed transfer:

- human extracts approved material from Secure Vault into the Restricted DMZ Workspace
- COOPER Private processes private data inside the Restricted DMZ Workspace
- human reviews output and returns approved material to Secure Vault
- human cleans the DMZ and unmounts the Vault

Private workshop rule:

> Private data does not leave the local environment.

> Private data is not stored unencrypted.

> Private data is not routed to cloud AI.

> Private workflows use local tools only.

Private Workshop must never fall back to cloud models.

## Glossary

- Workshop: the operating environment the user selected
- Tool Box: the approved set of tools available in a workshop
- Drawer: a grouped capability area inside a Tool Box
- Tool: a callable capability, model, script, or workflow
- Quartermaster: the organizer of approved tools and storage
- Safety Officer: the policy layer that blocks unsafe routing
- Workbench: the active execution space for a task
- Knowledge Shelf: general-reference storage in Obsidian
- Project Workspace: general working files
- Restricted DMZ Workspace: active private processing area
- Secure Vault: VeraCrypt long-term encrypted storage, human-managed
- StandardNotes: human-only secure notes

## Toolbox Model

The toolbox is a registry of callable capabilities, not one application.

Tool registry, router, and execution gateway are separate concerns:

- registry = what exists and is approved
- router = what should be selected
- gateway = what actually runs

Recommended drawers:

- Research Drawer
- Writing Drawer
- Coding Drawer
- Image Generation Drawer
- Automation Drawer
- Knowledge Drawer
- Security / Private Drawer
- Reporting Drawer
- System Maintenance Drawer

Example registry entry:

```yaml
tool: generate_image_nanobanana
drawer: image_generation
description: Generate an image from a text prompt
input: prompt
output: image_file
security_mode: general_only
executor: n8n_webhook
approval_required: true
```

## High-Level Data Flow

```text
User request
 → selected workshop
 → approved capability lookup
 → approval check if required
 → execution through gateway
 → result returned to COOPER
 → summary and storage
```

## Governance Rules

- COOPER is the foreman, not the worker.
- Workshop selection is human-decided.
- Private Workshop is an execution boundary, not a personality setting.
- Private Workshop never falls back to cloud models.
- Tool selection must respect the selected workshop and approval policy.
- Approval is required before governed execution.
- Sensitive outputs must go to the Restricted DMZ Workspace or to Secure Vault through human transfer.
- Open Workshop may write to Obsidian or Project Workspace with approval.
- Private Workshop may write only to Restricted DMZ Workspace.
- Private Workshop cannot write to Obsidian unless the human creates a sanitized Category 1 export and switches to Open Workshop.
- The system should prefer approved workflows over ad hoc invention.
- Build less infrastructure until the workflow proves its value.

## Current Phase

The ecosystem is in the documentation and workflow-definition phase.

Current priorities:

- align the source docs around COOPER
- define the tool registry structure
- define the first execution workflows
- define the WF-002 Codex Task Generator boundary
- harden Private Workshop boundaries
- keep the system simple enough to operate consistently

## Related Documents

- `02_COOPER System Specification.md`
- `03_AI Tool Stack & Roles.md`
- `04_Security & Compartmentalization Policy.md`
- `05_Reporting Workflow Standards.md`
- `06_Automation & Workflow Catalog.md`
- `07_Implementation Roadmap.md`
- `08_Obsidian Vault Structure.md`
