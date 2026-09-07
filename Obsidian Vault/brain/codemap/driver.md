---
title: driver.py
tags:
  - codemap
loc: 120
---

# driver.py

Runtime driver selection — any LLM can drive COOPER-Open.

Part of [[Code Map]] · `cooper-core/driver.py` · 120 lines

## Depends on

- [[archivist]]
- [[model_routing]]

## Classes

- **DriverError** (0 methods) — —

## Functions

- `_ensure_table()` — —
- `_aliases()` — Locally-routable names: the roster aliases plus the default pool.
- `_fetch_catalog_ids()` — —
- `catalog()` — Cached OpenRouter model list for the dropdown (id strings, sorted).
- `current()` — The model currently driving COOPER-Open.
- `set_driver()` — Validate and persist a new driver. Raises DriverError on anything
