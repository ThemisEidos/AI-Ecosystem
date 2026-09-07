---
title: COOPER Brain
tags:
  - hub
aliases:
  - Brain Hub
---

# COOPER Brain

The hub of COOPER's durable memory. Every note here is indexed into `brain_fts`
and surfaced by `archivist.recall()` at runtime — what links from here is what
COOPER can remember.

## Operating memory

- [[North Star]] — current position, what shipped, what's next. The first read
  of every session.
- [[Gotchas]] — every trap found, with the diagnostic trail that ends the
  argument. The most-consulted file in the vault.
- [[Patterns]] — confirmed implementation choices; how things are done here.
- [[Key Decisions]] — owner decisions and their reasoning.
- [[Skills]] — the learned-skill loop: what COOPER has proven it can do.
- [[Claude-Desktop-Context]] — context handed to desktop Claude sessions.

## Structural memory

- [[Code Map]] — the runtime itself, one note per module, wikilinked along
  real import edges. Regenerated from source by `cooper-core/codemap.py`;
  the graph view renders the architecture.

## Conventions

New trap → dated entry in [[Gotchas]] the day it happens. Position change →
[[North Star]] + PROGRESS.md decision log. Undocumented findings die with the
session.
