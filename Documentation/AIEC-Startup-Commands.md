# AI Ecosystem Startup Commands

## Commands

- `aiec-start`
  Starts Docker Desktop if needed, waits for the Docker engine, starts the AI Ecosystem stack with `docker compose`, falls back to `docker start` when compose cannot be used, waits for service readiness, starts the host-side PDA webhook server, and prints troubleshooting details for failures.
- `aiec-status`
  Prints Docker status, container state, service reachability, PDA webhook server reachability on port `8788`, compose-file detection, and targeted troubleshooting for unhealthy services.
- `Scripts\Test-PDAStack.ps1`
  Runs the fast PDA stack reachability check. Add `-Deep` or `-ValidateOpenWebUIChat` to include the slower Open WebUI chat-completion validation against `gemini`.
- `pda-dashboard`
  Refreshes the Obsidian PDA dashboard notes and opens `Obsidian Vault\02_Projects\AI Tool Ecosystem\PDA Operator Console.md`. It does not start Docker or require Open WebUI/n8n to be open.
- `pda-console`
  Compatibility alias for `pda-dashboard`.
- `pda`
  Compatibility wrapper for `aiec-start`.
- `pda-status`
  Compatibility wrapper for `aiec-status`.
- `pdadown`
  Stops the compose stack from `PDA-Runtime`.
- `aiec`
  Changes the shell location to the repo root.

## Expected Services

- Open WebUI: `http://localhost:3000`
- LiteLLM: `http://localhost:4000`
- n8n: `http://localhost:5678`
- Ollama: optional, checked at `http://localhost:11434/api/tags`
- PDA Webhook Server: `http://localhost:8788/pda-chat-bridge`
- PDA Webhook Health: `http://localhost:8788/pda-chat-bridge/healthz`

## Notes

- The startup flow uses the checked-in compose file at `PDA-Runtime\docker-compose.yml`.
- The PDA webhook server is a host PowerShell process, not a Docker container. `aiec-start` starts it after the required Docker services are healthy and avoids launching a duplicate when port `8788` is already in use.
- If a required service fails, the command reports whether the compose file exists, whether the container exists, whether it is running, recent redacted logs, and whether another process is already listening on the target port.
- If the PDA webhook server fails, the command reports whether the script exists, whether port `8788` already has a listener, probe errors against `http://localhost:8788/pda-chat-bridge`, and recent redacted server logs.
- The profile installer is `setup-pda-profile.ps1`. Run it if the shell profile needs to be rebuilt.
- `pda-dashboard` prefers opening the dashboard via Obsidian when the app or protocol handler is installed. If that fails, it falls back to the default editor for `.md` files.
- Legacy duplicate containers named `open-webui` and `litellm` were removed so the compose-managed `pda-open-webui` and `pda-litellm` containers now own host ports `3000` and `4000`.
- `aiec-status` treats LiteLLM `HTTP 401` on `/v1/models` as reachable because that endpoint can require authentication even when the service is healthy.
- `Scripts\Test-PDAStack.ps1` stays fast by default. The Open WebUI chat-completion probe is opt-in because it performs a real authenticated completion through Open WebUI and LiteLLM.
- The n8n PDA HTTP bridge workflow should be imported from `n8n Workflow/PDA-ChatBridge-HTTP.json`. The current export is fail-closed and returns explicit JSON if the local bridge server is offline instead of an empty `{}` response.
