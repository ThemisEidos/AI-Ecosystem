---
name: executor-workshop-integration
description: Use when wiring a new executor_type into COOPER's workshops — registry entries, workshop boundaries, and proving it was actually packaged into the image.
---

## When to use
When adding a new `executor_type` to `cooper-core/executor.py` and making it reachable
(or deliberately unreachable) from a workshop. Covers chat-reachable tools and
job-runner-only capabilities alike.

## Procedure

1. **Decide reachability first, because it is a security decision.**
   A chat-reachable tool gets an entry in `Config/general_tool_registry.yaml` and/or
   `Config/private_tool_registry.yaml`. A job-runner-only capability gets NO registry entry
   at all, so no chat model can see or select it — this is how `file_edit`, `web_search`
   and `rss_fetch` are treated. Pin the choice with a test that asserts the executor is
   absent from every registry.

2. **Respect the workshop boundary.** Private is local-only. An executor that reaches the
   internet belongs to Open alone (gate G4). Enforce it in code — `verify_job` compares the
   envelope's declared workshop against the running one — not by hoping a mount is missing.

3. **Ship the assets it reads, and prove it.** This is the step that has failed three times:
   `PDA-Fabric/` was gitignored and never committed (14a), then
   `Config/pii_research_queries.json` (14c) and `Scripts/PDA_RetryPolicy.json` (15f) were
   each missing from the built image. Two layers must both be right — the `COPY` line in
   `cooper-core/Dockerfile` AND `.dockerignore`'s deny-all allowlist.

4. **Verify in the image, not on the dev machine.** Readers of these files fail open by
   design, so a missing asset has no symptom: no error, no warning, a working system, and a
   fully green local suite. Add the file to `_REQUIRED_RUNTIME_FILES` in
   `cooper-core/test_packaging.py` (its drift guard fails the build if you forget) and run:

   ```bash
   docker exec <container> sh -c 'cd /app/cooper-core && python -m pytest -q'
   ```

5. **Verify external endpoints from inside the container too.** A source or endpoint
   reachable from the host can still be blocked in production — CISA's WAF returns 200 to
   the host and 403 to the container for the same URL, same user agent, same minute.
   Anything verified in the wrong environment has not been verified.

6. **Compare counts, not statuses.** Collected-test counts should differ between dev and the
   images only by amounts you can explain. An unexplained delta is a defect or a
   misunderstanding; a green status alone proves only that whatever got collected passed.
