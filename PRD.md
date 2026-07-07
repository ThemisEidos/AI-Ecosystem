# COOPER — Scope Plan & PRD (v2)

> **Status:** north-star plan. Changes rarely. Return here whenever the build drifts.
> **The one rule that governs this rebuild:** every phase ends in something that *runs*, not something that *describes*. No new standards documents count as "done." If you can't execute it, it isn't finished.
>
> **Project:** COOPER (Command Operations Orchestrator for Planning, Execution, and Reporting) — the governed operator surface for the AI Ecosystem / PDA platform.
> **Repo:** AI-Ecosystem (`D:\D_Projects\01_AI_Ecosystem`)
> **Owner:** ThemisEidos
> **Companion docs:** `CLAUDE.md` (how c3 works in the repo) · `PROGRESS.md` (living state)

---

## 1. Vision (unchanged — it was always right)

A personality-driven AI controller, COOPER, that you talk to in a web chat UI. COOPER is the **operations foreman, not the worker**: it interprets a request inside the workshop you selected, enforces policy, routes work to the best tool or model, has sub-agents review the work, and reports results back for your final approval. Right tool for the job — a specialist model per task, not one generalist doing everything adequately.

## 2. The honest diagnosis (why we're rebuilding)

The project accumulated an excellent **governance specification** — workshop model, 6-level permission ladder, Category 1/2 separation, evidence schema, Fabric and Workspace roles — across ~13 documented "phases." But by each phase's own written Definition of Done, those phases produced *documents, not running code* ("no execution code is changed," "linter scripts deferred," "documentation-first"). The result: COOPER's runtime is roughly 10% built while the paperwork makes it feel 90% done.

Two concrete symptoms:
1. **The PDA-Bridge is usually unreachable** — the conversation transport is a hand-rolled raw TCP socket in PowerShell that dies without recovery.
2. **COOPER can't converse** — the router is a task-dispatcher with no "just talk to me" path.

**Root cause:** the guardrails repeated in every doc ("no agents, no orchestration, no database, no queue, no execution runner, no autonomous loops") were meant to stop scope creep, but COOPER *is* an orchestration layer — so each phase that reaffirmed those prohibitions quietly voted against building the actual product. The fix is not more documents. It's the thin runtime that *implements* the spec you already wrote.

## 3. Decision: Path A

Keep the entire governance corpus as the **binding specification**, and build the runtime that implements it. The spec is the asset; the runtime is the gap. We are not rewriting the governance — we are making it real.

## 4. What we keep, build, and retire

**Keep as binding spec (do not re-document, just implement):**
- The two-workshop model: Open Workshop (COOPER, cloud-capable, Claude Sonnet default) vs Private Workshop (COOPER Private, local-only, Qwen via Ollama, never falls back to cloud).
- The 6-level permission ladder (L0 inform -> L5 destructive/blocked), with one-time-per-action approval (Phase 1 rule: no remembered permissions).
- Category 1 (Open/cloud-allowed) vs Category 2 (Private/local-only) data classification and the sanitization gate.
- The Quartermaster (router) / Safety Officer (approval) / Workbench (execution gateway) metaphor.
- Tool Registry contract (name, drawer, role, permission level, executor, approval requirement, I/O shape, security notes).
- Fabric = reusable prompt-pattern layer. Open WebUI Workspace = knowledge/RAG layer. Neither replaces governance.
- Storage boundaries (Obsidian = Knowledge Shelf; Restricted DMZ Workspace; Secure Vault and StandardNotes remain human-only, outside COOPER).
- The workflow evidence concept (file-based, WF-004 reads it).

**Build (the missing runtime):**
- A FastAPI backend that owns conversation and orchestration (replaces the raw TCP socket).
- COOPER's conversational reasoning core (the inversion: converse first, *then* decide answer / clarify / dispatch).
- A real registry reader + router that enforces workshop + permission level in code.
- A real approval gate that holds execution until you say yes.
- A tool-execution gateway that actually invokes a tool and returns a result.

**Retire / wrap:**
- The PowerShell raw-socket webhook server -> deleted, replaced by FastAPI.
- The ~200 PowerShell scripts -> not deleted; wrapped as callable registry tools where they do real deterministic work (consistent with your own AI-Judgment/Mechanical-Work separation standard — which is actually a *good* design principle, just never executed).

## 5. Roadmap — every step's Definition of Done is "it runs"

> Discipline rule restated: if the step ends in a markdown standard instead of an executable, it is **not done**.

