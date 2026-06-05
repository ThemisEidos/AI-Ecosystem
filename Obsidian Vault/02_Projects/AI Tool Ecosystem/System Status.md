# System Status

Updated: 2026-06-05 13:35:14

## AI Ecosystem Status

```text
=========================================
        AI Ecosystem Status Check
=========================================

[OK] Docker engine online.
[OK] Compose file found: C:\Users\earth\Proton Drive\Wjwilbourn\My files\Proton Drive\AI Ecosystem\PDA-Runtime\docker-compose.yml

Containers
NAMES            STATUS                  PORTS
pda-open-webui   Up 2 hours (healthy)    0.0.0.0:3000->8080/tcp, [::]:3000->8080/tcp
pda-litellm      Up 3 hours              0.0.0.0:4000->4000/tcp, [::]:4000->4000/tcp
pda-n8n          Up About an hour        0.0.0.0:5678->5678/tcp, [::]:5678->5678/tcp
bold_feynman     Exited (0) 9 days ago   

Services
[OK] Open WebUI reachable at http://localhost:3000
[OK] LiteLLM reachable at http://localhost:4000/v1/models (HTTP 401)
[OK] n8n reachable at http://localhost:5678
[OK] Ollama reachable at http://localhost:11434/api/tags
[OK] PDA Webhook Server reachable at http://localhost:8788/pda-chat-bridge/healthz
```

## Data Stores

| store | exists | count |
| --- | --- | --- |
| PDA_MemoryIndex.json | True | 2 |
| PDA_ArtifactIndex.json | True | 317 |
| Routing logs | True | 14 |
| Task queue | True | 227 |

## Memory By Category

| name | count |
| --- | --- |
| category_1 | 1 |
| test | 1 |

## Artifacts By Worker

| name | count |
| --- | --- |
| draft-worker | 83 |
| review-worker | 78 |
| research-worker | 64 |
| reporter-worker | 42 |
| findings-worker | 22 |
| timeline-worker | 22 |
| execute-worker | 3 |
| fabric-worker | 1 |
| planner-worker | 1 |
| validation-worker | 1 |
