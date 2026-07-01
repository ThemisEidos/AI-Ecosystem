---
name: om-search
description: /om-search — search the COOPER brain for a keyword or topic. Usage: /om-search <term>
---

Search the brain for `$ARGUMENTS`:

```bash
grep -ri "$ARGUMENTS" "Obsidian Vault/brain/" --include="*.md"
```

If results are found, read the matching files and summarize relevant entries. If no results, say so — don't guess.
