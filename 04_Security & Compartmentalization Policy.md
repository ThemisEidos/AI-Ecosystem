# Security & Compartmentalization Policy

## Purpose

This policy defines how information is classified, stored, processed, and shared inside the AI Ecosystem.

The policy uses two practical categories:

- Category 1 = Open Workshop / cloud allowed
- Category 2 = Private Workshop / local only

## Core Principle

Use the least exposed tool that can reasonably complete the task.

The policy is the rule. The architecture enforces the rule. Private Workshop is an execution boundary, not a personality setting.

## COOPER Workshop Mapping

### Open Workshop

Equivalent to:

- Category 1

Open Workshop may use cloud AI, cloud APIs, and general automation when the material is sanitized and the workflow is approved.

### Private Workshop

Equivalent to:

- Category 2

Private Workshop is local-only. It must not route to cloud AI or any third-party execution path.

## Permission Levels

The permission ladder applies inside both workshops, with tighter limits in Private Workshop.

Phase 1 approval rule:

- approval is one-time per workflow or action
- remembered permissions are not stored
- each governed action is approved explicitly

### Level 0 - Inform Only

- no external action
- no file read or write
- may auto-run

### Level 1 - Read Local Info

- read approved local files, configs, or status only
- no writes
- may auto-run inside the correct workshop

### Level 2 - Draft / Write Local Output

- create or update local non-sensitive output
- requires approval
- no remembered permissions in Phase 1

### Level 3 - Call External Service

- cloud AI
- web APIs
- external webhooks
- image generation providers
- research APIs
- requires approval
- allowed only in Open Workshop
- forbidden in Private Workshop

### Level 4 - Execute Script / Workflow

- PowerShell
- Python
- n8n
- Docker
- local workflow automation
- requires approval
- use dry-run where practical
- Private Workshop allows only local scripts and workflows with no cloud calls

### Level 5 - Destructive or Sensitive Action

- deletes files
- renames files
- moves files
- overwrites files
- modifies credentials
- changes security settings
- sends data externally
- alters the Restricted DMZ Workspace or Secure Vault
- installs software
- changes firewall, DNS, or security settings
- blocked by default in Phase 1

Private Workshop rules:

- Levels 0 to 2 are allowed if local and encrypted as appropriate
- Level 3 is forbidden
- Level 4 is local-only and requires approval
- Level 5 is blocked by default
- Private Workshop never falls back to cloud models

File modification actions such as delete, move, rename, or overwrite are Level 5 and blocked in Phase 1.

Software installation is Level 5 and blocked in Phase 1.

## Storage Boundary Model

Open Workshop storage:

- Knowledge Shelf = Obsidian
- Project Workspace = normal project folders

Private Workshop storage:

- Restricted DMZ Workspace = active private processing area
- Secure Vault = VeraCrypt long-term encrypted storage, human-managed
- StandardNotes = human-only secure notes

Rules:

- COOPER does not directly manage VeraCrypt or StandardNotes.
- COOPER Private only reads and writes inside the approved Restricted DMZ Workspace.
- COOPER Private never mounts, unmounts, opens, manages, or receives passwords for VeraCrypt.
- COOPER Private never writes directly to Secure Vault.
- Open Workshop may write to Obsidian or Project Workspace with approval.
- Private Workshop may write only to Restricted DMZ Workspace.
- Private Workshop cannot write to Obsidian unless the human creates a sanitized Category 1 export and switches to Open Workshop.
- Private Workshop cannot access StandardNotes.
- Private Workshop cannot use cloud services.
- Sensitive personal notes remain in StandardNotes and are outside PDA automation scope.
- WF-002 Codex task files are project artifacts and live in Project Workspace Codex_Tasks/ by default.
- Do not place WF-002 task files in Obsidian unless they have been sanitized and intentionally moved as Category 1 material.

Private workflow lifecycle:

```text
Secure Vault
 ↓ human-controlled extraction
Restricted DMZ Workspace
 ↓ COOPER Private processing
Restricted DMZ Workspace output
 ↓ human review
Secure Vault
 ↓ human-controlled return/archive
DMZ cleanup
```

## Category 1 - Open Workshop / Cloud Allowed

Category 1 is information that may be processed with cloud tools if doing so is appropriate.

Examples:

- planning
- public research
- sanitized report structures
- non-sensitive writing drafts
- workflow ideas
- tool comparisons
- general technical questions
- templates

