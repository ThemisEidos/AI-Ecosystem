# Security & Compartmentalization Policy

## Purpose

This document defines how information is classified, stored, processed, protected, and shared inside the AI operations ecosystem.

It answers:

> What information can be processed by cloud AI, what must stay local, and what controls prevent accidental exposure?

This policy is designed to keep the ecosystem practical. It uses two categories instead of a complex multi-tier classification model.

---

## Core Principle

Separate information by whether it may be shared or cannot be shared.

```text
Category 1 = Things I prefer not to share
Category 2 = Things that cannot be shared
```

The operating rule is:

> Use the least exposed tool that can reasonably complete the task.

The policy is the rule.  
The architecture enforces the rule.

---

## Classification Model

## Category 1 — Private / Prefer Not Shared

Category 1 includes information that should be handled thoughtfully, but may be processed by cloud AI if the exposure is acceptable or the information is sanitized.

### Examples

```text
personal productivity notes
career planning
general project ideas
AI ecosystem planning
sanitized report structures
generic business ideas
training notes
tool comparisons
non-sensitive writing drafts
workflow ideas
public research
general technical questions
non-sensitive code examples
templates
```

### Handling Rule

```text
Cloud AI may be used when appropriate, especially if the material is sanitized.
```

### Approved Tools

```text
ChatGPT
Claude
Gemini
Perplexity
Obsidian
StandardNotes
Open WebUI
Ollama
n8n
LiteLLM
Python
PowerShell
Docker
```

### Practical Standard

For Category 1, the goal is privacy-conscious use, not absolute isolation.

Use cloud AI when it adds value, but avoid unnecessary exposure.

---

## Category 2 — Restricted / Cannot Be Shared

Category 2 includes information that should not be sent to cloud AI, public tools, third-party platforms, or insecure storage.

### Examples

```text
PII
client-sensitive data
legal material
investigative material
credentials
API keys
passwords
private keys
security findings tied to real systems
facility layouts
access control details
badge or security system information
sensitive screenshots
private logs
unredacted reports
protected work material
active operational details
restricted government or organizational material
security exploit details tied to real targets
confidential source documents
```

### Handling Rule

```text
Local only, encrypted, or do not process with AI at all.
```

### Approved Handling

```text
local machine
encrypted storage
VeraCrypt
StandardNotes where appropriate
offline review
local scripts
Open WebUI with local-only models
Ollama
manual analysis
```

### Prohibited by Default

```text
ChatGPT
Claude
Gemini
Perplexity
cloud APIs
cloud automation tools
cloud document processors
normal cloud sync
unprotected Obsidian vaults
```

Exception:

```text
Category 2 material may be transformed into Category 1 only after proper sanitization.
```

---

## Category 2 Rule of Thumb

For Category 2:

```text
If it cannot be shared, do not upload it.
If it must be analyzed, keep it local.
If local AI is not good enough, sanitize it.
If it cannot be sanitized, analyze it manually.
```

---

## Decision Tree

Before using any AI tool, classify the material.

```text
1. Does this contain PII, credentials, client data, security data, legal/investigative material, or operational details?

   Yes → Category 2
   No → Continue

2. Would I be uncomfortable if this was exposed outside my system?

   Yes → Category 1
   No → Category 1 / public-safe

3. Does the task require the actual raw data?

   Yes → Use approved handling for that category
   No → sanitize or abstract it

4. Can a local tool do the job?

   Yes → prefer local for Category 2
   No → do not process Category 2 with AI unless sanitized
```

---

## Enforcement Model

A written policy does not enforce itself.

Enforcement comes from:

```text
storage separation
workspace separation
browser/profile separation
local-only processing
credential separation
network controls
sanitization gates
habit and review
```

The goal is to make the unsafe path harder than the safe path.

---

# 1. System Security Baseline

The operating system and device environment are the foundation for both categories.

Minimum baseline:

```text
full-disk encryption where practical
strong login password
password manager
MFA where available
regular OS updates
firewall enabled
NextDNS or equivalent DNS filtering
VPN when appropriate
least-privilege user account where practical
separate workspaces or profiles
encrypted containers for restricted files
controlled backups
no secrets in plain text
no sensitive files in casual sync folders
regular review of connected apps and API keys
```

The OS and device should be secure enough that Category 2 local handling is meaningful.

---

# 2. Storage Separation

