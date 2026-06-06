# AI Tool Stack & Roles

## Purpose

This document defines the role of each AI tool, model, platform, and supporting service in the AI operations ecosystem.

It answers:

> Which AI tool should be used for which job, and why?

This document is a starting baseline, not a final tool list. AI tools, models, APIs, pricing, privacy terms, and specialized platforms will change over time. The ecosystem should be designed around stable roles rather than brand loyalty.

---

## Core Principle

Do not organize the ecosystem around one company, one model, or one interface.

Organize the ecosystem around capability roles:

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

The tools may change. The roles should remain stable.

---

## Living Inventory Standard

This document should be reviewed and updated as the ecosystem matures.

Tools may be:

- added
- removed
- replaced
- merged
- downgraded
- promoted
- moved into a different role
- retained only as backups

A new tool should not be added just because it is interesting. It should fill a defined role or improve an existing workflow.

### Expansion Principle

This document is a starting baseline, not a final tool list.

AI tools, models, APIs, and specialized platforms will change over time. The ecosystem should be updated by role, not by brand loyalty.

When a new tool is discovered, it should be evaluated against the existing role architecture:

- What role does it fill?
- Does it replace an existing tool?
- Does it supplement an existing tool?
- Does it introduce a new capability?
- Does it improve privacy, cost, speed, quality, or automation?
- Does it create unnecessary complexity?
- Can it integrate with the existing stack?
- Does it create security or compartmentalization concerns?
- Does it require ongoing maintenance?

Tools may be added, removed, merged, or replaced as the ecosystem matures.

---

## Strategic Architecture

The ecosystem should use layered architecture:

```text
User
 ↓
Knowledge Base / Working Notes
 ↓
AI Interfaces and Assistants
 ↓
Model Gateway / Local and Cloud Models
 ↓
Automation Layer
 ↓
Outputs / Reports / Dashboards / Briefings
```

Expanded:

```text
User
 ↓
Obsidian / StandardNotes / Source Material
 ↓
ChatGPT / Claude / Gemini / Perplexity / Open WebUI
 ↓
LiteLLM / APIs / Ollama / Cloud Models / Local Models
 ↓
n8n / Scripts / Docker / Scheduled Workflows
 ↓
Reports / PDFs / PowerPoints / Charts / Briefings / Logs
```

---

## Current Baseline Stack

The starting baseline includes:

```text
ChatGPT
Claude
Gemini
Perplexity
Obsidian
StandardNotes
n8n
LiteLLM
Open WebUI
Ollama
Docker
VeraCrypt
Proton ecosystem
NextDNS
PowerShell scripts
Python scripts
Local Linux infrastructure
```

This list will expand over time.

---

## Recommended Role Table

| Role | Primary Tool | Backup / Secondary |
|---|---|---|
| General analysis | ChatGPT | Claude, Gemini |
| Structured project planning | ChatGPT | Claude |
| Report drafting | ChatGPT | Claude |
| Report editing and critique | Claude | ChatGPT |
| Current research | Perplexity | ChatGPT with browsing, Gemini |
| Source discovery | Perplexity | ChatGPT with browsing |
| Large document review | Gemini | Claude, ChatGPT |
| Coding assistance | ChatGPT | Claude, Gemini |
| Code review | Claude | ChatGPT |
| Local / private chat | Open WebUI | Ollama direct |
| Local model runtime | Ollama | LM Studio or other runtimes |
| Model routing | LiteLLM | OpenRouter or direct APIs |
| Workflow automation | n8n | Python, PowerShell, cron |
| Knowledge base | Obsidian | Local markdown folders |
| Sensitive notes | StandardNotes | VeraCrypt / encrypted storage |
| Sensitive files | VeraCrypt | Proton Drive / encrypted local folders |
| Network filtering | NextDNS | Local firewall / router rules |
| Containerized services | Docker | Native installs / VMs |
| Report products | Markdown, Word, PDF, PowerPoint | Specialized export tools |
| Charts and visuals | Python, spreadsheets, BI tools | AI-assisted chart generation |

---

## Stack Layers

## Layer 1 — User Interfaces

Purpose:

```text
Thinking, writing, research, analysis, interaction, and review.
```

Tools:

```text
ChatGPT
Claude
Gemini
Perplexity
Open WebUI
Obsidian
StandardNotes
```

This is the layer where most human interaction occurs. It should remain simple and usable. Avoid spreading the same work across too many interfaces unless there is a specific reason.

---

## Layer 2 — Model Access

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

