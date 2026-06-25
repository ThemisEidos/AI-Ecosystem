# Workspace Governance Core Live Retrieval Check

## Purpose

Define the manual live Open WebUI grounding check for the existing `AI Ecosystem Governance` Workspace collection.

This protocol exists to validate live retrieval behavior in the Open WebUI chat path.

It does not change collection status by itself.

## Scope

- test only the existing governance collection
- validate live Open WebUI Workspace grounding behavior
- check whether answers stay aligned with approved governance documents
- record whether retrieval appears grounded, partial, or ungrounded

Out of scope:

- creating new collections
- re-importing documents
- changing runtime or Docker behavior
- testing Private Workshop content
- changing repo retrieval status before the manual check is complete

## Collection Under Test

```text
collection_id: workspace_governance_core
collection_name: AI Ecosystem Governance
collection_type: Project Governance
security_category: Category 1
workshop_scope: Open Workshop
import_status: SUCCESS
integrity_status: PASS
retrieval_status: corpus-validated only
```

## Manual Open WebUI Test Procedure

1. Open Open WebUI in the Open Workshop context.
2. Start a fresh chat session.
3. Attach or enable the `AI Ecosystem Governance` Workspace collection.
4. Confirm no other unrelated knowledge collections are attached for the test.
5. Ask each test question exactly as written or with only minor wording changes.
6. Record the response text or a concise summary of the response.
7. Evaluate the response using the grounding indicators and scoring rubric below.
8. Mark the result as `Pass`, `Partial`, or `Fail`.
9. Record any hallucination, missing context, or contradiction with repo governance docs.
10. Stop the check if any response suggests Category 2, Private, Restricted DMZ, `State/`, secrets, logs, or runtime evidence should be uploaded into Workspace.

## Exact Test Questions

Use the following question set:

1. What is the current roadmap phase?
2. What is the current next build action?
3. What is the difference between Open Workshop and Private Workshop?
4. What is the difference between Category 1 and Category 2 handling?
5. What must not be stored in Open WebUI Workspace?
6. What is WF-004 responsible for in evidence and reporting behavior?
7. What is the WF-002 package-folder standard?
8. What is the current status of the Open / Private runtime split?
9. Is Private Open WebUI host-loopback access at `127.0.0.1:3001` complete or deferred?
10. Should new Workspace collections be added now?

## Expected Grounding Indicators

Grounding indicators include:

- the answer clearly reflects approved governance documents already in the Workspace collection
- the answer uses the current repo-aligned phase and policy language
- the answer preserves Open vs Private boundary rules
- the answer preserves Category 1 vs Category 2 rules
- the answer does not invent new approved work
- the answer does not treat model confidence as evidence
- the answer does not treat Workspace as the source of truth over repo docs
- the answer identifies deferred items as deferred rather than complete

Weak grounding indicators include:

- vague but plausible policy language with no clear tie to the governance docs
- mixing old roadmap state with current roadmap state
- recommending new collections, new infrastructure, or new scope without governance support
- claiming Private host-loopback is complete when it is documented as deferred

## Scoring Rubric

### Pass

- answer is materially correct
- answer is clearly grounded in the Workspace governance content
- no meaningful hallucination is present
- no contradiction with current repo governance docs is present
- no prohibited upload or scope recommendation is made

### Partial

- answer is partly correct but incomplete, weakly grounded, or overly generic
- answer may rely on broad model knowledge instead of clearly using the collection
- answer may omit an important constraint or deferred status
- answer does not create a serious governance contradiction

### Fail

- answer is materially incorrect
- answer contradicts current governance docs
- answer invents policy, phase status, or approved work
- answer recommends prohibited content in Workspace
- answer treats deferred items as complete
- answer suggests Category 2 / Private material should be uploaded or tested in Open Workspace

## Result Table Template

| Question | Response summary | Grounding indicators seen | Score | Hallucination present | Missing context | Notes |
|---|---|---|---|---|---|---|
| What is the current roadmap phase? |  |  |  |  |  |  |
| What is the current next build action? |  |  |  |  |  |  |
| What is the difference between Open Workshop and Private Workshop? |  |  |  |  |  |  |
| What is the difference between Category 1 and Category 2 handling? |  |  |  |  |  |  |
| What must not be stored in Open WebUI Workspace? |  |  |  |  |  |  |
| What is WF-004 responsible for in evidence and reporting behavior? |  |  |  |  |  |  |
| What is the WF-002 package-folder standard? |  |  |  |  |  |  |
| What is the current status of the Open / Private runtime split? |  |  |  |  |  |  |
| Is Private Open WebUI host-loopback access at `127.0.0.1:3001` complete or deferred? |  |  |  |  |  |  |
| Should new Workspace collections be added now? |  |  |  |  |  |  |

## Constraints

- do not treat model confidence as grounding
- answers must cite or clearly use Workspace-provided governance content
- repo docs remain the source of truth
- Workspace is a retrieval aid, not the authoritative system of record
- no Category 2 / Private material should be tested or uploaded
- do not use or upload `State/`, runtime evidence, secrets, logs, or Restricted DMZ content
- keep the test inside Category 1 / Open Workshop governance questions only
- do not change collection metadata or retrieval status during this check

## Definition Of Done

This protocol is complete when:

- the manual Open WebUI live retrieval procedure is documented
- the exact governance test question set is documented
- the grounding indicators are documented
- the pass / partial / fail scoring rubric is documented
- the result table template is documented
- the constraints are explicit
- no live retrieval pass/fail claim is made before manual testing