1. **Conversational runtime.** FastAPI service + one chat endpoint to Ollama. DoD: you send COOPER a message and he answers conversationally, in-character, in the web UI. *(Fixes both symptoms. Highest priority.)*
2. **Decision layer.** COOPER classifies each turn: answer / clarify / dispatch. DoD: COOPER asks a clarifying question on a vague request and answers directly on a simple one — observably, at runtime.
3. **Registry reader + router (Quartermaster).** Load the real tool registry; select a capability by workshop + role. DoD: "what tools are available?" returns the actual registry contents for the active workshop.
4. **Approval gate (Safety Officer).** Enforce the permission ladder in code. DoD: a Level 2+ action visibly halts and waits for your approval before proceeding; Level 0/1 auto-run.
5. **Execution gateway (Workbench) + one real tool.** Wire one PowerShell/CLI tool end-to-end. DoD: COOPER executes a real tool after approval and shows you the result + artifact path.
6. **Workshop enforcement.** Open vs Private boundary enforced at the routing layer. DoD: Private Workshop refuses a cloud call at runtime; Open Workshop allows an approved one.
7. **Sub-agent review loop.** Worker -> reviewer -> governor (steal loki-mode's RARV + anti-sycophancy + "empty review blocks" patterns). DoD: a dispatched task is checked by a reviewer agent before results reach you.
8. **Memory + skill loop.** ChromaDB + the Obsidian "brain" read each turn; successful tasks abstracted into scored, versioned skills (the "exceed Hermes" step). DoD: COOPER recalls a prior decision and reuses a saved skill at runtime.
9. **Dockerize + portability.** Clean deploy on WSL2 now, Pop!_OS later. DoD: `docker compose up` brings COOPER fully online on a fresh checkout.

## 6. Patterns stolen from comparable projects (apply during build, not as docs)

- **loki-mode (trust layer):** blind 3-reviewer council, anti-sycophancy "Devil's Advocate" reviewer, RARV loop (Reason->Act->Reflect->Verify with self-correction), "empty review proves nothing -> BLOCK," episodic->semantic memory pipeline. -> steps 7-8.
- **Agentic OS:** `brain/` folder of shared markdown read at session start (your Obsidian vault already is this), skills with eval scoring + score history, FastAPI + light SPA backbone. -> steps 1, 8.
- **Ecosystem (budget/tiering):** hard budget stops, inspectable run receipts, provider tiering with graceful degradation (maps to your "right tool for the job"). -> steps 3, 5.
- **Explicitly NOT stolen:** loki's 10k-line Bash core, its code-only focus, Agentic OS's 3-agent lock-in, Hermes's allow-all security default.

## 7. Where COOPER stands vs Hermes

Behind on the self-improving skill loop (closed at step 8). Ahead on multi-agent orchestration, governance/auditability, and — your genuine edge, which none of the others have — the classification-based Open/Private security model. "Better than Hermes" is earned at step 8.

## 8. Definition of done (project)

You can talk to a personality-driven COOPER in a web UI that actually converses; it routes tasks to best-fit tools/models; worker/reviewer/governor sub-agents check work; the Open/Private boundary and approval ladder are enforced *in running code, not prose*; and you get results + artifact paths for final approval. Top-tier version is then hardening: error handling, reliability, sub-agent disagreement cases.

## 9. Tech stack

Frontend: Open WebUI (existing). Backend: Python + FastAPI. COOPER runtime: Ollama (Gemma/Qwen-class; swappable). Routing: LiteLLM + OpenRouter. Vector memory: ChromaDB. State: SQLite (SQLAlchemy). Human memory: Markdown / Obsidian "brain". Automation: n8n (retained). Containers: Docker Compose. Target OS: WSL2 -> Pop!_OS.

## 10. Anti-drift checklist (read before declaring any phase done)

- [ ] Does the artifact RUN, or only describe? If only describe -> not done.
- [ ] Can I demonstrate the DoD live, end to end, right now?
- [ ] Did I avoid writing a new "standard/doctrine/policy" doc this phase?
- [ ] Did I implement the existing spec rather than re-specify it?
- [ ] Is `PROGRESS.md` updated with what now runs?

## 11. Companion documents (c3 authors these)

- **`CLAUDE.md`** (repo root) — operating manual c3 reads automatically each session: repo map, real start/stop/status commands, conventions, do-not-touch list, how to run tests, and a one-line "current vs target architecture" pointer to this PRD. c3 writes it because c3 has repo ground truth.
- **`PROGRESS.md`** (repo root) — living state: the 9-step checklist above, current-step marker, decisions log, blocked/needs-input section. Updated every session.
