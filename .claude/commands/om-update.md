---
name: om-update
description: /om-update — update a brain file with a new entry. Usage: /om-update <file> <content>
---

Update `Obsidian Vault/brain/$ARGUMENTS`. 

Steps:
1. Parse $ARGUMENTS: the first word is the target file (without path or extension), the rest is the content to capture.
2. Map to the correct brain file:
   - `decisions` → `Key Decisions.md`
   - `patterns` → `Patterns.md`
   - `gotchas` → `Gotchas.md`
   - `skills` → `Skills.md`
   - `north-star` → `North Star.md`
3. Read the current file, then append a new dated section:
   ```
   ### YYYY-MM-DD · <title derived from content>
   <content>
   ```
4. Confirm the write succeeded.
