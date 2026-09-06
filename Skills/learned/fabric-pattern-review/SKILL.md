---
name: fabric-pattern-review
description: Use this skill when evaluating technical requirements or task descriptions for clarity, scope, and potential risks.
---

## When to use
This procedure is used to audit a technical requirement or a test case description (e.g., "verifying the fabric pattern writer") to ensure it contains sufficient detail for execution without ambiguity.

## Procedure
1. **Identify Ambiguities**: Check if specific tools, environments, or platforms are clearly named (e.g., replace 'private stack browser' with a specific internal tool name).
2. **Define Scope of Verification**: Identify the specific functional requirements to be tested (e.g., authentication, UI rendering, API connectivity) rather than using broad terms like "verifying."
3. **Identify Environmental Variables**: Note any external factors that required for success (e.g., VPN status, cache clearing).
4. **Establish Success Criteria**: Define clear Pass/Fail criteria or a list of specific outcomes (e.g., "Page loads in <2s").
5. **Add Metadata**: Include timestamps and versioning to track the test session.