This layer should reduce dependency on any single provider. Over time, LiteLLM and Open WebUI can become important for managing multiple models from one interface or one API-compatible gateway.

---

## Layer 3 — Automation

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

Automation should start small. Do not automate a broken process. First define the workflow manually, then automate repeated steps.

---

## Layer 4 — Knowledge and Files

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

Obsidian should be the structured knowledge base. StandardNotes and encrypted storage should handle sensitive material that should not live in a normal markdown vault.

---

## Layer 5 — Outputs

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

The ecosystem should support clean export from working notes to polished products.

---

## Tool Roles

## ChatGPT

### Recommended Role

```text
Primary general-purpose analyst and project partner.
```

### Best For

- structured reasoning
- project planning
- TCREI workflows
- report drafting
- workflow design
- technical explanation
- coding assistance
- document generation
- executive summaries
- synthesis across multiple domains

### Use ChatGPT When

```text
You need structured thinking, planning, report development, synthesis, coding, or document generation.
```

### Caution

Do not use ChatGPT as the source of truth for sensitive, legal, current, or highly specific claims without verification.

---

## Claude

### Recommended Role

```text
Senior editor, prose specialist, and second-opinion analyst.
```

### Best For

- long-form writing
- report critique
- tone refinement
- editing
- policy-style drafting
- nuanced reasoning
- code review
- alternative analysis

### Use Claude When

```text
You need careful writing, editing, critique, prose refinement, or a second analytical review.
```

### Caution

Claude should not replace source verification. Use it as a strong writing and reasoning partner.

---

## Gemini

### Recommended Role

```text
Large-context and multimodal analyst.
```

### Best For

- long-context review
- Google ecosystem support
- document-heavy review
- image analysis
- video analysis
- alternative model comparison
- multimodal workflows
- coding support

### Use Gemini When

```text
You need long-context review, multimodal analysis, Google ecosystem integration, or alternative model comparison.
```

### Caution

Verify output against source documents, especially when working with long context or summarized material.

---

## Perplexity

### Recommended Role

```text
Research scout and source discovery tool.
```

### Best For

- current web research
- source discovery
- vendor comparison
- market scanning
- quick background research
- finding relevant references
- identifying recent developments

### Use Perplexity When

```text
You need current research, quick source discovery, or market/tool scanning.
```

### Caution

Do not stop at the first answer. Follow sources, compare results, and preserve citations when the research supports a report.

---

## Obsidian

### Recommended Role

```text
Knowledge base and project brain.
```

### Best For

- project documentation
- linked notes
- source documents
- templates
- prompts
- workflows
- dashboards
- report planning
- long-term knowledge development

### Use Obsidian When

```text
You need structured, reusable, linked, long-term knowledge.
```

### Caution

Do not store sensitive raw material in a normal Obsidian vault unless the vault/storage environment is properly protected.

---

## StandardNotes

### Recommended Role

```text
Secure notes and sensitive personal knowledge.
```

### Best For

- sensitive notes
- private reflections
- protected planning
- information that should not be exposed to general cloud AI tools
- secure text storage

### Use StandardNotes When

```text
The material is more sensitive than normal Obsidian notes.
```

### Caution

Do not duplicate sensitive information into less secure systems for convenience.

---

## Open WebUI

### Recommended Role

```text
Local and hybrid AI command console.
```

### Best For

- self-hosted AI interface
- local model access
- Ollama integration
- OpenAI-compatible APIs
- hybrid local/cloud model experimentation
- model switching

### Use Open WebUI When

```text
You want a self-hosted chat interface for local and hybrid models.
```

### Caution

Open WebUI is powerful but adds maintenance overhead. Keep the deployment simple until the workflow proves useful.

---

## LiteLLM

### Recommended Role

```text
AI model switchboard and API gateway.
```

### Best For

- routing between providers
- OpenAI-compatible API access
- cost tracking
- budget control
- provider abstraction
- fallbacks
- centralized model access
- future-proofing against model churn

### Use LiteLLM When

```text
You want one API gateway for multiple model providers with routing, spend tracking, and provider abstraction.
```

### Caution

Do not add LiteLLM before there is a clear need for multi-model routing. It is valuable, but it adds architecture complexity.

---

## Ollama

### Recommended Role

```text
Local model engine.
```

### Best For

- local model execution
- offline AI
- private experimentation
- lightweight inference
- local prototypes
- integration with Open WebUI
- testing open models

### Use Ollama When

```text
You want to run models locally for experimentation, privacy-conscious workflows, or offline use.
```

### Caution

Local models may be less capable than leading cloud models. Use them where privacy, experimentation, or offline operation matters more than maximum capability.