Category 2 material should not live in the same place as normal AI-working material.

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

### Storage Rule

```text
If it is Category 2, it starts and stays inside restricted storage.
```

### Obsidian Role

Obsidian is primarily a Category 1 system.

Use Obsidian for:

```text
sanitized notes
templates
project architecture
AI workflows
prompts
general knowledge
reporting standards
productivity systems
tool evaluations
non-sensitive project notes
```

Do not use normal Obsidian vaults for:

```text
credentials
API keys
client-sensitive raw notes
restricted investigative material
unredacted reports
protected evidence
sensitive screenshots
security details tied to real systems
```

If Category 2 material must be stored in Obsidian, the vault should be inside encrypted storage and treated as restricted.

---

# 3. Workspace Separation

Use separate workspaces for different sensitivity levels.

## General Workspace

Used for Category 1.

May include:

```text
Obsidian
ChatGPT
Claude
Gemini
Perplexity
n8n general workflows
cloud APIs
browser tabs
non-sensitive files
```

## Restricted Workspace

Used for Category 2.

Should include:

```text
VeraCrypt mounted folder
local scripts
Ollama
Open WebUI local-only
local documents
manual review tools
restricted browser profile
```

Should not include:

```text
logged-in cloud AI accounts
cloud API credentials
cloud sync tools unless encrypted first
public upload tools
general-purpose automation with cloud access
```

### Workspace Rule

```text
Category 2 data should never enter a workspace that has easy access to cloud AI.
```

---

# 4. Browser and Profile Separation

Use separate browser profiles to reduce accidental exposure.

## Cloud AI Profile

Used for Category 1.

May include:

```text
ChatGPT
Claude
Gemini
Perplexity
API dashboards
research tools
general web access
```

## Restricted Local Profile

Used for Category 2.

Should include:

```text
Open WebUI local-only
localhost tools
local documentation
local admin panels
```

Should not include:

```text
logged-in ChatGPT
logged-in Claude
logged-in Gemini
logged-in Perplexity
cloud AI API dashboards
general upload tools
```

### Browser Rule

```text
When working Category 2 material, use a browser profile where cloud AI tools are not logged in.
```

---

# 5. Local-Only AI Path

For Category 2, the approved AI path is:

```text
Category 2 Material
 ↓
VeraCrypt / encrypted local folder
 ↓
local script or local parser
 ↓
Ollama local model
 ↓
Open WebUI local-only interface
 ↓
local output saved back to encrypted storage
```

Not:

```text
Category 2 Material
 ↓
ChatGPT / Claude / Gemini / Perplexity
```

### Local AI Rule

```text
For Category 2, local AI must mean local model, local processing, and no external API tools.
```

Open WebUI must be configured carefully. If Open WebUI has both local and cloud models enabled, the wrong model selection can still expose data.

Recommended options:

```text
Option A: Separate Open WebUI instance for local-only models
Option B: Separate Open WebUI user/profile with cloud models disabled
Option C: No Open WebUI; use Ollama directly for Category 2
```

---

# 6. Credential Separation

Do not make cloud credentials available inside restricted environments.

## General Environment

May include:

```text
OpenAI API key
Anthropic API key
Gemini API key
Perplexity API access
cloud storage tokens
general automation credentials
```

## Restricted Environment

Should include:

```text
no cloud AI API keys
no cloud storage tokens
no external automation credentials
local model access only
local scripts only
restricted file access
```

### Credential Rule

```text
If a restricted workflow has no cloud AI credentials, it cannot accidentally call cloud AI.
```

---

# 7. LiteLLM Routing Controls

If LiteLLM is added as a model gateway, it should enforce routing by category.

Conceptual policy:

```text
Category 1 requests:
- Allow OpenAI
- Allow Anthropic
- Allow Gemini
- Allow local models

Category 2 requests:
- Allow local Ollama only
- Block OpenAI
- Block Anthropic
- Block Gemini
- Block Perplexity
```

Conceptual routing logic:

```text
if data_category == "category_2":
    allowed_models = ["ollama/local-model"]
    blocked_models = ["openai", "anthropic", "gemini", "perplexity"]
```

### LiteLLM Rule

```text
Route by data category, not just by best model.
```

Limitation:

LiteLLM only enforces workflows that pass through LiteLLM. It does not prevent manual copy/paste into a browser-based AI tool.

---

# 8. n8n Workflow Separation

