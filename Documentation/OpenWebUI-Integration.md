# Open WebUI Integration

This document defines the Open WebUI chat path for the PDA Chat Bridge.

## Dual-Provider Model Access

Open WebUI now serves two distinct model access patterns:

- **LiteLLM** is the governed PDA gateway. It exposes the curated PDA aliases used for approved workflow routing and stable day-to-day use.
- **OpenRouter direct** is connected separately as an OpenAI-compatible provider for exploration and broad model catalog browsing.
- **PDA Chat Bridge** remains a preserved Pipe Function workflow and is not replaced by either provider connection.

### Current Model Sources

- **LiteLLM governed gateway**: `http://host.docker.internal:4000/v1`
  - Curated aliases: `local-llama`, `openai`, `claude`, `gemini`, `openrouter`
- **OpenRouter Catalog**: `https://openrouter.ai/api/v1`
  - Large external catalog for discovery and ad hoc use
- **PDA Chat Bridge**: preserved as the `PDA Chat Bridge` Pipe Function in Open WebUI

### Governance Notes

- Category 2 and `restricted_local` work must remain on `local-llama` only.
- Do not treat the OpenRouter catalog as the governed default path for PDA automation.
- LiteLLM remains the approved control point for curated aliases, auth, and future routing policy.
- The OpenRouter catalog can be noisy and crowded in the model selector. Enable model-list caching and consider a later allowlist if the UI becomes difficult to use.

## Architecture

```mermaid
flowchart TD
    A[Open WebUI Pipe Function] --> B[n8n production webhook]
    B --> C[Local PDA webhook bridge]
    C --> D[PDA command interpreter]
    D --> E[Governed submitter]
    E --> F[Approval gate]
    F --> G[Queue / staging / results]
```

## Contract

- Open WebUI calls the n8n production webhook through a Pipe Function.
- The Pipe sends `user_message` and `confirm_dispatch` to `http://localhost:5678/webhook/pda-chat-bridge-http`.
- The n8n workflow forwards the request to `http://host.docker.internal:8788/pda-chat-bridge`.
- The local PowerShell bridge returns machine-readable JSON with recommendation and dispatch status.
- No direct queue access is allowed from Open WebUI, n8n, or the webhook layer.
- The bridge server binds to local interfaces on port `8788` so Docker can reach it through the host gateway.

## Recommended Open WebUI Method

Use a **Pipe Function**.

- Pipes are first-class selectable models in the Open WebUI chat sidebar.
- Pipes control the full request/response cycle, which fits the PDA's two-step confirmation flow.
- Tools are designed for model-invoked API calls during inference, not for a user-facing chat model wrapper.
- Pipelines are better reserved for heavier or externalized processing.
- Actions are useful later if you want a button-based confirmation shortcut, but they are not required for the base chat flow.

## Deployment Instructions

1. Place the repository on the same host where n8n can execute `pwsh`.
2. Ensure `Scripts/Invoke-PDAWebhookBridge.ps1` is reachable from the n8n runtime path.
3. Import and activate `n8n Workflow/PDA-ChatBridge-HTTP.json` in n8n.
4. Run `Scripts/Start-PDAWebhookServer.ps1` on the host machine before testing the HTTP workflow.
5. In Open WebUI, create a Pipe Function from [Open WebUI/PDA_ChatBridge_Pipe.py](C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Open WebUI\PDA_ChatBridge_Pipe.py).
6. Set the Pipe Function's `N8N_WEBHOOK_URL` valve to `http://host.docker.internal:5678/webhook/pda-chat-bridge-http` if Open WebUI runs in Docker, or `http://localhost:5678/webhook/pda-chat-bridge-http` if it runs on the host.
7. Enable the Pipe Function and select it as the active model in the chat sidebar.
8. Confirm that the Open WebUI model points to the PDA Pipe, not to queue files or workers.

## Configuration Instructions

- The Pipe Function sends the first pass with `confirm_dispatch = false`.
- The Pipe Function only replays with `confirm_dispatch = true` after explicit user approval in the chat.
- Keep the `confirm_dispatch` valve path disabled on first-pass recommendations.
- Do not bypass the bridge by calling submitters, queue workers, or workers directly.
- The Pipe Function stores pending confirmation state locally so the second message can replay the governed dispatch.

## Webhook Flow

