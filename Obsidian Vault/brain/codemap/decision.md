---
title: decision.py
tags:
  - codemap
loc: 410
---

# decision.py

COOPER decision layer — one tool-attached model call per turn (Step 15a).

Part of [[Code Map]] · `cooper-core/decision.py` · 410 lines

## Depends on

- [[retry_policy]]

## Classes

- **TurnDecision** (0 methods) — —
- **ToolCall** (0 methods) — —
- **ModelReply** (0 methods) — —
- **_ToolCallAccumulator** (3 methods) — Accumulates OpenAI-style fragmented tool_call deltas (by `index`,

## Functions

- `_dropped_calls_note()` — —
- `async route_turn()` — —
- `async _stream_ollama_events()` — —
- `async _stream_openai_events()` — —
- `_stream_events()` — —
- `async route_turn_stream()` — —
- `async _stream_and_maybe_dispatch()` — Forwards content deltas in real time as they arrive. Tool_call
- `async _ollama_complete()` — —
- `async _openai_complete()` — —
- `_parse_ollama_tool_calls()` — —
- `_parse_openai_tool_calls()` — —
- `_build_answer_messages()` — —