n8n should be split conceptually into two modes.

## n8n General Mode

Used for Category 1.

May include:

```text
public research
note routing
task reminders
sanitized report workflows
AI prompt chains
tool comparison tracking
project dashboards
cloud APIs
```

## n8n Restricted Mode

Used for Category 2 only if local and controlled.

Should include:

```text
local file processing
local OCR
local report formatting
local metadata extraction
local model calls
encrypted output handling
```

Should not include:

```text
cloud AI credentials
cloud storage upload nodes
public webhook exposure
external sharing nodes
unnecessary logging of sensitive content
```

### n8n Rule

```text
Do not store cloud AI credentials in the restricted n8n environment.
```

Automation should not silently move Category 2 material into cloud tools.

---

# 9. Network Controls

Network controls add friction and reduce accidental exposure.

For restricted environments, consider blocking:

```text
chatgpt.com
claude.ai
gemini.google.com
perplexity.ai
api.openai.com
api.anthropic.com
generativelanguage.googleapis.com
```

Possible methods:

```text
NextDNS denylist profile
local firewall rules
separate VM network rules
restricted Linux user profile
hosts file for simple blocking
router-level rules
```

A stronger setup:

```text
Restricted VM or Linux user
→ no browser logins to cloud AI
→ firewall blocks known AI endpoints
→ only localhost AI tools allowed
```

### Network Rule

```text
Restricted environments should not have easy network access to cloud AI endpoints.
```

---

# 10. File Labeling and Folder Naming

Classification should be visible.

Recommended folder names:

```text
/Class-1-Working/
/Class-2-Restricted/
/Class-2-Do-Not-Upload/
/VeraCrypt/Restricted/
```

Recommended file names:

```text
CLASS2_Project_SourceNotes_2026-05-26.md
CLASS2_Client_Report_Draft_v01.docx
CLASS1_Sanitized_Report_Outline.md
```

Avoid vague names:

```text
stuff.md
new_report.docx
final_final.pdf
notes_copy2.txt
```

For sensitive projects, avoid putting sensitive names in file names if the folder or path may be exposed.

### Labeling Rule

```text
Category 2 files should be visibly marked as restricted.
```

---

# 11. Sanitization Gate

Sometimes cloud AI can help with Category 2-adjacent work, but not with raw Category 2 material.

The safe path is:

```text
Category 2 Raw Material
 ↓
Manual or local sanitization
 ↓
Category 1 Sanitized Summary
 ↓
Cloud AI
```

### Sanitization Should Remove or Generalize

```text
names
addresses
phone numbers
emails
client names
company names
badge details
access control details
facility layouts
IP addresses
hostnames
usernames
credentials
API keys
timestamps if sensitive
photos with identifying details
screenshots with sensitive metadata
legal or investigative identifiers
specific vulnerabilities tied to real entities
```

### Example

Raw Category 2:

```text
Client X facility at 123 Main St has badge reader model ABC123 exposed near the north dock.
```

Sanitized Category 1:

```text
A facility had an exposed access-control reader in a low-visibility area. Draft a professional finding and recommendation.
```

### Sanitization Rule

```text
Only sanitized summaries can move from Category 2 to Category 1.
```

---

# 12. Cloud AI Rules

For ChatGPT, Claude, Gemini, Perplexity, and other cloud AI tools:

```text
Use only for Category 1 or sanitized material.
Do not paste credentials.
Do not upload raw Category 2 files.
Do not paste unredacted client material.
Do not paste restricted screenshots.
Do not paste private logs.
Avoid unnecessary context.
Check whether source documents contain hidden sensitive content before upload.
```

### Cloud AI Rule

```text
Cloud AI is approved for Category 1, not raw Category 2.
```

---

# 13. Local AI Rules

For Open WebUI, Ollama, local models, and related services:

```text
Bind services to localhost unless remote access is required.
Avoid exposing local AI services to the internet.
Use authentication where available.
Keep Docker volumes organized.
Separate test data from sensitive data.
Do not assume local AI is automatically secure.
Control who can access the machine.
Monitor what data is uploaded into the interface.
Disable cloud-connected tools for Category 2 work.
```

### Local AI Rule

```text
Local AI can process Category 2 only when the model, interface, files, and outputs remain local.
```

---

# 14. Secrets Management

Secrets include:

