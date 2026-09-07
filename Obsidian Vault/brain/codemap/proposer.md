---
title: proposer.py
tags:
  - codemap
loc: 148
---

# proposer.py

COOPER Proposer — self-improvement loop, draft side (Step 11).

Part of [[Code Map]] · `cooper-core/proposer.py` · 148 lines

## Depends on

- [[decision]]
- [[retry_policy]]
- [[skills]]

## Functions

- `slugify()` — —
- `async _extract_draft()` — —
- `async draft_skill()` — Draft a SKILL.md into Skills/_drafts/<slug>/. Returns the dir, or None
- `offer_line()` — One-line promotion offer appended to the dispatch reply. '' when no draft.
