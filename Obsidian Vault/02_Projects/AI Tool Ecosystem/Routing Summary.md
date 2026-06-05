# Routing Summary

Updated: 2026-06-05 13:26:26

## Summary

| metric | value |
| --- | --- |
| Valid records | 14 |
| Success count | 12 |
| Failure count | 2 |
| Success rate | 85.71% |
| Fallback usage count | 0 |
| Category 1 volume | 8 |
| Category 2 volume | 6 |
| Cloud usage | 8 |
| Local usage | 6 |

## Dispatches By Command

| name | count |
| --- | --- |
| /research | 6 |
| /review | 6 |
| /draft | 2 |

## Dispatches By Model

| name | count |
| --- | --- |
| gemini | 6 |
| local-llama | 6 |
| openai | 2 |

## Dispatches By Worker

| name | count |
| --- | --- |
| research-worker | 6 |
| review-worker | 6 |
| draft-worker | 2 |

## Top Routing Reasons

| name | count |
| --- | --- |
| Research work should prefer Gemini and fall back to OpenRouter if the primary alias fails. | 6 |
| Restricted-local tasks are local-only with no cloud fallback. | 6 |
| Drafting should prefer OpenAI for structured writing and fall back to Claude. | 2 |
