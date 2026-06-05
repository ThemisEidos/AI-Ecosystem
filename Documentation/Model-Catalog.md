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
| `openrouter` | OpenRouter | `openai/gpt-4o-mini` | Pass |
| `local-llama` | Ollama | `llama3.2` | Pass |

## Catalog

| Alias | Provider | Actual model | Intended use | Category 1 | Category 2 | Verification | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `openai` | OpenAI | `gpt-4o-mini` | Primary drafting and reporting model through the PDA `gpt` route alias; fallback for review work | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `openai/gpt-4o-mini` |
| `claude` | Anthropic | `claude-sonnet-4-5-20250929` | Primary review model; fallback for drafting/reporting | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `anthropic/claude-sonnet-4-5-20250929` |
| `gemini` | Gemini | `gemini-2.5-flash` | Primary research model | Suitable | Not suitable | Pass | Configured directly in LiteLLM as `gemini/gemini-2.5-flash` |
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

The `gemini` alias now resolves to `gemini/gemini-2.5-flash` and passes live invocation through LiteLLM. Research routing remains unchanged.
