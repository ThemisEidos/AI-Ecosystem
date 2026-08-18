# Step 15 — Max-Metric Program: metric closure × planner–executor × council

**Date:** 2026-08-18
**Status:** Approved direction (owner, 2026-08-18) — the program, priorities, and
execution order are set; governance gates G1–G5 remain individually open and each
blocks only its named slice
**Branch context:** all work on `main`
**Relationship to Step 14:** absorbs and re-orders the approved Step 14 slices
(spec 2026-08-04); 14a–14f keep their names, new work is lettered 15a–15h.
The written 14a plan (`plans/2026-08-04-step-14a-fabric-executor.md`) is built on
the classifier-dispatch architecture that 15a replaces — it gets a light revision
after 15a lands, not a rewrite (the executor handler itself carries over).

---

## 1. Decision record

### Goal (owner, 2026-08-18)

COOPER-Open maxes all nine harness metrics; COOPER-Private maxes every metric
physically reachable on the 6GB-VRAM host. Success is comparative as well as
absolute: **outperform other agentic harnesses — specifically Hermes Agent (29/45,
mirror-image profile) — on every metric**, without taking Hermes's trade (spending
governance for autonomy). A running version stays operational throughout: every
slice ships alone and live on the existing stacks, Step 14 discipline. Merged into the goal, by owner
direction the same day:

- **Planner–executor split** — a big-brain model drafts each job's plan,
  workflow, and per-step instructions once; a cheap executor model runs the
  steps inside it. The plan and the Step 14 job envelope are the same object:
  big brain drafts the envelope → council critiques → owner approves → hash
  pinned → executor runs within it.
- **Council system** — multi-model deliberation at planning time and at final
  review. Owner accepted the pushback that mid-run deviation prevention stays
  deterministic (envelope hash + quotas + exception queue, enforced in code);
  councils judge quality, mechanisms enforce bounds. Optional mid-run oversight
  is a single fast-model checkpoint that can only halt into the exception
  queue, never approve-forward.

### The nine metrics (defined 2026-08-18 session; each 0–5, evidence-scored)

| # | Metric | COOPER today | Operational test |
|---|---|---|---|
| M1 | Tool reach | 3 | fraction of registered tools reachable by natural language × breadth |
| M2 | Autonomy horizon | 1 | longest governed chain without a human turn |
| M3 | Tool-call fidelity | 2 | regex → classifier → native function-calling w/ schema validation |
| M4 | Governance | **5** | forbidden action at every tier is blocked AND logged; fail-closed |
| M5 | Memory & learning | 4 | repeated tasks improve; learning itself is gated |
| M6 | Verification | 4 | injected failure is caught by an independent reviewer |
| M7 | Audit | **5** | any past action reconstructable from stored state alone |
| M8 | Robustness | 4 | safe + honest degradation under timeout / backend death / malicious input |
| M9 | Portability | 4 | fresh machine → running, count of manual steps |

Standing constraint: **no slice may spend M4 or M7 to buy another metric.**
That trade is Hermes's profile; declining it is this platform's identity.

### Key research findings this spec relies on (verified 2026-08-18)

- **gemma4 has native tool calling in every variant** (Google, Apr 2026;
  Ollama `tools` param, ~86% claimed accuracy). COOPER-Private's served model
  already supports it — **no model swap needed for 15a on Private.**
- Open WebUI supports `ENABLE_PERSISTENT_CONFIG=false` /
  `RESET_CONFIG_ON_START=true` + `OPENAI_API_CONFIGS`, making the connection
  wizard fully env-provisionable (kills the empty-dropdown 401 gotcha class).
- OpenRouter free-tier daily cap is **account-wide across all `:free` models**
  (1000/day at ≥$10 balance) — fan-out across free models does not multiply
  quota. Paid spread does. Account has ~$12.09 of $20 prepaid remaining;
  `qwen/qwen3-235b-a22b-2507` ($0.09/$0.55 per M) undercuts gpt-4o-mini.
