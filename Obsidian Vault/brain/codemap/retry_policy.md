---
title: retry_policy.py
tags:
  - codemap
loc: 183
---

# retry_policy.py

COOPER's per-stage timeout/retry budgets (Step 15f-ii). Implements

Part of [[Code Map]] · `cooper-core/retry_policy.py` · 183 lines

## Classes

- **Budget** (1 methods) — One stage's execution envelope. `timeout` applies per attempt, so the

## Functions

- `load_policy()` — Read the policy, failing open to an empty dict. Unlike model_routing,
- `_clamp()` — —
- `budget_for()` — Resolve `role`'s budget, filling anything undeclared from the policy's
- `_is_retryable()` — A governance refusal or a malformed request is not worth hammering N
- `async call_with_budget()` — Run `operation` under the budget: `timeout` per attempt, at most
- `async stream_with_budget()` — Bound a streaming response without capping its total length.