---

## n8n

### Recommended Role

```text
Automation engine.
```

### Best For

- workflow automation
- AI-assisted workflows
- document routing
- API integrations
- scheduled tasks
- human-in-the-loop automation
- report pipeline automation
- notifications
- data movement between systems

### Use n8n When

```text
You want to automate repeatable workflows or connect AI to tools, files, APIs, and scheduled processes.
```

### Caution

Do not automate too early. First define the manual process, then automate repeatable steps.

---

## Docker

### Recommended Role

```text
Containerized service layer.
```

### Best For

- running local services
- isolating tools
- repeatable deployments
- n8n
- Open WebUI
- LiteLLM
- databases
- supporting infrastructure

### Use Docker When

```text
You want repeatable, isolated, easy-to-redeploy services.
```

### Caution

Docker improves portability but can complicate networking, permissions, persistence, and backups if not documented.

---

## VeraCrypt

### Recommended Role

```text
Sensitive file compartmentalization.
```

### Best For

- encrypted containers
- sensitive reports
- source material
- client-sensitive documents
- backups
- offline protected storage

### Use VeraCrypt When

```text
You need strong local compartmentalization for files that should not live exposed in normal folders.
```

### Caution

Maintain backups and recovery procedures. Losing the password or key material may mean losing access permanently.

---

## Proton Ecosystem

### Recommended Role

```text
Privacy-respecting cloud layer.
```

### Best For

- email
- aliases
- cloud storage
- VPN
- privacy-conscious communications
- secure external sharing when appropriate

### Use Proton When

```text
You need a privacy-focused alternative to mainstream cloud, email, or VPN services.
```

### Caution

Cloud storage is still cloud storage. Sensitive material should be encrypted before upload when appropriate.

---

## NextDNS

### Recommended Role

```text
Network-level filtering and security support.
```

### Best For

- DNS filtering
- blocking known malicious domains
- privacy filtering
- telemetry reduction
- device-level policy support
- visibility into DNS behavior

### Use NextDNS When

```text
You want DNS-level security, filtering, and privacy support across devices.
```

### Caution

DNS filtering is not a replacement for endpoint security, VPN, firewall controls, or safe browsing behavior.

---

## Python Scripts

### Recommended Role

```text
Custom analysis, transformation, and automation support.
```

### Best For

- data cleanup
- report formatting
- charting
- file processing
- API interaction
- automation glue
- parsing logs
- spreadsheet work
- repeatable technical workflows

### Use Python When

```text
You need flexible data handling, analysis, file manipulation, or automation that does not require a full platform.
```

### Caution

Scripts should be documented, versioned, and tested before being trusted for important workflows.

---

## PowerShell Scripts

### Recommended Role

```text
Windows automation and operational scripting.
```

### Best For

- Windows setup
- file management
- application launchers
- developer environment setup
- system checks
- repeatable local workflows
- project maintenance

### Use PowerShell When

```text
You need repeatable Windows-focused automation.
```

### Caution

Scripts should avoid destructive actions unless reviewed and tested. Include logging and dry-run options where practical.

---

## Tool Selection Rules

## Use ChatGPT When

```text
You need structured reasoning, planning, report development, synthesis, coding, or document generation.
```

## Use Claude When

```text
You need careful writing, editing, critique, prose refinement, or a second analytical review.
```

## Use Gemini When

```text
You need long-context review, multimodal analysis, Google ecosystem integration, or alternative model comparison.
```

## Use Perplexity When

```text
You need current research, quick source discovery, or market/tool scanning.
```

## Use Open WebUI When

```text
You want a self-hosted chat interface for local and hybrid models.
```

## Use LiteLLM When

```text
You want one API gateway for multiple model providers with routing, spend tracking, and provider abstraction.
```

## Use Ollama When

```text
You want to run models locally for experimentation, privacy-conscious workflows, or offline use.
```

## Use n8n When

```text
You want to automate repeatable workflows or connect AI to tools, files, APIs, and scheduled processes.
```

## Use Obsidian When

```text
You need structured, linked, reusable long-term knowledge.
```

## Use StandardNotes When

```text
The information is more sensitive than normal vault material.
```

## Use VeraCrypt When

```text
Files require stronger local compartmentalization.
```

---

## Model Churn Strategy

Models will change.

The ecosystem should expect that.

Use this principle:

> Do not hardcode the ecosystem around one model. Route tasks by role, not by model name.

### Bad Pattern

```text
Use Model X for everything.
```

### Better Pattern

