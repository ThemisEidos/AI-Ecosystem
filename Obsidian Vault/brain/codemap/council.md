---
title: council.py
tags:
  - codemap
loc: 254
---

# council.py

COOPER Council -- multi-model deliberation subsystem (Step 15d).

Part of [[Code Map]] · `cooper-core/council.py` · 254 lines

## Depends on

- [[decision]]
- [[model_routing]]
- [[retry_policy]]
- [[review]]

## Classes

- **CouncilVerdict** (0 methods) — —

## Functions

- `_disambiguate_labels()` — Labels for CouncilVerdict.member, one per roster position. A roster
- `async _member_verdict()` — One council member's JSON-schema-constrained verdict call. Fails open
- `async critique_envelope()` — Planning-time critique: every roster member independently reviews the
- `has_objection()` — True if any member flagged. Dissent is never outvoted -- one flag is
- `needs_council_tier()` — Final review is council-tier if the job is L4+ or writes files;
- `verdicts_to_dicts()` — —
- `async final_review()` — Tiered final review over a job run's output. Council tier for L4+ /
