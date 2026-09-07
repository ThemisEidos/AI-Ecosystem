---
title: review.py
tags:
  - codemap
loc: 131
---

# review.py

COOPER Reviewer — sub-agent review loop (Step 7).

Part of [[Code Map]] · `cooper-core/review.py` · 131 lines

## Depends on

- [[decision]]
- [[retry_policy]]

## Classes

- **ReviewVerdict** (0 methods) — —

## Functions

- `async review()` — Reviewer: ask the model to check the worker's output. Fails open (pass).
- `govern()` — Governor: decide what the user sees based on the reviewer's verdict.
