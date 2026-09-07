---
title: approval.py
tags:
  - codemap
loc: 148
---

# approval.py

COOPER Safety Officer — approval gate for the permission ladder (Step 4).

Part of [[Code Map]] · `cooper-core/approval.py` · 148 lines

## Classes

- **ApprovalTicket** (0 methods) — —
- **ApprovalConflictError** (1 methods) — Raised by request() when a live ticket already occupies this (workshop,

## Functions

- `needs_approval()` — Does this tool halt for approval before running?
- `request()` — Open a pending ticket for this (workshop, session). Refuses to overwrite a
- `_get_live()` — —
- `has_pending()` — —
- `peek()` — Read the session's pending ticket without consuming it (GET /pending).
- `is_response()` — —
- `consume()` — Consume and return this session's live ticket, or None.
- `is_approved()` — —
- `is_denied()` — —
