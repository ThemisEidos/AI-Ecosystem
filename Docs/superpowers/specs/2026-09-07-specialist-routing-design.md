# Specialist Routing — the foreman delegates (owner-directed 2026-09-07)

Owner's words: gpt-4o-mini "should be deciding what the workflow is and identifying those
specialist models and assigning them tasks where needed and routing that task through the
openrouter to those models." The PRD's "right tool for the job" made concrete: cheap brain
decides and delegates; specialists execute; LiteLLM/OpenRouter is the road.

## What exists / what's missing

`lite_llm_router` (executor `llm_api`) already routes a prompt to a LiteLLM alias. Two gaps:
1. **No roster.** It forwards ANY `model` string — no governance allowlist, and per Gotchas
   2026-08-04 raw slugs silently fail anyway; only aliases work.
2. **The brain is blind.** The tool schema names no specialists and describes no strengths,
   so the foreman cannot choose one. "Identifying the specialist" requires being told the
   options.

## Design

1. **Roster as data** — `Scripts/PDA_ModelRouting.json` gains a `specialists` map:
   `name → {alias, description}`. Owner-editable; adding a specialist is a JSON edit.
   v1 roster uses only aliases that already exist in LiteLLM (`openai`, `claude`,
   `gemini`, `gemini-pro`); widening the `openrouter` alias to more slugs is a later,
   separate LiteLLM-config change.
2. **Schema-level enforcement** — the tool's `specialist` parameter is an **enum** of
   roster names in the registry YAML, so the model literally cannot emit an off-roster
   name. A consistency test (drift-guard pattern) fails if the YAML enum and the JSON
   roster ever diverge. Code validates again at execution (defense in depth: schema is
   advisory to a misbehaving model; the executor is not).
3. **The brain is told its options** — the tool description enumerates each specialist
   and when to use it. That is the "deciding" half.
4. **Result provenance** — replies stay labeled `[Specialist: <name> (<alias>)]` so the
   owner always sees who did the work (M7: auditability).
5. **Governance unchanged** — the tool keeps L3 + approval_required: true. Lowering an
   approval gate is an owner decision, flagged as an open decision point, not assumed.
6. **Budgets** — the call runs under the 15f `executor` role budget (90s), previously
   reserved with no call site; this is its call site.

## Out of scope
- Multi-step autonomous decomposition (chains across turns are the human-in-loop path).
- New LiteLLM aliases / OpenRouter slug widening.
- Job-pipeline specialist routing (jobs keep their per-role config).

## Tests
Roster load/validate; enum↔roster drift guard; off-roster refused in code; empty task
refused; label present; budget wiring; full suite; live: real delegation to `claude`
through the running stack with the reply labeled.
