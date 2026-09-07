---
title: registry.py
tags:
  - codemap
loc: 234
---

# registry.py

COOPER Quartermaster — tool registry reader, OpenAI-schema renderer, and arg

Part of [[Code Map]] · `cooper-core/registry.py` · 234 lines

## Classes

- **RegistryError** (0 methods) — —

## Functions

- `_registry_path()` — —
- `_load()` — —
- `list_tools()` — Return the enabled tool entries for a workshop, as loaded from disk.
- `get_tool()` — Look up a single tool by id within a workshop's registry.
- `format_tool_list()` — Human-readable registry listing, used for direct chat replies.
- `is_registry_query()` — Heuristic: does this message ask what tools/capabilities exist?
- `render_tool_schema()` — One tool entry -> an OpenAI function-calling `tools` array element.
- `render_workshop_tools()` — Every enabled tool for a workshop, rendered as OpenAI tool schemas —
- `validate_args()` — Validate a proposed tool_call's args against tool['parameters'].
