# Claude Desktop — Session Context

This file is the entry point for Claude Desktop MCP sessions on the COOPER project.

## How to load context

When starting a COOPER session in Claude Desktop, read these files in order:
1. `PROGRESS.md` — current build step, what runs, what doesn't
2. `brain/North Star.md` — project goals and roadmap
3. `brain/Key Decisions.md` — decision history
4. `brain/Gotchas.md` — known traps and limitations

## Key paths (Windows)
- Repo root: `D:\D_Projects\01_AI_Ecosystem`
- COOPER Core: `D:\D_Projects\01_AI_Ecosystem\cooper-core\`
- Vault: `D:\D_Projects\01_AI_Ecosystem\Obsidian Vault\`
- Config: `D:\D_Projects\01_AI_Ecosystem\Config\`

## What c3 does that Claude Desktop doesn't
- c3 gets SessionStart hook injection automatically (vault context loaded on session open)
- Claude Desktop reads vault on demand via MCP — ask it to "read the vault context" or "check PROGRESS.md"
- Both read from the same files on disk — same ground truth

## MCP servers available in Claude Desktop
- `cooper-vault` → Obsidian Vault/ (brain, memory, knowledge)
- `cooper-repo` → full repo (code, config, docs, PROGRESS.md, CLAUDE.md)
