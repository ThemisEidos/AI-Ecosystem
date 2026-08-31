# PDA Model Routing

> **Superseded 2026-08-30 (Step 15c):** `Scripts/PDA_ModelRouting.json` was rewritten
> for cooper-core's role→alias routing map; the `command_routes`/`category_routes`
> schema this document describes no longer exists in that file. This document is
> retained for historical reference to the retired v1 PowerShell router only.

This document defines PDA Governance & Model Routing v1.

## Goal

The routing layer selects the approved LiteLLM alias for each governed PDA command and enforces local-only handling for sensitive work.

## Source Of Truth

- Policy file: `Scripts/PDA_ModelRouting.json`
- Loader/helper: `Scripts/Get-PDAModelRoute.ps1`
- Invocation adapter: `Scripts/Invoke-PDAModel.ps1`

## Routing Table

| Command / Category | Primary | Fallback | Cloud Allowed | Reason |
| --- | --- | --- | --- | --- |
| `/research` `category_1` | `gemini` | `openrouter` | `true` | Prefer Gemini for research synthesis and fall back to OpenRouter if needed. |
| `/review` `category_1` | `claude` | `openai` | `true` | Prefer Claude for critique quality and fall back to OpenAI. |
| `/draft` `category_1` | `openai` | `claude` | `true` | Prefer OpenAI for structured drafting and fall back to Claude. |
| `/execute` `category_1` | `local-llama` | none | `false` | Execution planning remains local-only. |
| `category_2` | `local-llama` | none | `false` | Category 2 is local-only with no cloud fallback. |
| `restricted_local` | `local-llama` | none | `false` | Restricted-local work is local-only with no cloud fallback. |

## Enforcement Rules

- Category 2 can never use cloud aliases.
- `restricted_local` can never use cloud aliases.
- `/execute` is local-only even for `category_1`.
- Missing or unknown routes fail closed instead of falling back silently.
- LiteLLM remains the routing gateway. This layer does not change provider credentials or aliases.

## Output Fields

The route helper and invocation adapter include these routing fields:

- `command`
- `category`
- `selected_model`
- `fallback_chain`
- `routing_reason`
- `cloud_allowed`

Additional adapter metadata includes `primary_model`, `transport_model`, `route_source`, and `model_candidates`.

## Routing Audit Logs

Every governed PDA model dispatch writes a JSON audit record to `PDA-Logs/routing/`.

Each record includes:

- `command`
- `category`
- `selected_model`
- `fallback_chain`
- `routing_reason`
- `worker`
- `timestamp`
- `outcome`

Use these logs for explainability, governance review, performance tuning, and later self-optimization work. The invocation adapter also returns the written file path as `routing_audit_log` in its JSON output.

## Worker Integration

The governed routing layer is currently wired into:

- `Scripts/Invoke-PDAResearchWorker.ps1`
- `Scripts/Invoke-PDAReviewWorker.ps1`
- `Scripts/Invoke-PDADraftWorker.ps1`
- `Scripts/Invoke-PDAExecuteWorker.ps1`

Each worker passes command and category context into `Scripts/Invoke-PDAModel.ps1` instead of selecting models directly.

## Validation

- Run `Scripts/Test-PDAModelRouting.ps1` for policy validation.
- Run `Scripts/Test-PDALiteLLMProviders.ps1` for alias/provider validation.
- Run `aiec-status` before policy testing so the local stack is known-good.

## Safety Notes

- Do not enable any cloud fallback for `category_2`.
- Do not bypass the adapter from worker scripts.
- Do not change LiteLLM alias definitions to satisfy routing. Change the routing policy instead.
