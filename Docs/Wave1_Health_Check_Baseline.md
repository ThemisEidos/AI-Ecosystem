# Wave 1 Health Check Baseline

## Purpose

Define the minimum Wave 1 health-check baseline for Open and Private ecosystem services before any runtime split implementation is approved.

## Open Ecosystem Health Checks

Required checks for Open services:

- service reachable on expected local endpoint
- service returns expected health or ready signal where available
- dependent local route is reachable where applicable
- failure state is visible in logs

## Private Ecosystem Health Checks

Required checks for Private services:

- service reachable on expected local endpoint
- service operates without cloud fallback
- service failure is visible locally
- service remains bounded to Private-local dependencies

## Minimum Service List

### Open WebUI

- confirm UI process is reachable
- confirm expected local endpoint responds
- confirm logs show startup success or explicit failure

### LiteLLM

- confirm router endpoint is reachable where applicable
- confirm model-routing service starts cleanly
- confirm failure state is visible in logs

### n8n

- confirm automation service is reachable where applicable
- confirm configured workflow entry surfaces are available
- confirm startup and error states are visible in logs

### Ollama / Local Model Runtime

- confirm local model runtime is reachable where applicable
- confirm local inference path is available
- confirm failures are surfaced locally

### Workflow Gateway / Webhooks

- confirm expected local webhook or gateway endpoint is reachable where applicable
- confirm unavailable gateway states are explicit
- confirm logs identify timeout or routing failure conditions

## Health Check Output Expectations

Health checks should produce concise output showing:

- service name
- target endpoint or local surface
- pass or fail state
- short failure reason when failing
- timestamp of the check

## Logging Expectations

Logs should make the following visible:

- startup success
- bind failure
- route failure
- timeout condition
- downstream dependency failure

Wave 1 does not require centralized log aggregation.

## Relationship to Future Observability Work

This baseline is a prerequisite for later observability work.

Wave 1 health checks establish minimum visibility only.
Richer observability belongs to later Open-focused planning and approved implementation work.

## Non-Goal

No dashboard implementation is approved in Wave 1.

## Implemented Health Commands

Open:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAOpenStackHealth.ps1
```

Private:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Test-PDAPrivateStackHealth.ps1 -ValidateWF007
```

## Current Runtime Notes

- Open health remains HTTP-based for Open WebUI, LiteLLM, n8n, and the webhook bridge surface
- Private health uses separate local endpoints for Private Open WebUI and Private Ollama
- Private Open WebUI must point only to `http://private-ollama:11434`
- WF-007 readiness remains validated through the existing workflow test rather than a new workflow implementation
- Private Open WebUI health passes through container-local and validation-script checks even when host-loopback browser access is unavailable
- Private Ollama remains private-only and is not exposed to the host
- host-loopback UI access at `127.0.0.1:3001` is a deferred runtime limitation and is not currently treated as a Wave 1 validation blocker

## Logging Notes

- Open container logs remain available through Docker logs for `pda-open-webui`, `pda-litellm`, and `pda-n8n`
- Private container logs remain available through Docker logs for `pda-private-open-webui` and `pda-private-ollama`

## Related Documents

- [Wave1_Open_Private_Split_Plan.md](../Docs/Wave1_Open_Private_Split_Plan.md)
- [07_Implementation Roadmap.md](../07_Implementation%20Roadmap.md)
