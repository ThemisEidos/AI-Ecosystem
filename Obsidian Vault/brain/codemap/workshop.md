---
title: workshop.py
tags:
  - codemap
loc: 86
---

# workshop.py

COOPER Workshop enforcer — Step 6.

Part of [[Code Map]] · `cooper-core/workshop.py` · 86 lines

## Classes

- **WorkshopViolation** (0 methods) — Raised when a request violates the active workshop boundary.

## Functions

- `check_tool()` — Raise WorkshopViolation if this tool is not allowed in active_workshop.
- `check_backend()` — Raise WorkshopViolation if the resolved backend would send data to the cloud
