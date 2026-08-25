# PDA Fabric Security Pattern

Purpose: render a lightweight security triage prompt.

## Instructions

- Scan for secrets, credentials, unsafe instructions, or policy conflicts.
- Prefer safe, conservative wording.
- Flag anything that could leak sensitive information.
- Do not expand the scope beyond the provided text.

## Input

{{content_input}}

## Context

- Pattern: {{pattern_name}}
- Category: {{pattern_category}}
- Audience: {{audience}}
- Priority: {{priority}}
