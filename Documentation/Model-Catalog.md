# LiteLLM Model Catalog

This catalog documents the current LiteLLM aliases configured for the AI Ecosystem stack.

Sources used:
- `litellm/litellm_config.yaml` for alias-to-provider/model mapping
- `Scripts/PDA_ModelRouting.json` and `Scripts/Get-PDAModelRoute.ps1` for intended routing use
- Live LiteLLM invocation checks against `http://localhost:4000/v1/chat/completions`

## Summary

| Alias | Provider | Actual model | Verification |
| --- | --- | --- | --- |
| `openai` | OpenAI | `gpt-4o-mini` | Pass |
| `claude` | Anthropic | `claude-sonnet-4-5-20250929` | Pass |
| `gemini` | Gemini | `gemini-2.5-flash` | Pass |
| `gemini-pro` | Gemini | `gemini-2.5-pro` | Pass |
| `openrouter` | OpenRouter | `openai/gpt-4o-mini` | Pass |
| `local-llama` | Ollama | `llama3.2` | Pass |

## Catalog

| Alias | Provider | Actual model | Intended use | Category 1 | Category 2 | Verification | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `openai` | OpenAI | `gpt-4o-mini` | Primary drafting and reporting model through the PDA `gpt` route alias; fallback for review work | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `openai/gpt-4o-mini` |
| `claude` | Anthropic | `claude-sonnet-4-5-20250929` | Primary review model; fallback for drafting/reporting | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `anthropic/claude-sonnet-4-5-20250929` |
| `gemini` | Gemini | `gemini-2.5-flash` | Primary research model | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `gemini/gemini-2.5-flash`, with native LiteLLM fallback to `gemini-pro` |
| `gemini-pro` | Gemini | `gemini-2.5-pro` | Native backup deployment for the `gemini` alias under provider-side high demand or transient failures | Suitable | Not suitable | Pass | Exposed in LiteLLM for router fallback from `gemini` without using OpenRouter |
| `openrouter` | OpenRouter | `openai/gpt-4o-mini` | Research fallback when the Gemini route is unavailable | Suitable | Not suitable | Pass | Configured in LiteLLM as `openrouter/openai/gpt-4o-mini` |
| `local-llama` | Ollama | `llama3.2` | Default local fallback; required route for `restricted_local` and `category_2` tasks | Suitable | Suitable and preferred | Pass | Configured in LiteLLM as `ollama/llama3.2` via Ollama on `http://host.docker.internal:11434` |

## Routing Notes

- `category_2` and `restricted_local` normalize to the local-only route and should remain on `local-llama`.
- Review flows prefer `claude` and fall back to the PDA `gpt` route, which maps to `openai`.
- Drafting and reporting flows prefer the PDA `gpt` route and fall back to `claude`.
- Research flows prefer `gemini` and fall back to `openrouter`.

## Verification Method

Each alias was tested through LiteLLM with a direct `POST` to:

```text
http://localhost:4000/v1/chat/completions
```

The test asked each alias to return a deterministic one-token-style marker. Current results:

- `openai`: success
- `claude`: success
- `gemini`: success
- `openrouter`: success
- `local-llama`: success

## Current Status

The `gemini` alias now resolves to `gemini/gemini-2.5-flash` with a native LiteLLM fallback to `gemini-pro` (`gemini/gemini-2.5-pro`). Direct invocation passes on the primary path, and a forced fallback test confirms LiteLLM can fail over to the native Gemini backup model without using OpenRouter. Research routing remains unchanged.

## Open WebUI Verification

Verified on June 5, 2026 against the running `pda-open-webui` container and its persisted `webui.db`:

- Open WebUI is configured to use the OpenAI-compatible provider list stored in its database, not container env vars.
- The saved Open WebUI provider configuration includes the LiteLLM endpoint at `http://host.docker.internal:4000/v1`.
- An authenticated `GET /api/models` call to Open WebUI returned the curated LiteLLM alias `gemini`.
- The latest Open WebUI chat record titled `Google Maps Trip Planning 🗺️` stores `models: ["gemini"]`.
- That same chat record contains a completed assistant response with `model: "gemini"`, confirming the Open WebUI-facing path successfully used the LiteLLM `gemini` alias end-to-end after the native Gemini fallback change.

Backend verification note:

- A minimal direct `POST /api/chat/completions` probe against Open WebUI returned a local Open WebUI request-shape error (`'NoneType' object has no attribute 'startswith'`) rather than a LiteLLM provider error.
- That probe does not invalidate the verified chat path above, because the persisted Open WebUI chat record shows a successful real chat completion using `gemini`.

## Open WebUI Positioning

This catalog describes the **LiteLLM governed alias layer**, not the full OpenRouter catalog exposed separately in Open WebUI.

- LiteLLM is the stable PDA gateway for curated aliases.
- OpenRouter direct in Open WebUI is intended for exploration and catalog browsing.
- The PDA Chat Bridge remains a separate workflow Pipe and should remain visible alongside model providers.
- Category 2 work must stay on `local-llama` only, regardless of any external catalog availability.
- If the OpenRouter catalog feels too noisy in Open WebUI, prefer caching first and an allowlist or tagged presets second.
