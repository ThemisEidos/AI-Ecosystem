# COOPER × Hermes Merge — Design Spec (Steps 10–13)

**Date:** 2026-07-08
**Status:** Approved by owner (ThemisEidos)
**Branch context:** all COOPER v2 work lives on `step-9-dockerize`; `main` does not have it.

---

## 1. Decision record

### Problem

Hermes Agent (Nous Research, Feb 2026, MIT, ~82.5% Python, 188K GitHub stars) is a
shipped, widely adopted open-source agent runtime with the capabilities COOPER lacks:
a community skills ecosystem (90K+ skills), a self-improvement loop, a multi-platform
messaging gateway, and mature packaging. Question considered: continue COOPER, switch
to Hermes, or merge Hermes's capabilities into COOPER.

### Options considered

1. **Continue COOPER as-is** — keeps governance, stays capability-poor.
2. **Switch to Hermes configured like COOPER** — rides upstream velocity, but Hermes's
   security history disqualifies it as the trust root: independent audit found
   4 Critical / 9 High findings in default config (unrestricted shell execution,
   approval checks unconditionally skipped in container envs, batch-runner
   auto-approve enabling prompt-injection RCE); approvals were fail-open until v0.17.
3. **Merge — port Hermes's capability patterns into cooper-core under COOPER's
   governance.** Chosen.

Within option 3, three execution approaches were weighed:

- **A. Native port, SKILL.md-format-compatible** — chosen.
- B. Vendor Hermes subsystems (MIT permits) — rejected: inherits an unaudited slice of
  a 15k-commit codebase and freezes it; auditing it costs as much as writing it.
- C. COOPER-native skill format from scratch — rejected: forfeits the community hub
  for no gain; the SKILL.md format is trivial and is the de-facto standard.

### Why A works: skills are data, not code

A Hermes skill is a directory containing a `SKILL.md` (YAML frontmatter: `name`,
`description`; markdown body) plus optional `references/`, `templates/`, `scripts/`
directories, distributed as plain git repos ("taps"). Same pattern as Claude Code
skills. COOPER can read the format verbatim without running any Hermes code —
"own everything" and "keep the ecosystem" coexist.

### Owner's requirements (elicited 2026-07-08)

- Purpose split: **75% personal governed platform, 25% distributable** to friends and
  family (local install or VM on a private server).
- Capability priority: **skills ecosystem #1, self-improvement loop #2,** messaging
  gateway #3, ops maturity #4 — all desired.
- Maintenance posture: **own everything.** Native code in cooper-core; Hermes source
  is reference reading only; zero vendored code.

---

## 2. Scope & positioning

Extends the completed 9-step roadmap with **Steps 10–13**:

| Step | Name | Module |
|---|---|---|
| 10 | Governed skills subsystem | `cooper-core/skills.py` |
| 11 | Self-improvement loop | `cooper-core/proposer.py` |
| 12 | Messaging gateway (Telegram, Open workshop only) | `cooper-core/gateway.py` |
| 13 | Friends & family packaging + session-bound approvals | bootstrap script + `approval.py` change |

Steps 10–11 are the core and come first. Each module follows the existing
cooper-core pattern: one focused module + one test file per concern
(as `registry.py` / `test_registry.py`).

---

## 3. Step 10 — Skills subsystem (`skills.py`)

### Format & layout

- `SKILL.md` format is Hermes/Claude-compatible **verbatim**: YAML frontmatter with
  required `name` (must match parent directory) and `description`, markdown body,
  optional `references/`, `scripts/`, `templates/`.
- Skills live at repo root: `Skills/<category>/<skill-name>/SKILL.md` — mirrors the
  tap layout so community skills drop in unmodified.

### Governance manifest (the COOPER differentiator)

A skill on disk is **inert** until registered in `Config/skills_registry.yaml`
(declarative, same discipline as the tool registries):

```yaml
skills:
  - id: weekly-review
    path: Skills/productivity/weekly-review
    workshop: open            # open | private
    permission_level: 1
    approval_required: false
    content_hash: "<sha256 of skill directory at approval time>"
```

