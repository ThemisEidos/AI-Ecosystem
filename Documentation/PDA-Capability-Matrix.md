# PDA Capability Matrix and Tool Router Plan

This is a proposal document, not an implementation change. It defines how PDA should choose the right tool for the task based on sensitivity, task type, output type, and automation readiness.

## Design Goals

- Keep Category 2 and restricted-local work local.
- Prefer the smallest tool that can complete the task safely.
- Use cloud-backed tools only for sanitized Category 1 work.
- Route repeatable work to local automation when the output is structured and the failure mode is easy to test.
- Keep Obsidian and PDA memory as the durable system of record for reusable outputs.

## Capability Matrix

| Task type | Sensitivity | Preferred tool | Backup tool | Output location | Automation readiness |
| --- | --- | --- | --- | --- | --- |
| Research | Category 1 | Open WebUI + Gemini via LiteLLM | Perplexity manual search or Fabric research pattern | `04_Resources/Research/`, `05_Reports/Research/` | Assisted |
| Research | Category 2 | Fabric research-synthesis local | Ollama local | `04_Resources/Research/`, `05_Reports/Research/` | Semi-automated |
| Reporting | Category 1 | Fabric report-summary | Open WebUI + Claude via LiteLLM | `05_Reports/` | Semi-automated |
| Reporting | Category 2 | Fabric report-summary local | PowerShell or Python report generator | `05_Reports/` | Automated |
| Learning | Category 1 | NotebookLM package generation | Obsidian notes + Fabric summary | `04_Resources/Learning/`, `08_Prompts/`, `05_Reports/Learning/` | Assisted |
| Learning | Category 2 | Obsidian local synthesis + Fabric summary | Ollama local | `04_Resources/Learning/`, `10_Archive/` | Manual |
| Summarization | Category 1 | Fabric report-summary | Open WebUI + Claude via LiteLLM | `05_Reports/Summaries/` | Automated |
| Summarization | Category 2 | Fabric report-summary local | PowerShell or Python summary helper | `05_Reports/Summaries/` | Automated |
| Review | Category 1 | Fabric review-checklist | Open WebUI + Claude via LiteLLM | `05_Reports/Reviews/` | Semi-automated |
| Review | Category 2 | Fabric review-checklist local | PowerShell or Python checklist helper | `05_Reports/Reviews/` | Automated |
| Security triage | Category 1 | Fabric security-triage | PowerShell or Python static checks | `06_AI-Systems/Security/Reports/` | Local only |
| Security triage | Category 2 | Fabric security-triage local | PowerShell or Python static checks | `06_AI-Systems/Security/Reports/` | Local only |
| Coding | Category 1 | PowerShell or Python local-first | Open WebUI + ChatGPT or Claude for design review only | Repo workspace, `06_AI-Systems/Coding/` | Semi-automated |
| Coding | Category 2 | PowerShell or Python local-only | Ollama local | Repo workspace, `06_AI-Systems/Coding/` | Local only |
| Automation | Category 1 | n8n + PowerShell + Python | Open WebUI + Gemini for workflow design | `06_AI-Systems/Automation/`, `n8n Workflow/` | Semi-automated |
| Automation | Category 2 | n8n + PowerShell + Python local-only | Ollama local | `06_AI-Systems/Automation/`, `n8n Workflow/` | Local only |
| Local-only restricted work | Restricted local | PowerShell + Python + Ollama + Fabric local | Same local tools | Local workspace only | Local only |

## Routing Rules

1. Research:
   - Prefer Gemini through Open WebUI/LiteLLM for Category 1 research synthesis.
   - Prefer Fabric research-synthesis for local or sanitized repeatable work.
   - Never send Category 2 research to cloud-backed tools.

2. Reporting:
   - Prefer Fabric report-summary for repeatable report generation.
   - Use Claude only for sanitized Category 1 drafting when a higher-level summary is needed.
   - Keep report artifacts in `05_Reports/`.

3. Learning:
   - Prefer NotebookLM only for sanitized Category 1 source packages.
   - Keep raw Category 2 learning material local.
   - Feed NotebookLM outputs back into Obsidian capture notes and PDA memory promotion notes.

