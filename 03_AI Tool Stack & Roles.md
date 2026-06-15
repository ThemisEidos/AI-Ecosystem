# AI Tool Stack & Roles

## Purpose

This document defines the role of each tool, model, and service in the AI Ecosystem.

The stack is organized by capability role, not by hype or brand loyalty. Tools may change. Roles should stay stable.

## Core Principle

Do not organize the ecosystem around one vendor or one model.

Organize it around roles:

```text
Reasoning
Research
Writing
Coding
Automation
Local / private AI
Multimodal analysis
Report production
Knowledge management
Model routing
Security boundaries
```

## Model Policy

- Open Workshop default = Claude Sonnet
- Private Workshop default = Qwen local via Ollama

## Tool Drawer Categories

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

## Baseline Stack

Current baseline capabilities:

- Claude
- ChatGPT
- Gemini
- Perplexity
- Obsidian
- StandardNotes
- n8n
- LiteLLM
- Open WebUI
- Ollama
- Docker
- VeraCrypt
- Proton ecosystem
- NextDNS
- PowerShell scripts
- Python scripts

## Fabric and Workspace Roles

- Fabric is the reusable prompt-pattern layer.
- Fabric stores cognitive workflow patterns such as analysis, summarization, report review, threat analysis, and decision support.
- Open WebUI Workspace is the knowledge and reference-asset layer.
- Open WebUI Workspace may hold governance collections, project documentation, technical references, and training or research collections.
- Open WebUI Workspace should not hold tool registries, approval rules, runtime state, secrets, private data, or personality state.
- COOPER remains the governed orchestrator that can later select Fabric patterns and consult Workspace collections.

## Role Table

| Role | Primary Tool | Backup / Secondary |
|---|---|---|
| General analysis | Claude Sonnet | ChatGPT, Gemini |
| Structured planning | Claude Sonnet | ChatGPT |
| Report drafting | Claude Sonnet | ChatGPT |
| Report editing and critique | Claude | ChatGPT |
| Current research | Perplexity | ChatGPT with browsing, Gemini |
| Large document review | Gemini | Claude, ChatGPT |
| Coding assistance | ChatGPT | Claude, Gemini |
| Local / private chat | Open WebUI | Ollama direct |
| Local model runtime | Ollama | Other local runtimes |
| Model routing | LiteLLM | Direct APIs |
| Workflow automation | n8n | Python, PowerShell |
| Knowledge base | Obsidian | Local markdown folders |
| Sensitive notes | StandardNotes | VeraCrypt / encrypted storage |
| Sensitive files | VeraCrypt | Encrypted local folders |
| Network filtering | NextDNS | Local firewall rules |
| Containerized services | Docker | Native installs / VMs |
| Report products | Markdown, Word, PDF, PowerPoint | Export tools |

## Stack Layers

### User Interfaces

Purpose:

```text
Thinking, writing, research, analysis, interaction, and review.
```

Tools:

```text
Claude
ChatGPT
Gemini
Perplexity
Open WebUI
Obsidian
StandardNotes
```

### Model Access

Purpose:

```text
Model selection, routing, local/cloud access, provider abstraction, and experimentation.
```

Tools:

```text
Direct subscriptions
API keys
LiteLLM
Open WebUI
Ollama
Cloud model providers
Local models
```

### Automation

Purpose:

```text
Repeatable processes, scheduled jobs, document processing, API workflows, and human-in-the-loop automation.
```

Tools:

```text
n8n
Python scripts
PowerShell scripts
cron jobs
Docker containers
API workflows
```

### Knowledge and Files

Purpose:

```text
Knowledge management, sensitive storage, documentation, source material, and long-term retrieval.
```

Tools:

```text
Obsidian
StandardNotes
Proton Drive
VeraCrypt
Local encrypted folders
File system folders
```

### Outputs

Purpose:

```text
Finished analytical products.
```

Outputs:

```text
Markdown
Word documents
PDFs
PowerPoint decks
Charts
Dashboards
Reports
Briefing notes
Automation logs
Decision records
```

## Role-Based Tool Selection

Tools should be evaluated by:

- task fit
- privacy impact
- automation value
- maintenance burden
- integration cost
- output quality
- security boundary

## Permission Table

| Level | Scope | Approval | Private Workshop |
|---|---|---|---|
| 0 | Inform only | No | Allowed |
| 1 | Read local info | No if inside correct workshop | Allowed |
| 2 | Draft / write local output | Yes | Allowed if local and encrypted as appropriate |
| 3 | External service | Yes | Forbidden |
| 4 | Script / workflow execution | Yes | Allowed if local-only |
| 5 | Destructive or sensitive action | Blocked by default in Phase 1 | Blocked by default |

## Operating Rule

Use the best tool for the role, not the most popular tool.

If a task is private, use local-only tooling in the Private Workshop.
If a task is open, use the approved Open Workshop stack.
If a workflow is not defined, define the workflow before adding more tools.

## Glossary

- Workshop: the selected operating environment
- Tool Box: the approved set of tools in a workshop
- Drawer: a grouped capability category
- Tool: a callable capability, model, script, or workflow
- Quartermaster: the tool and storage organizer
- Safety Officer: the policy layer that blocks unsafe use
- Workbench: the active execution space
- Knowledge Shelf: general-reference storage
- Open WebUI Workspace: knowledge and reference-asset layer
- Fabric: reusable prompt-pattern and cognitive workflow layer
- Secure Vault: restricted encrypted storage
- Codex Task Queue: Project Workspace folder for WF-002 task files
