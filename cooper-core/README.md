# COOPER Core

FastAPI conversational backend for COOPER. Replaces the raw TCP webhook server.
Step 1 of `PRD.md`: COOPER can now hold a conversation.

## Prerequisites

1. Python 3.10+
2. Ollama running on Windows (start the Ollama app or `ollama serve`)
3. The COOPER model built (one-time, from repo root):
   ```
   ollama create COOPER -f Models/cooper-personality/Modelfile
   ```
   If `gemma3:12b` isn't pulled yet: `ollama pull gemma3:12b` first.

## Run

```bash
cd cooper-core
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

`--host 0.0.0.0` is required so Docker containers (Open WebUI) can reach the service via `host.docker.internal`.

## Verify

```bash
# Health check
curl http://localhost:8000/health

# Single-turn chat
curl -s -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "hello, how are you"}' | python3 -m json.tool

# Multi-turn chat (carry history manually)
curl -s -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "what can you help me with?",
    "history": [
      {"role": "user", "content": "hello"},
      {"role": "assistant", "content": "<COOPERs first reply here>"}
    ]
  }' | python3 -m json.tool
```

## Connect to Open WebUI

Open WebUI (running at http://localhost:3000) needs one connection added:

**Via Settings UI (immediate, no restart needed):**
1. Open http://localhost:3000 → click your avatar (top-right) → Settings → Connections
2. Under "OpenAI API", click the `+` button
3. Set URL: `http://host.docker.internal:8000/v1`
4. Set API Key: `cooper-local` (any non-empty value works)
5. Click Save — refresh the page
6. Select `COOPER` from the model dropdown and start chatting

**Via docker-compose (persistent across container restarts):**
See the `OPENAI_API_BASE_URL` block in `PDA-Runtime/docker-compose.yml` — add it to the `open-webui` service and restart the container.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama endpoint |
| `COOPER_MODEL` | `COOPER` | Ollama model name |

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness check |
| POST | `/chat` | Simple `{message, history}` → `{reply}` |
| GET | `/v1/models` | OpenAI-compatible model list |
| POST | `/v1/chat/completions` | OpenAI-compatible streaming chat |
