---
title: skills.py
tags:
  - codemap
loc: 601
---

# skills.py

COOPER Skills — governed SKILL.md subsystem (Step 10).

Part of [[Code Map]] · `cooper-core/skills.py` · 601 lines

## Depends on

- [[archivist]]
- [[embeddings]]

## Classes

- **SkillError** (0 methods) — —
- **Skill** (0 methods) — —

## Functions

- `parse_skill_md()` — Split SKILL.md into (frontmatter dict, markdown body). Raises SkillError.
- `compute_content_hash()` — SHA-256 over every file in sorted relative-path order (path + contents),
- `load_manifest()` — Read Config/skills_registry.yaml (mtime-cached, matching registry.py's
- `_entry_dir()` — —
- `skill_status()` — Governance check for one manifest entry. Anything but 'ok' means disabled.
- `_load_skill()` — —
- `list_skills()` — All loadable (approved, hash-valid) skills for a workshop.
- `is_skill_query()` — Heuristic: does this message ask what skills exist?
- `select_skill()` — Best keyword-overlap match against name/description. None if no overlap.
- `_min_semantic_sim()` — —
- `async select_skill_semantic()` — Embedding-similarity match against name+description, falling back to
- `format_skill_context()` — System-prompt block for an activated knowledge skill (approved content).
- `skill_context_for()` — The one call main.py makes per turn. '' when nothing matches or on any error.
- `format_skill_list()` — Human-readable catalog including DISABLED entries with their reason.
- `_reject_symlinks()` — Fail closed if any entry under src is a symlink (spec: no symlink dereference
- `_dir_size_bytes()` — —
- `_sweep_stale_staging()` — Remove _incoming/ entries older than the staleness window — orphans left
- `discard_staged()` — Denied import: drop the staged _incoming/<name> dir. False if nothing
- `fetch_tap()` — Clone a tap repo and stage skills/<name>/ under Skills/_incoming/<name>/.
- `preview_import()` — Fetch + stage the skill, return its SKILL.md text for the approval question.
- `register_import()` — Post-approval: promote _incoming/<name> to Skills/imported/<name>, hash it,
- `_draft_dir()` — —
- `preview_promote()` — SKILL.md text for the approval question — from the draft, or (fallback,
- `register_promotion()` — Post-approval: move the draft to Skills/learned/<name>, hash, register.
- `_append_manifest_entry()` — —
- `record_activation()` — Count one knowledge-skill activation. Non-fatal on any error.
- `get_activation_count()` — —