Approved handling:

- cloud AI
- Obsidian
- StandardNotes where appropriate
- Open WebUI
- Ollama
- n8n
- LiteLLM
- Python
- PowerShell
- Docker

## Category 2 - Private Workshop / Local Only

Category 2 is information that must not leave the local environment.

Examples:

- credentials
- API keys
- passwords
- private keys
- client-sensitive data
- investigative material
- PII
- unredacted reports
- restricted logs
- operational details
- security findings tied to real systems

Approved handling:

- local machine
- encrypted storage
- VeraCrypt
- local scripts
- offline review
- Open WebUI with local-only models
- Ollama
- manual analysis

Prohibited by default:

- cloud AI
- cloud APIs
- public webhooks
- unencrypted storage
- normal cloud sync
- plain-text logging of sensitive material

## Private Workshop Rules

```text
Private data does not leave the local environment.
Private data is not stored unencrypted.
Private data is not routed to cloud AI.
Private workflows use local tools only.
```

Private Workshop must never fall back to cloud models.

## Storage Separation

Recommended structure:

```text
Obsidian Vault
→ Category 1 / sanitized / working knowledge

VeraCrypt Container
→ Category 2 / restricted / cannot share

Local Restricted Folder
→ Category 2 working files

Cloud AI Chats
→ Category 1 only
```

Rule:

```text
If it is Category 2, it starts and stays inside the Restricted DMZ Workspace or Secure Vault through human transfer.
```

## Workspace Separation

Use separate workspaces for general and restricted work.

General workspace:

- Obsidian
- cloud AI tools
- general browser profiles
- non-sensitive files

Restricted workspace:

- VeraCrypt mounted folder
- local scripts
- Ollama
- local-only Open WebUI
- local documents
- restricted browser profile

Rule:

```text
Category 2 data should never enter a workspace that has easy access to cloud AI.
```

## Browser and Profile Separation

Use separate browser profiles.

Cloud profile:

- ChatGPT
- Claude
- Gemini
- Perplexity
- general research tools

Restricted local profile:

- local-only Open WebUI
- localhost tools
- local documentation
- local admin panels

Rule:

```text
When working Category 2 material, use a browser profile where cloud AI tools are not logged in.
```

## Credential Separation

Do not make cloud credentials available inside restricted environments.

Category 2 environments should include:

- no cloud AI API keys
- no cloud storage tokens
- no external automation credentials
- local model access only
- restricted file access

## Sanitization Gate

Cloud AI may only receive sanitized Category 1 material.

Remove or generalize:

- names
- addresses
- phone numbers
- emails
- credentials
- client names
- company names
- facility details
- access details
- IP addresses
- hostnames
- screenshots with sensitive metadata

Rule:

```text
Only sanitized summaries can move from Category 2 to Category 1.
```

## Network Controls

Restricted environments should not have easy network access to cloud AI endpoints.

Useful controls:

- NextDNS denylist profile
- local firewall rules
- separate VM network rules
- hosts file blocking
- router-level rules

## Incident Response

If Category 2 material is exposed:

1. stop using the affected workflow
2. identify what was exposed
3. identify where it was sent or stored
4. revoke or rotate exposed credentials if needed
5. document the incident
6. move future processing into a safer compartment

For exposed secrets, assume compromise and rotate immediately.

## Final Standard

Category 1:

- Open Workshop allowed when appropriate
- privacy-conscious handling

Category 2:

- Private Workshop only
- encrypted
- or no AI

Supporting enforcement:

- storage separation
- workspace separation
- browser profile separation
- local-only AI path
- credential separation
- network friction
- sanitization gate
- manual review

## Glossary

- Knowledge Shelf: Obsidian
- Project Workspace: general working files
- Restricted DMZ Workspace: active private processing area
- Secure Vault: VeraCrypt long-term encrypted storage, human-managed
- StandardNotes: human-only secure notes

## Glossary

- Workshop: the selected operating environment
- Tool Box: the approved tools for a workshop
- Drawer: a grouped capability area
- Tool: a callable capability, model, script, or workflow
- Quartermaster: the storage and inventory organizer
- Safety Officer: the policy layer that blocks unsafe handling
- Workbench: the active working space
- Knowledge Shelf: general-reference storage
- Secure Vault: VeraCrypt long-term encrypted storage, human-managed
