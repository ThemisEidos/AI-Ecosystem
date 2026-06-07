# NotebookLM Package Generator Usage

Updated: 2026-06-06

## Purpose

Use `Scripts/New-PDANotebookLMPackage.ps1` to build a NotebookLM-ready package from sanitized Obsidian notes.

## Example

```powershell
pwsh -NoProfile -File .\Scripts\New-PDANotebookLMPackage.ps1 `
  -LearningArea "Research" `
  -Topic "LLM Evaluation Notes" `
  -SourcePaths @(
    ".\Obsidian Vault\02_Projects\AI Tool Ecosystem\Research\llm-eval-sanitized.md",
    ".\Obsidian Vault\02_Projects\AI Tool Ecosystem\Research\reading-summary-sanitized.md"
  ) `
  -Summary "Sanitized research package for NotebookLM." `
  -Questions @(
    "What are the key takeaways?",
    "What methods were repeated?",
    "What follow-up questions should I ask?"
  )
```

## Output

The script creates a package under:

```text
PDA-Backups/notebooklm/<learning-area>/<topic>/<topic>-<timestamp>/
```

Package contents:

```text
sources/
manifest.json
summary.md
questions.md
```

## Safety Rules

- Only upload sanitized Category 1 material.
- Never upload raw Category 2 material.
- If the content is flagged as restricted or contains secret-like material, the script stops.
- If a source note lacks an explicit category marker, the script uses a conservative content scan and path check, then records that in the manifest.

