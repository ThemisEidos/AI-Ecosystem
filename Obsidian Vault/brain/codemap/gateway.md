---
title: gateway.py
tags:
  - codemap
loc: 125
---

# gateway.py

COOPER Signal gateway (Step 12).

Part of [[Code Map]] · `cooper-core/gateway.py` · 125 lines

## Classes

- **GatewayConfig** (0 methods) — —

## Functions

- `load_config()` — None unless api_url, number, AND a non-empty allowlist are configured.
- `parse_envelopes()` — (sender, text) for every dataMessage in a /v1/receive payload.
- `is_allowed()` — Fail closed: empty allowlist admits nobody.
- `async send()` — —
- `async poll_once()` — One receive→filter→handle→reply pass. Returns messages handled.
- `async run_loop()` — Poll forever (or max_iterations, for tests). Never raises out.
