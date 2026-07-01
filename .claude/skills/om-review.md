---
name: om-review
description: Read the Obsidian brain for session context. Invoke at the start of any COOPER build session to load active patterns, open gotchas, and project direction before touching code.
---

## When to invoke
- At the start of a session before writing or editing code
- When unsure whether a pattern or approach has been tried before
- When a new error looks familiar and might be documented in Gotchas.md

## How to review

Read these files in order. They are optimized for fast scan:

1. `Obsidian Vault/brain/North Star.md` — current step, DoD, what NOT to do
2. `Obsidian Vault/brain/Gotchas.md` — traps to avoid right now
3. `Obsidian Vault/brain/Patterns.md` — confirmed implementation choices
4. `Obsidian Vault/brain/Key Decisions.md` — binding architectural decisions
5. `Obsidian Vault/brain/Skills.md` — what COOPER can already do (don't reimplement)

## Post-review
After reading, state in one sentence:
- Current step and DoD
- Any open gotcha directly relevant to today's task

Then proceed. Do not summarize the entire brain to the user.
