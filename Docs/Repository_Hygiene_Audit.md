# Repository Hygiene Audit

## Current State

The repository is functionally ahead of its hygiene state.

The governing numbered docs and the governed COOPER status stack are in place, but the working tree still contains legacy root-document deletions, mutable runtime artifacts, and local workspace noise. The repository is not yet clean enough to call the hygiene baseline complete.

## Remaining Noise

### Legacy root-document deletions

- `AI Tool Stack & Roles.md`
- `AI_Ecosystem_Architecture.md`
- `Obsidian Vault Structure.md`
- `Reporting Workflow Standards.md`
- `Security & Compartmentalization Policy.md`

Classification:

- intentional legacy-document cleanup
- duplicates already replaced by numbered documents
- should remain deleted if the migration is being finalized

Recommendation:

- delete intentionally in the repository history cleanup path
- do not restore

### Runtime artifacts

- `Models/cooper-personality/personality.json`
- `Scripts/COOPER_Personality.json`

Classification:

- runtime state / live personality profile
- mutable test dependency
- not a stable baseline for repository history

Recommendation:

- do not commit as normal source
- move to a separate runtime folder or exclude via `.gitignore`
- keep tracked only if the project explicitly needs a versioned baseline snapshot, not the live mutable file

### Workspace noise

- `Legacy_Docs/`
- `Obsidian Vault/02_Projects/opt-out/`
- `codex-automation-damage-snapshot.diff`
- `codex-automation-damage-snapshot.stat.txt`
- `codex-automation-damage-status.txt`
- `codex-automation-quarantine/`

Classification:

- `Legacy_Docs/`: archive material with a README, but still uncommitted workspace content
- `Obsidian Vault/02_Projects/opt-out/`: local workspace / project asset noise
- `codex-automation-damage-*`: temporary artifact files
- `codex-automation-quarantine/`: quarantine artifact directory

Recommendation:

- `Legacy_Docs/`: either commit intentionally as archive material or ignore if it is meant to stay local-only
- `Obsidian Vault/02_Projects/opt-out/`: gitignore or relocate out of the repository tree
- `codex-automation-damage-*`: gitignore or delete after verification
- `codex-automation-quarantine/`: gitignore or delete after verification

## Runtime Artifacts

### `Models/cooper-personality/personality.json`

Observed state:

- differs from HEAD
- currently holds the live personality profile values used during validation

Classification:

- runtime state
- not a stable configuration baseline in its current form

Commit policy:

- do not commit as part of normal hygiene cleanup
- prefer a separate runtime storage location or explicit ignore rule

### `Scripts/COOPER_Personality.json`

Observed state:

- differs from HEAD
- mirrors the live personality profile and related runtime metadata

Classification:

- generated runtime mirror
- test/runtime dependency

Commit policy:

- do not commit as normal source
- prefer `.gitignore` or a separate runtime folder for generated mirrors

## Legacy Documents

The deleted root-level docs are legacy duplicates of the numbered source-of-truth documents.

They are replaced by:

- `00_Project Charter.md`
- `01_AI Ecosystem Architecture.md`
- `02_COOPER System Specification.md`
- `03_AI Tool Stack & Roles.md`
- `04_Security & Compartmentalization Policy.md`
- `05_Reporting Workflow Standards.md`
- `06_Automation & Workflow Catalog.md`
- `07_Implementation Roadmap.md`
- `08_Obsidian Vault Structure.md`

Recommendation:

- keep the numbered docs as authoritative
- keep the legacy root deletions intentional
- archive only if a separate migration archive is still desired for audit traceability

## .gitignore Recommendations

Current `.gitignore` covers many runtime and secret patterns, but it is missing explicit rules for the current hygiene noise.

Recommended additions:

- `Models/cooper-personality/personality.json`
- `Scripts/COOPER_Personality.json`
- `Legacy_Docs/`
- `Obsidian Vault/02_Projects/opt-out/`
- `codex-automation-*`
- `Obsidian Vault/02_Projects/AI Tool Ecosystem/PDA Dashboard.md`
- `Obsidian Vault/02_Projects/AI Tool Ecosystem/System Status.md`

Optional follow-up patterns if generated runtime files continue to appear:

- `*_live.json`
- `*_runtime.json`
- `*_generated.json`

## Cleanup Recommendations

### Immediate

1. Keep the numbered docs as the source of truth.
2. Leave the legacy root-document deletions in place and commit them only as part of the migration cleanup path.
3. Exclude or relocate `Models/cooper-personality/personality.json` and `Scripts/COOPER_Personality.json` so runtime personality drift stops polluting the working tree.
4. Ignore or move the `codex-automation-*` artifacts and `Obsidian Vault/02_Projects/opt-out/` workspace noise.

### Near-Term

1. Add explicit `.gitignore` entries for the runtime artifacts and local workspace noise.
2. Decide whether `Legacy_Docs/` is a tracked archive or a local-only migration aid.
3. Stop generating dashboard/status mirror files directly into tracked workspace paths.

### Optional

1. Move mutable runtime state into a dedicated runtime directory.
2. Separate archived legacy docs from active workspace noise more clearly.
3. Add a short repository hygiene checklist to future commit prep.

## Validation

Reviewed:

- `git status --short`
- `git ls-files`
- `git check-ignore -v` on representative runtime, archive, and noise paths
- runtime file diffs for `Models/cooper-personality/personality.json`
- runtime file diffs for `Scripts/COOPER_Personality.json`

Conclusion:

- repository is not yet ready for Phase 5A as a clean baseline
- the governed stack is functional, but the hygiene baseline still needs cleanup and ignore rules