```text
passwords
API keys
private keys
tokens
recovery codes
database credentials
OAuth secrets
SSH keys
encryption keys
client credentials
```

Rules:

```text
Never store secrets in Obsidian.
Never paste secrets into cloud AI.
Never commit secrets to Git.
Never store secrets in plain text scripts.
Use a password manager or dedicated secrets manager.
Use environment variables or protected config files when needed.
Rotate exposed secrets immediately.
```

### Secrets Rule

```text
Secrets are always Category 2 and should never be processed by cloud AI.
```

---

# 15. Document and Report Handling

Reports should follow this rule:

```text
Drafts, source material, final reports, and appendices should remain distinguishable.
```

Recommended handling:

```text
Source material → encrypted storage if Category 2
Normalized notes → Obsidian only if sanitized
Drafts → Obsidian or encrypted storage depending category
Final reports → controlled storage
Appendices → encrypted or controlled storage if Category 2
```

### Report Handling Rule

```text
Do not mix raw Category 2 source material with Category 1 report templates and sanitized notes.
```

---

# 16. Automation Security Rules

For n8n, scripts, APIs, and scheduled workflows:

```text
Use least privilege.
Avoid hardcoded secrets.
Log only what is necessary.
Do not log sensitive content.
Separate test and production workflows.
Use local execution for Category 2 workflows.
Review workflows before enabling automation.
Disable unused credentials.
Document what each automation can access.
Avoid public webhooks for restricted workflows.
```

### Automation Rule

```text
Automation should never silently move Category 2 material into cloud tools.
```

---

# 17. Practical Enforcement Stack

The ecosystem should enforce the policy in layers.

```text
Level 1 — Policy
Define Category 1 and Category 2.

Level 2 — Storage
Category 2 lives in VeraCrypt or encrypted local folders.

Level 3 — Workspace Separation
Category 2 work happens in a restricted local workspace.

Level 4 — Tool Separation
Category 2 uses local-only tools: Ollama, local scripts, local Open WebUI.

Level 5 — Credential Separation
No cloud AI API keys in restricted workflows.

Level 6 — Network Friction
Block cloud AI endpoints from restricted environment when practical.

Level 7 — Sanitization
Only sanitized summaries can move from Category 2 to Category 1.

Level 8 — Review
Before upload, ask: “Is this raw Category 2 or sanitized Category 1?”
```

---

# 18. Recommended Initial Setup

Start with:

```text
1. Normal workspace for Category 1
2. VeraCrypt container for Category 2
3. Separate browser profile for cloud AI
4. Restricted browser profile for local-only tools
5. Local-only AI workspace for Category 2
6. No cloud API keys in restricted workflows
7. Manual sanitization before cloud AI use
```

Add later:

```text
LiteLLM routing rules
restricted n8n instance
NextDNS / firewall blocking
separate Linux user or VM
automated file labeling
local DLP scanning
local OCR and parsing pipeline
```

---

# 19. Incident Response

If Category 2 material is accidentally exposed:

```text
Stop using the affected workflow.
Identify what was exposed.
Identify where it was sent or stored.
Remove local copies if appropriate.
Revoke or rotate exposed credentials if secrets were involved.
Document the incident.
Review whether the workflow needs to change.
Move future processing to a safer compartment.
```

For exposed credentials:

```text
Assume compromise.
Rotate immediately.
Review logs.
Disable old tokens.
Check connected services.
Update scripts or workflows that used the old secret.
```

---

# 20. Review Questions Before Using a Tool

Before using any tool with a file, note, report, or dataset, ask:

```text
What category is this?
Does this tool need the raw data?
Can I sanitize the data?
Can I use a local tool instead?
Where will the output be stored?
Will this create a duplicate copy?
Will this expose metadata?
Does this involve a client, investigation, credential, PII, security data, or private identifier?
Is this raw Category 2 or sanitized Category 1?
```

---

## Final Operating Standard

The ecosystem follows this standard:

```text
Category 1 → privacy-conscious handling; cloud AI allowed when appropriate.
Category 2 → local only, encrypted, or no AI.
```

Supporting enforcement:

```text
storage separation
workspace separation
browser profile separation
local-only AI path
credential separation
network friction
sanitization gate
manual review
```

The strongest rule is:

> Category 2 data should never enter a workspace that has easy access to cloud AI.

This policy should be reviewed as the AI ecosystem matures, especially when new tools, models, APIs, or automation workflows are added.