- Host GPU: RTX 1000 Ada, 6GB. gemma4:12b (7.6GB) partially CPU-offloaded;
  two resident models don't fit.
- **Quantize-down is a dead end:** the served 12b is already Q4_K_M (verified via
  `ollama show`); benchmark consensus is Q3/Q2 quality loss — worst on tool calling
  and constraint following — is disqualifying. Check for a `gemma4:12b` QAT q4_0
  tag instead: same size, trained-for-quantization quality bump, zero VRAM cost.
- **Private model strategy is a role split, not a swap:** `gemma4:e4b` (~5GB,
  fully GPU-resident, native tools, same family so the SYSTEM prompt carries over)
  for high-frequency roles — executor steps, tool-calling, checkpoint reviewer;
  12b loaded on demand for low-frequency judgment — planning, final review. The
  E4B side-by-side benchmark (tool-call accuracy on registry schemas, tokens/sec,
  `ollama ps` showing 100% GPU) is slice 15c's entry gate.

---

## 2. Target architecture

```
owner (chat)                          n8n (cron)
   │                                     │
   ▼                                     ▼
cooper-core ──── planner: big-brain model drafts plan+envelope   (15e)
   │                │
   │                ▼
   │        council critique panel, dissents attached            (15d)
   │                │
   │                ▼
   │        OWNER APPROVES → envelope hash-pinned                (14b mechanic)
   │                │
   │                ▼
   │        executor loop: cheap model runs steps                (15a calls,
   │          Open: cheap cloud alias · Private: gemma4           15c routing)
   │          envelope enforced IN CODE per step
   │          optional checkpoint reviewer → exception queue only
   │                │
   │                ▼
   │        final review: single reviewer (≤L3) / council (L4+)  (15d)
   │                │
   │                ▼
   └──────── evidence record: plan hash + council verdicts       (M7 held)
```

## 3. New slices

Same discipline as Step 14: each ships alone, runs live before the next
starts, lands with tests, full suite green.

