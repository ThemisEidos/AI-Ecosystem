# NotebookLM Package Template

Updated: 2026-06-06

## TCREI

### Topic

- `{{topic}}`

### Context

- `{{why_this_package_exists}}`

### References

- `{{source_list}}`

### Execution

- `{{notebooklm_notebook_name}}`
- `{{package_version}}`
- `{{package_date}}`

## Package Manifest

```json
{
  "package_name": "{{package_name}}",
  "learning_area": "{{learning_area}}",
  "category": "category_1",
  "sanitized": true,
  "notebooklm_notebook": "{{notebooklm_notebook_name}}",
  "created_at": "{{created_at}}",
  "source_summary": "{{one_sentence_summary}}",
  "source_count": "{{source_count}}",
  "redaction_notes": [
    "{{redaction_note_1}}",
    "{{redaction_note_2}}"
  ],
  "questions": [
    "{{question_1}}",
    "{{question_2}}",
    "{{question_3}}"
  ]
}
```

## Source Files

Place only sanitized, cloud-safe material in this package.

```text
sources/
├── 01-summary.md
├── 02-transcript-sanitized.md
├── 03-notes-sanitized.md
└── 04-references.md
```

## Questions for NotebookLM

- What are the main ideas?
- What patterns repeat across the sources?
- What should I remember later?
- What can be reused in future work?
- What are the gaps or open questions?

## Upload Readiness Check

- [ ] Content is Category 1 or sanitized from Category 2
- [ ] No secrets, credentials, private logs, or sensitive identifiers remain
- [ ] Source list is complete
- [ ] Questions are targeted and useful
- [ ] Output is suitable for cloud upload

## Naming Convention

Use:

```text
<learning-area>-<topic>-<YYYYMMDD>
```

Examples:

- `training-power-bi-fundamentals-20260606`
- `ai-systems-litellm-routing-20260606`
- `research-model-evaluation-20260606`
- `leadership-decision-memos-20260606`