```text
Use the best available reasoning model for deep analysis.
Use the best available writing model for editing.
Use the best available research tool for source discovery.
Use a local model for private low-risk drafting.
Use routing tools when multiple providers become necessary.
```

LiteLLM, Open WebUI, APIs, and local runtimes reduce dependence on any single provider.

---

## Security Boundaries

## Low Sensitivity

May use:

```text
ChatGPT
Claude
Gemini
Perplexity
cloud APIs
Open WebUI
Ollama
```

Examples:

```text
general planning
public research
template drafting
generic reports
learning notes
non-sensitive code examples
tool comparison
workflow design
```

---

## Moderate Sensitivity

Prefer:

```text
ChatGPT / Claude / Gemini only when data is sanitized
Open WebUI
Ollama
local files
encrypted storage
StandardNotes
```

Examples:

```text
internal workflows
personal planning
sanitized report notes
non-public project architecture
professional development material
draft templates
non-sensitive operational planning
```

---

## High Sensitivity

Prefer:

```text
local-only tools
encrypted storage
VeraCrypt
offline notes
manual review
no cloud AI unless explicitly approved and sanitized
```

Examples:

```text
credentials
API keys
client-sensitive data
operational details
PII
legal or investigative material
restricted logs
sensitive source documents
unredacted reports
```

### Security Rule

> Obsidian organizes the workflow. Protected storage holds sensitive material.

---

## New Tool Evaluation Criteria

Before adding a new tool to the ecosystem, evaluate:

```text
Role
Capability
Cost
Privacy
Security
API access
Local / self-hosted option
Export options
File support
Model quality
Automation support
Vendor lock-in risk
Reliability
Maintenance burden
Learning curve
Integration value
```

### Scoring Scale

```text
1 = poor
2 = limited
3 = acceptable
4 = strong
5 = excellent
```

---

## Tool Evaluation Template

```markdown
# Tool Evaluation: [Tool Name]

## Intended Role

## Primary Use Case

## Strengths

## Weaknesses

## Cost / Pricing Notes

## Privacy / Security Notes

## API / Integration Notes

## Local or Cloud

## File / Data Support

## Automation Support

## Best Fit in Ecosystem

## Replacement / Backup Tool

## Complexity Added

## Decision

Adopt / Test / Watch / Reject

## Review Date
```

---

## Future Tool Categories to Add

The ecosystem may later add tools in these categories:

```text
report generation tools
charting and visualization tools
PowerPoint / slide generation tools
local document processing tools
OCR tools
PDF extraction tools
coding agents
OSINT / research tools
graph database tools
vector database tools
knowledge graph tools
automation connectors
voice transcription tools
meeting summary tools
secure file transfer tools
local search tools
dashboard tools
spreadsheet automation tools
diagramming tools
threat intelligence tools
DFIR tools
privacy auditing tools
```

Each category should be added only when there is a real use case.

---

## Recommended Initial Operating Stack

The current starting stack is:

```text
ChatGPT = primary analyst and project partner
Claude = writing/editorial second opinion
Gemini = long-context and Google ecosystem support
Perplexity = research scout
Obsidian = knowledge base and project brain
StandardNotes = sensitive notes
LiteLLM = future API gateway
Open WebUI = local/hybrid AI interface
Ollama = local model runtime
n8n = automation engine
Docker = containerized service layer
VeraCrypt = sensitive file compartmentalization
Proton ecosystem = privacy-respecting cloud layer
NextDNS = network-level filtering and security support
Python = custom analysis and automation
PowerShell = Windows automation and project maintenance
```

---

## Review Cycle

Review this document:

```text
Monthly during active ecosystem development
Quarterly once the system stabilizes
Immediately when a major model, tool, API, pricing, privacy, or security change occurs
```

---

## Change Log

| Date | Change | Reason |
|---|---|---|
| YYYY-MM-DD | Created baseline tool stack and role architecture | Initial ecosystem setup |
| YYYY-MM-DD | Added tool | New capability or workflow requirement |
| YYYY-MM-DD | Removed tool | Redundant, costly, insecure, or no longer useful |
| YYYY-MM-DD | Changed role | Tool capability or ecosystem need changed |

---

## Final Operating Standard

The AI tool ecosystem should remain:

```text
role-based
modular
secure
compartmentalized
local-first when practical
cloud-assisted when useful
automation-ready
easy to update
not dependent on one vendor
not overengineered too early
```

The stack should evolve as the work evolves.

The stable question is not:

> What is the best AI tool?

The better question is:

> What role needs to be filled, and which tool currently fills that role best?
```
