# Obsidian Vault Structure

## Purpose

This document defines the recommended Obsidian vault structure for the AI Ecosystem.

The vault should be a working knowledge base, not a note dump. It should support COOPER, reports, prompts, workflows, and project documentation without mixing in sensitive material that belongs in the Restricted DMZ Workspace or Secure Vault.

Storage boundary terms:

- Knowledge Shelf = Obsidian
- Project Workspace = general working files
- Restricted DMZ Workspace = active private processing area
- Secure Vault = VeraCrypt long-term encrypted storage, human-managed
- StandardNotes = human-only secure notes

## Structure

Recommended top-level layout:

```text
PDA-Obsidian-Vault/
├── 00_Inbox/
├── 01_Dashboard/
├── 02_Projects/
├── 03_Areas/
├── 04_Resources/
├── 05_Reports/
├── 06_AI-Systems/
├── 07_Automations/
├── 08_Prompts/
├── 09_Templates/
├── 10_Archive/
└── _Attachments/
```

## Where Core AI Ecosystem Docs Live

- AI ecosystem architecture and COOPER docs should live in the project area for the AI Ecosystem.
- Workflow definitions should live in the automation and workflow catalog.
- Report standards should live in the reporting area.
- Prompt libraries should live in the prompts area.
- Templates should live in the templates area.

The Obsidian vault is the Knowledge Shelf, not the Secure Vault.
The Secure Vault and StandardNotes are outside the Obsidian automation surface.

## Recommended Project Layout

```text
02_Projects/
└── AI Tool Ecosystem/
    ├── Project Overview.md
    ├── 01_AI Ecosystem Architecture.md
    ├── 02_COOPER System Specification.md
    ├── 03_AI Tool Stack & Roles.md
    ├── 04_Security & Compartmentalization Policy.md
    ├── 05_Reporting Workflow Standards.md
    ├── 06_Automation & Workflow Catalog.md
    ├── 07_Implementation Roadmap.md
    └── 08_Obsidian Vault Structure.md
```

## Sensitive Material

Do not keep sensitive material in a normal vault unless the vault is itself protected.

Sensitive material should go to:

- Restricted DMZ Workspace for active processing
- Secure Vault for long-term protected storage after human review
- password manager for secrets

Examples of sensitive material:

- credentials
- API keys
- passwords
- unredacted reports
- client-sensitive notes
- investigative material
- restricted logs
- private notes

## Naming Conventions

Use clear descriptive names.

Good:

- `Project Overview.md`
- `System Status.md`
- `Workflow Catalog.md`
- `Report Template.md`
- `Automation Checklist.md`

Avoid:

- `stuff.md`
- `final_final.md`
- `notes copy 2.md`
- vague or temporary names

Recommended format:

```text
Descriptive Title.md
```

Date-based notes may use:

```text
YYYY-MM-DD Daily Log.md
YYYY-MM Weekly Review.md
YYYY-MM Monthly Review.md
```

## Templates

Templates should cover the core repeatable documents:

- project notes
- workflow records
- report outlines
- review checklists
- decision logs
- prompt templates

## Simplified Operating Rule

- keep the vault structured
- keep the vault useful
- keep the vault readable
- keep sensitive data out of the normal vault
- move deep productivity methodology into supporting material rather than repeating it here
- use the Restricted DMZ Workspace for active private work
- use the Secure Vault for long-term protected storage

## Final Standard

The vault should support:

- projects
- areas
- resources
- reports
- AI systems
- automations
- prompts
- templates
- archives

The structure should stay simple enough that it can be maintained consistently.