1. Open WebUI Pipe sends `{ "user_message": "...", "confirm_dispatch": false }` to the n8n production webhook.
2. n8n normalizes the request into `user_message` and `confirm_dispatch`.
3. n8n sends an HTTP request to `http://host.docker.internal:8788/pda-chat-bridge`.
4. `Scripts/Start-PDAWebhookServer.ps1` receives the request locally on port `8788`.
5. The server invokes `Scripts/Invoke-PDAWebhookBridge.ps1 -Message "<text>" -AsJson`.
6. The webhook bridge invokes `Scripts/Invoke-PDAChatBridge.ps1`.
7. The bridge resolves the request against `Scripts/PDA_TaskOntology.json`.
8. If the request is mapped and confirmed, the governed submitter is called.
9. n8n returns the JSON response to Open WebUI.

## Confirmation Flow

- If the interpreter returns `mapped`, the bridge sets `requires_confirmation` to `true` until `confirm_dispatch` is supplied.
- If the result is `ambiguous` or `unknown`, no dispatch is allowed.
- The Pipe Function records the pending request and waits for an explicit user approval phrase before replaying with `confirm_dispatch: true`.
- Confirmation does not bypass ontology, approval, or category controls.

## Troubleshooting

- If the bridge returns invalid JSON, verify that `pwsh` is installed and the script path is correct.
- If the HTTP bridge workflow cannot reach the server, confirm `Scripts/Start-PDAWebhookServer.ps1` is running on port `8788`.
- If Docker-to-host calls hang, run `Scripts/Test-PDAWebhookServerReachability.ps1` and verify `host.docker.internal` returns HTTP 200 from inside the `pda-n8n` container.
- If dispatch never happens, confirm that the interpreted request maps to a governed command and that the worker eligibility check passes.
- If Category 2 requests are routed externally, stop and validate the ontology and worker registry immediately.
- If the n8n workflow cannot parse the bridge output, run `Scripts/Invoke-PDAWebhookBridge.ps1 -Message "review my latest findings" -AsJson` locally and inspect the JSON.
- If a confirmation appears to be ignored, verify that the request was mapped and that `confirm_dispatch` was sent as a real boolean-like value.
- If Open WebUI loses pending confirmation state after restart, reissue the initial prompt so the Pipe can rebuild the pending entry.

## Recommended Usage

- First call: `confirm_dispatch = false`
- Second call only after explicit user confirmation: `confirm_dispatch = true`
- The bridge remains the source of truth for command recommendation and dispatch readiness.

## Clipboard Import

- Use [`n8n Workflow/PDA-ChatBridge-HTTP-Clipboard.json`](C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\n8n%20Workflow\PDA-ChatBridge-HTTP-Clipboard.json) when pasting directly into the n8n canvas.
- If the n8n import dialog creates no nodes, paste the clipboard JSON into the canvas instead of using file import.
- The clipboard workflow is intentionally minimal: nodes plus connections only.
- The HTTP bridge server must be running on `http://localhost:8788/pda-chat-bridge` before testing the pasted workflow, and the n8n HTTP Request node should target `http://host.docker.internal:8788/pda-chat-bridge`.

## Open WebUI Setup

1. In Open WebUI, open `Admin Panel -> Functions`.
2. Click `Create` and choose a new Function ID such as `pda_chat_bridge`.
3. Paste the contents of [Open WebUI/PDA_ChatBridge_Pipe.py](C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\Open WebUI\PDA_ChatBridge_Pipe.py).
4. Save the function.
5. Open the function settings and set `N8N_WEBHOOK_URL`.
6. Enable the function.
7. Select `PDA Chat Bridge` from the chat model picker.
8. Send an initial message. The function will query the n8n webhook with `confirm_dispatch: false`.
9. Reply with an explicit approval phrase such as `confirm dispatch`. The function will replay the same request with `confirm_dispatch: true`.

## Provider Setup

1. Keep the LiteLLM OpenAI-compatible connection enabled at `http://host.docker.internal:4000/v1`.
2. Use LiteLLM as the source for governed PDA aliases and normal curated model access.
3. Add a second OpenAI-compatible connection for OpenRouter at `https://openrouter.ai/api/v1`.
4. Use bearer auth with the OpenRouter API key.
5. Leave the model filter blank only if you want the full catalog visible.
6. Enable `Cache Base Model List` in Open WebUI to reduce repeated provider list fetches.
7. If the selector becomes too noisy, add an allowlist or create Open WebUI model presets and tags for the few OpenRouter models you actually want exposed.

## Notes

- The Pipe Function is the primary integration path.
- An Action Function can be added later if you want a button-driven confirmation step, but it is not required for the working chat flow.
- The integration assumes the Open WebUI container can reach the host via `host.docker.internal`, which matches the documented Docker setup.
- The dual-provider setup is intentional: LiteLLM for governance, OpenRouter direct for exploration, PDA Chat Bridge for workflow dispatch.