- `content_hash` is a SHA-256 computed at approval time over the skill directory's
  files in sorted relative-path order (each file's path + contents fed to one hash),
  so the digest is deterministic across platforms.
- **Verified on every load. Mismatch = skill disabled** with a visible warning until
  re-approved. This is the direct counter to Hermes's persistent-skill-injection CVE
  class: nobody — including the agent itself — can silently mutate an approved skill.
- Re-approval friction on every edit is accepted deliberately (owner approved).
- Manifest is mtime-cached like the tool registries so edits take effect without
  restart under `--reload`.

### Activation modes (two risk classes)

1. **Knowledge skills** (no `scripts/`): on selection, the body is injected into that
   turn's system prompt. Body capped at **≤ 5,000 tokens** (hub convention); oversize
   bodies are truncated with a logged warning. Levels 0/1 — auto-activates.
2. **Script-bearing skills**: the body may instruct, but scripts execute **only
   through the existing Step 5 execution gateway and Step 4 approval gate**. Scripts
   never gain a new execution path. Level 2+ by definition.

### Selection

Skills join the same LLM-backed selection flow as tools (the `select_tool_llm`
pattern: schema-constrained catalog pick, keyword-overlap fallback on any error),
scoped per workshop.

### Importer

New registry tool `import_skill` (Level 2, `approval_required: true`):

1. Fetch tap repo (git clone / archive download).
2. Present the **full SKILL.md content** inside the approval question.
3. On approve: compute `content_hash`, write manifest entry, skill goes live.
4. Imports land in the **Open workshop only** by default; promoting a skill to
   Private is a second explicit approval.

---

## 4. Step 11 — Self-improvement loop (`proposer.py`)

Hermes's learning loop, governed:

- After a successful dispatch→review cycle, the archivist's existing LLM-extraction
  path (Step 8) additionally drafts a candidate `SKILL.md` into `Skills/_drafts/`.
- **Drafts are never loadable** — `_drafts/` is excluded from the loader
  unconditionally.
- On a subsequent turn COOPER surfaces the draft: "I've drafted a skill from this —
  approve to activate?" — a standard single-use approval ticket.
- Promotion = move into `Skills/<category>/`, hash, register in the manifest.
- Usage stats (activation count, last success) stored in `cooper_memory.db` alongside
  the archivist's tables. `State/COOPER_Skills.json` is untouched legacy workflow
  evidence.
- **Out of scope for v1:** prompt-level self-optimization (Hermes's DSPy/GEPA).
  v1 is reuse-counted skill accretion — measurable, no genetic algorithms.

---

## 5. Step 12 — Messaging gateway (`gateway.py`)

- **One channel first: Telegram** (simplest bot API; long-polling, so no inbound port
  opened on the home network).
- **Classification ruling baked in:** messages traverse third-party servers, so the
  gateway binds to the **Open workshop only**. The Private workshop remains reachable
  exclusively from localhost Open WebUI.
- Gateway auth: allowlist of Telegram user IDs (initially the owner's). Pairing a new
  user is itself an approval-gated action.
- Approval tickets over Telegram reuse the existing conversational yes/no next-message
  flow, but multi-client exposure requires Step 13's session binding first.

---

## 6. Step 13 — Friends & family packaging

- Bootstrap script in Hermes's one-command style: check Docker, clone repo, seed
  `.env` from `.env.example`, `docker compose up`. The Step 9 compose stack is the
  backbone; this is a wrapper, not a new runtime path.
- **Mandatory before any second client connects** (closes the audit's deferred item):
  approval tickets bound to session identity. `ApprovalTicket` in
  `cooper-core/approval.py` gains a `session_id`; only the session that triggered a
  dispatch can approve its ticket. Closes the hole where client A approves client B's
  action.

---

## 7. Testing & error handling

Per-module test files matching the existing convention:

- `test_skills.py` — hash mismatch disables the skill; `_drafts/` never loads;
  workshop scoping enforced; 5K-token cap applied; unreadable/malformed manifest
  loads **zero** skills (fail closed), never "all".
- `test_proposer.py` — draft creation, promotion flow, ticket required.
- `test_gateway.py` — non-allowlisted user rejected; private workshop unreachable.
- Integration case: import a skill → tamper with its file → verify it is disabled and
  the warning is surfaced.

**Universal rule: every failure mode fails closed** — the governance property that
distinguishes COOPER from Hermes's CVE history.

---

## 8. Sources

- Hermes ecosystem overview: https://the-agent-report.com/2026/06/hermes-agent-ecosystem-2026-pillar/
- Security audit (4 Critical / 9 High): https://github.com/NousResearch/hermes-agent/issues/7826
- Batch-runner approval bypass: https://github.com/NousResearch/hermes-agent/issues/35164
- CVE cluster analysis: https://labs.cloudsecurityalliance.org/research/csa-research-note-hermes-agent-cves-20260504-csa-styled/
- SKILL.md format reference: https://www.agensi.io/learn/skill-md-format-reference
- Skill authoring guide: https://www.glukhov.org/ai-systems/hermes/authoring-hermes-skill/
- Official skills docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