| Slice | Builds | Closes | DoD (observable, running) |
|---|---|---|---|
| **15a** | **Native tool-calling dispatch.** Registry entries rendered as OpenAI-format tool schemas; model emits validated `tool_calls`; a tool_call becomes a dispatch ticket exactly as today (approval gate unchanged). Open: gpt-4o-mini tools via LiteLLM. Private: gemma4 via Ollama `tools`. Retires `_NOTE_WRITE_RE`, `_MODEL_HINT_RE` and the classifier's dispatch-routing role; approval previews show validated args | M3→5, M1 reachability | The two dead Gotchas die live: `lite_llm_router` dispatches from all three previously-failing phrasings; a note write in ordinary phrasing (incl. the previously-impossible subdirectory case surfaced as a proper refusal, not a post-approval parse error). A registry-walk test asserts every enabled tool is schema-reachable — this test IS metric M1 permanently |
| **15b** | **Zero-touch provisioning.** `install-cooper.sh` injects the generated key + `OPENAI_API_CONFIGS` into both compose files; `RESET_CONFIG_ON_START` strategy documented for existing volumes; optional admin-account seeding via signup API | M9→5 | Fresh volume → working browser chat with zero Settings-UI clicks, both stacks |
| **15c** | **Per-role model routing.** Implement `Scripts/PDA_ModelRouting.json` in cooper-core (repo rule: no new policy files — implement existing ones): role→alias map (classifier/brain/planner/executor/reviewer/drafter/archivist). Private mapping per the role-split decision above: `gemma4:e4b` resident for high-frequency roles, 12b on-demand for judgment; E4B benchmark is this slice's entry gate. LiteLLM fallback pools: same alias, multiple deployments (e.g. gpt-4o-mini via OpenAI + via OpenRouter) for automatic 429 failover | cooldown resilience; prereq for 15d/15e | Kill one provider key mid-conversation → turn still completes via fallback (logged); each role provably queries its mapped alias (LiteLLM logs) |
| **15d** | **Council subsystem.** Planning-time: 3–5 diverse aliases independently critique a drafted envelope; dissents attached to the approval request. Final review: council for L4+ / file-writing jobs, single reviewer otherwise. All verdicts + dissents land in the evidence record. Councils never run mid-loop | M6→5, feeds M7 | An envelope with a seeded flaw (over-broad write_scope) draws at least one council objection that reaches the owner's approval prompt; a passing L4 job's evidence record contains named per-member verdicts |
| **15e** | **Planner–executor.** `POST /jobs/draft`: big-brain alias drafts a complete `jobs_registry.yaml` envelope + per-step instructions from an owner's natural-language goal; flows through 15d council → owner approval → 14b hash mechanic. Executor loop (14b/14d runner) runs steps on the cheap executor alias with the plan's instructions in context | M2→4 | Owner states a goal in chat; a council-reviewed envelope arrives for approval; on approval the job runs unattended within it; big-brain alias is called zero times during execution (LiteLLM logs prove the split) |
| **15f** | **Robustness hardening.** (i) Injection canaries: adversarial suite feeding hostile web/tool content through `web_search`/`browser`/`fabric_pattern` paths — untrusted text enters prompts only as quoted data, never instructions; ships WITH 14c, not after. (ii) Implement `Scripts/PDA_RetryPolicy.json` (existing declarative policy, currently unread) as per-stage timeout/retry budgets — kills the 120s triple-LLM-chain failure class (Step 11 incident). (iii) Chaos tests: backend killed mid-dispatch, malformed tool output, disk-full | M8→5 | Canary suite green in CI; a mid-dispatch backend kill yields an honest error + evidence record, not a hang; retry budgets visible in logs |
| **15g** | **Governed learning breadth.** (i) Outcome-weighted skill scoring: reviewer pass/fail per activation feeds the score (data already in `cooper_memory.db`). (ii) Prompt self-optimization, governed: optimizer proposes a prompt *diff* → owner approves → hash-pinned like a skill (the DSPy/GEPA capability declined in the Hermes merge, now under COOPER rules). (iii) Job runs feed the skill drafter — jobs are inherently repeatable, exactly what the 2026-08-02 draft gate awaits | M5→5 | A skill's score visibly moves on a failed review; one prompt improvement lands through the full propose→approve→pin loop; first job-sourced draft offer observed live (closes the never-observed-notice item) |
| **15h** | **Session plans** (governance-gated — G3). The per-job-approval amendment generalized to interactive work: a chat-drafted plan approved once (hash-pinned, edit voids), then N steps executed unattended with digest reporting | M2→5 | A multi-step chat task completes with exactly one approval; an out-of-plan action lands in the exception queue |
| **15i** | **COOPER Cockpit — custom UI** (owner-added 2026-08-18), replacing Open WebUI as the product surface. Pages: **chat** with native decision/approval affordances (approve/deny buttons instead of phrase-regex matching — retires the approval-phrase fragility class, Gotchas 2026-07-21 — plus the `decision` field rendered, not hidden); **brain graph** — interactive graph of the Obsidian vault's notes + wikilinks (COOPER's brain made visible), extendable to skills/memory links; **workflow monitor** — live job runs per step, exception-queue drain, evidence-record browser; **metrics dashboard** — M1–M9 scores, skill activations/trust, per-alias model usage + spend; **settings** — registries, routing map, job envelopes. Governance invariant: the Cockpit is a *client* of the same bearer-authed API — every action passes the same approval gate; governance edits remain explicit owner actions; no privileged side-channel. Design pending its own spec; lands incrementally | product surface; surfaces M7 live; supersedes 15b's wizard problem long-term | Monitor page shows a live 14b job run end-to-end; chat page reaches parity and is **browser-verified**; Open WebUI retires only after that verification (same rule as the v1 PS-webhook retirement) |

## 4. Execution order (merged with Step 14)

