---
title: Code Map
tags:
  - codemap
---

# Code Map

COOPER's runtime, one note per module, wikilinked along real import
edges. Regenerate after a refactor: `cd cooper-core && .venv/bin/python codemap.py`.
Part of [[COOPER Brain]].

## Modules

- [[jobs]] — COOPER Jobs — envelope loading, hash verification, exception queue (Step 14b). (1329 loc, imported by 1)
- [[executor]] — COOPER Workbench — execution gateway (Step 5). (1228 loc, imported by 2)
- [[main]] — COOPER Core — FastAPI conversational runtime. (1157 loc, imported by 0)
- [[skills]] — COOPER Skills — governed SKILL.md subsystem (Step 10). (601 loc, imported by 3)
- [[archivist]] — COOPER Archivist — memory + skill loop (Step 8). (410 loc, imported by 4)
- [[decision]] — COOPER decision layer — one tool-attached model call per turn (Step 15a). (410 loc, imported by 7)
- [[evidence]] — Workflow-evidence validation (Tests/Fixtures/Workflow_Evidence rule set). (281 loc, imported by 0)
- [[council]] — COOPER Council -- multi-model deliberation subsystem (Step 15d). (254 loc, imported by 2)
- [[registry]] — COOPER Quartermaster — tool registry reader, OpenAI-schema renderer, and arg (234 loc, imported by 2)
- [[retry_policy]] — COOPER's per-stage timeout/retry budgets (Step 15f-ii). Implements (183 loc, imported by 7)
- [[approval]] — COOPER Safety Officer — approval gate for the permission ladder (Step 4). (148 loc, imported by 1)
- [[proposer]] — COOPER Proposer — self-improvement loop, draft side (Step 11). (148 loc, imported by 1)
- [[codemap]] — Code map generator — COOPER's structural self-knowledge (2026-09-07). (144 loc, imported by 0)
- [[review]] — COOPER Reviewer — sub-agent review loop (Step 7). (131 loc, imported by 2)
- [[gateway]] — COOPER Signal gateway (Step 12). (125 loc, imported by 1)
- [[driver]] — Runtime driver selection — any LLM can drive COOPER-Open. (120 loc, imported by 1)
- [[embeddings]] — Embedding helpers for semantic selection (skills, and anything after them). (105 loc, imported by 2)
- [[workshop]] — COOPER Workshop enforcer — Step 6. (86 loc, imported by 1)
- [[pairing]] — Device pairing for the Cockpit (Step 15i). (80 loc, imported by 1)
- [[model_routing]] — COOPER's per-role model routing map (Step 15c). Implements (68 loc, imported by 4)