4. Summarization:
   - Prefer Fabric report-summary for local summaries.
   - Use cloud LLMs only for Category 1 inputs that are explicitly sanitized.

5. Review:
   - Prefer Fabric review-checklist for checklist-style reviews.
   - Use Claude through Open WebUI/LiteLLM only for Category 1 review assistance.

6. Security triage:
   - Prefer Fabric security-triage and local PowerShell/Python checks.
   - Keep all Category 2 and restricted-local security work local.

7. Coding:
   - Prefer local PowerShell/Python edits and validation.
   - Use Open WebUI only for design review or explanation, not for secret-bearing source handling.

8. Automation:
   - Prefer n8n for workflow orchestration.
   - Use PowerShell and Python for local glue, validation, and artifact creation.

9. Local-only restricted work:
   - Use local tools only.
   - Never route to NotebookLM, cloud chat models, or external web APIs.

## Proposed JSON Schema

The future `Scripts/PDA_CapabilityMatrix.json` file should follow this shape:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "PDA Capability Matrix",
  "type": "object",
  "required": ["schema_version", "updated_at", "matrix"],
  "properties": {
    "schema_version": {
      "type": "string"
    },
    "updated_at": {
      "type": "string"
    },
    "matrix": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "task_type",
          "sensitivity_category",
          "preferred_tool",
          "backup_tool",
          "output_location",
          "automation_readiness",
          "cloud_allowed"
        ],
        "properties": {
          "task_type": { "type": "string" },
          "sensitivity_category": { "type": "string" },
          "preferred_tool": { "type": "string" },
          "backup_tool": { "type": "string" },
          "output_location": {
            "type": "array",
            "items": { "type": "string" }
          },
          "automation_readiness": { "type": "string" },
          "cloud_allowed": { "type": "boolean" },
          "route_alias": { "type": "string" },
          "notes": { "type": "string" }
        }
      }
    }
  }
}
```

## Proposed Helper Functions

### `Get-PDAToolForTask`

Suggested signature:

```powershell
function Get-PDAToolForTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$SensitivityCategory,

        [Parameter(Mandatory = $false)]
        [string]$RequestedCommand,

        [Parameter(Mandatory = $false)]
        [string]$SourceSurface,

        [Parameter(Mandatory = $false)]
        [string]$OutputType
    )
}
```

Expected return fields:

- `task_type`
- `sensitivity_category`
- `preferred_tool`
- `backup_tool`
- `route_alias`
- `output_location`
- `automation_readiness`
- `cloud_allowed`
- `reason`

### `Test-PDAToolAllowedForCategory`

Suggested signature:

```powershell
function Test-PDAToolAllowedForCategory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter(Mandatory = $true)]
        [string]$SensitivityCategory,

        [Parameter(Mandatory = $false)]
        [string]$TaskType
    )
}
```

Expected return fields:

- `allowed`
- `reason`
- `cloud_allowed`
- `category_match`

## Commands That Should Use The Router

The router should sit behind any command that selects a tool or model:

- `/research`
- `/report`
- `/review`
- `/draft`
- `/summarize`
- `/fabric research`
- `/fabric report`
- `/fabric review`
- `/fabric security`
- `/notebooklm`
- `/execute`
- build runner task selection when the selected task needs a tool decision
- worker dispatchers that currently choose a model or tool directly

Read-only status commands like `/status`, `/tasks`, `/approvals`, `/workers`, `/reports`, `/memory`, and `/help` should not need the router unless they themselves trigger a tool decision.

## Implementation Roadmap

### Phase 1

- Create the matrix file and loader.
- Add validation tests for category gating and tool selection.
- Keep the router read-only and explainable.

### Phase 2

- Wire `Get-PDAToolForTask` into command interpretation and worker dispatch.
- Add fallback and deny rules for sensitive categories.
- Log routing decisions for later audit.

### Phase 3

- Feed router decisions into the dashboard and operator console.
- Add metrics for tool usage, fallback frequency, and blocked routes.
- Expand the matrix as new tools or patterns are added.

## Recommended Next Step

Create `Scripts/PDA_CapabilityMatrix.json`, add the loader/helper functions, and then wire the router into command interpretation and worker dispatch in a follow-up change.