```
15a → 14a(revised) → 15c → 14b → 15d → 15e → 14c(+15f-i) → 14d → 14e → 15f(ii,iii) → 15g → 15h
15b: independent, anytime.   14f: still blocked on owner hardware choice.
15i (Cockpit) lands incrementally alongside, not as one slice: workflow-monitor page
after 14b (something to monitor), metrics dashboard after 15d (verdicts to show),
chat-parity + brain graph + settings before 15h. 15b still ships — it fixes today's
stack cheaply and Open WebUI stays until Cockpit chat parity is browser-verified.
```

Rationale: 15a first because 14a-as-planned builds on the architecture 15a
retires; 15c before 15d/15e because both consume the role map; 15f-i is welded
to 14c because untrusted web content entering an autonomous loop is exactly
Hermes's RCE vector — 14c does not ship without it.

## 5. Metric traceability

| Metric | Today | Closed by | Open ceiling | Private ceiling |
|---|---|---|---|---|
| M1 | 3 | 15a + 14b/14c executors + registry-walk test | 5 | 5 (scored within its boundary — cloud tools excluded by design, not missing) |
| M2 | 1 | 14b (→3), 15e (→4), 15h (→5) | 5 | 5 (jobs + local planner; see G1 for the better-planner variant) |
| M3 | 2 | 15a | 5 | 5 (gemma4 native tools; measure the 86% claim live) |
| M4 | 5 | held — every slice states its governance treatment | 5 | 5 |
| M5 | 4 | 15g | 5 | 5 (optimization evals run slower locally; same loop) |
| M6 | 4 | 15d + 15c | 5 | 4–5: needs the gemma4:e4b-as-reviewer benchmark; if 4b review quality fails, honest ceiling is 4 (same-model review) |
| M7 | 5 | held — plan hashes + council verdicts extend the evidence schema | 5 | 5 |
| M8 | 4 | 15f | 5 | 5 |
| M9 | 4 | 15b | 5 | 5 |

## 6. Governance decisions required (owner-only; nothing proceeds past the gate without an explicit answer)

| # | Decision | Needed by | Default if undecided |
|---|---|---|---|
| G1 | **Private plan-handoff:** may an Open-drafted, owner-approved plan file be handed inbound to Private for execution? Defensible iff the planning context contains zero Category 2 data; still boundary-adjacent | 15e | No — Private plans locally with gemma4 (weaker plans, purest boundary) |
| G2 | **Open brain/planner model:** reverse the 2026-08-04 "stays gpt-4o-mini" decision? Candidates: `qwen3-235b` (cheaper than current), `:free` Nemotron/GLM (provider may log prompts — Category 1 only, stated not assumed). Planner role (15c) can differ from brain | 15c | Brain stays gpt-4o-mini; planner alias choice still required |
| G3 | **Session-plans amendment** (15h): extends per-job approval to interactive chat work | 15h | Not enacted; M2 rests at 4 |
| G4 | **SearXNG scope:** Open-stack only, or also reachable from Private (self-hosted, so local-only is possible)? | 14c | Open only |
| G5 | **Spend guard:** set an OpenRouter spend limit / burn alert now that credit drawdown is confirmed ($7.91 of $20 used) | anytime | none set (status quo) |

## 7. Rejected in this design (recorded so they stay rejected)

- **Mid-run council checkpoints** — deliberation cannot outperform a hash
  check at boundary enforcement; cost is 10+ calls per checkpoint. Mechanisms
  enforce bounds; councils judge quality.
- **Runtime LLM-picks-the-LLM routing** — adds a call per step and breaks
  M7 ("the router felt like Claude today" is not an audit line). All model
  assignment is declarative (15c map, envelope per-stage fields).
- **Vendoring an agent SDK / framework for the loop** — same "own
  everything" grounds as the Hermes merge decision.
- **Fan-out across `:free` models for quota** — the cap is account-wide;
  the mechanism doesn't exist.

## 8. Out of scope

Signal/email push (unchanged, far-later); autonomous code edits by the repo
steward (14e stays draft-and-notify); prompt-level self-optimization beyond
the governed diff loop of 15g.
