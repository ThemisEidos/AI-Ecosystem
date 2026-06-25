# Workspace Governance Core Retrieval Validation Report

Validation date: 2026-06-24

## Purpose

Validate real-world retrieval behavior of the Open WebUI Workspace knowledge layer for the `AI Ecosystem Governance` collection.

## Test Methodology

Manual retrieval validation was performed as a source-grounded audit of the ingested governance corpus.

The test approach used the same question set that would be asked in Open WebUI chat with Workspace context enabled, then compared the expected retrieval answer against the approved repository documents.

This repository environment does not expose a live Open WebUI chat session, so the report documents a manual corpus-based retrieval audit rather than an API-level vector-store probe.

## Required Test Questions

| Question | Validated response summary | Evaluation |
|---|---|---|
| What is the current roadmap phase? | Phase 8 - Open WebUI Workspace Knowledge Layer is current. The roadmap states Phase 8 is the current phase and the next work is scope and readiness for the Workspace knowledge layer. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What is WF-004 responsible for? | WF-004 Operational Status summarizes ecosystem health and readiness from runtime/state evidence, and the workflow catalog says it should treat canonical workflow evidence records as the primary source of truth when present. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What is the difference between Open Workshop and Private Workshop? | Open Workshop is Category 1, cloud-allowed, and may use approved cloud AI and general automation. Private Workshop is Category 2, local-only, and must not route to cloud AI or third-party execution paths. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What content is prohibited in Open WebUI Workspace? | Registries, approval rules, runtime state, secrets, private data, and personality state are prohibited. Workspace is for knowledge and reference assets only. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What is WF-006 allowed to do? | WF-006 turns approved research output into a knowledge collection import draft, runs in Open Workshop, and carries forward only approved sources and source URLs. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What is the role of Obsidian vs Workspace? | Obsidian is the Knowledge Shelf and working knowledge base. Open WebUI Workspace is a separate knowledge and reference-asset layer for governed collections and reference libraries. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |
| What is the Security & Compartmentalization Policy for Private Workshop? | Private Workshop is local-only, cannot use cloud AI, cannot fall back to cloud models, and may write only to the Restricted DMZ Workspace unless a sanitized Category 1 export is moved to Open Workshop. | Correct; Grounded in docs: yes; Hallucination present: no; Missing context: no |

## Findings

### Strengths of Workspace Retrieval

- Core governance questions resolve cleanly from the imported document set.
- Phase and workshop boundary questions are strongly grounded and consistent across the roadmap, architecture, and policy docs.
- Security boundaries are explicit enough that retrieval should answer them with low ambiguity.
- WF-006 is clearly constrained to approved-source import drafting, which makes its retrieval target narrow and stable.

### Gaps in Retrieval Accuracy

- The collection is coherent, but several answers depend on cross-document synthesis rather than a single source line.
- WF-004 spans the roadmap, workflow catalog, and evidence standard, so retrieval quality depends on cross-linking multiple docs correctly.
- The current validation could not directly exercise a live Open WebUI vector-store session in this repository environment.

### Missing or Weak Document Linkage

- The relationship between Obsidian and Workspace is spread across architecture, tool stack, and vault-structure documents rather than concentrated in one canonical definition.
- WF-004 and WF-006 are understandable, but retrieval works best when the roadmap, workflow catalog, and policy docs all remain synchronized.

### Contradictions Between Docs and Retrieval Output

- No contradictions were identified in the source corpus used for this validation.
- The documents align on Phase 8 being current, Workspace being knowledge-focused, and Private Workshop being local-only.

## Risk Assessment

- Over-reliance risk on Workspace vs repo truth: Workspace should remain a cached interpretation layer, not the source of truth. Repo documents remain authoritative.
- Hallucination risk from incomplete ingestion: Low for the tested governance prompts if all nine documents are present, but it increases if any core doc is missing or stale.
- Context dilution risk: Moderate if additional mixed-purpose collections are added later; the current governance set is narrow enough to stay useful.
- Sensitive data leakage risk: No sensitive data was identified in the imported governance corpus used for this validation.

## Conclusion

Workspace is partially ready, with constraints.

The imported governance collection is coherent, source-grounded, and retrieval-friendly for core policy and roadmap questions, but this report does not prove live vector-store behavior in Open WebUI itself. That means the collection is suitable as a governed knowledge layer, but it still needs direct in-app spot validation before being treated as fully production-ready.

## Recommended Next Step

Begin Phase 8 refinement iteration.

