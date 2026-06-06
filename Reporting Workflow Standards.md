# Reporting Workflow Standards

## Purpose

This document defines the standard process for creating analytical reports inside the AI operations ecosystem.

It governs how raw notes, evidence, source material, AI-assisted analysis, drafts, reviews, and final products move through a repeatable reporting workflow.

The goal is to create reports that are:

- accurate
- clear
- defensible
- evidence based
- professionally written
- properly reviewed
- suitable for the intended audience
- easy to reproduce using repeatable workflows

This standard applies to:

- investigative reports
- physical security assessments
- cybersecurity reports
- DFIR reports
- intelligence summaries
- business reports
- technical findings
- after action reviews
- executive summaries
- briefing products
- project status reports

---

## Core Reporting Principle

The reporting system follows this rule:

> Source material stays raw.  
> Analysis becomes structured.  
> Final reports become polished.

Raw material, analyst interpretation, AI-assisted drafts, and final products must remain distinguishable from one another.

The reporting workflow should never allow AI assistance, editing, formatting, or summarization to obscure where facts came from or what remains uncertain.

---

## Standard Report Lifecycle

The default lifecycle is:

```text
Capture → Normalize → Analyze → Draft → Review → Finalize → Archive
```

Expanded:

```text
Raw Capture
    ↓
Normalize Notes
    ↓
Build Timeline
    ↓
Identify Findings
    ↓
Analyze Risk / Impact
    ↓
Draft Report
    ↓
Review
    ↓
Finalize
    ↓
Archive / Lessons Learned
```

---

## 1. Capture

Capture is the intake phase.

The purpose is to preserve raw information before it is cleaned, interpreted, or rewritten.

Possible source material includes:

- field notes
- meeting notes
- photos
- screenshots
- logs
- timelines
- emails
- interviews
- documents
- audio notes
- web research
- tool outputs
- AI summaries
- prior reports
- client-provided material

### Capture Rules

- Preserve raw notes before editing.
- Do not overwrite original observations.
- Separate facts from assumptions.
- Label source material clearly.
- Preserve timestamps when available.
- Preserve uncertainty.
- Do not allow AI to invent missing details.
- Do not treat AI summaries as source evidence unless clearly labeled.

### Recommended Storage

```text
05_Reports/
├── 00_Report Inbox/
├── 01_Source Material/
└── 08_Appendices/
```

Attachments may also be stored in:

```text
_Attachments/
├── Images/
├── PDFs/
├── Screenshots/
├── Diagrams/
└── Exports/
```

---

## 2. Normalize

Normalization turns raw material into a consistent working format.

This phase prepares the material for analysis without changing the underlying meaning.

Normalization tasks include:

- correcting timestamp format
- standardizing names
- standardizing locations
- removing duplicates
- separating facts from assumptions
- labeling source type
- organizing photos or attachments
- building a timeline
- identifying missing information
- flagging contradictions
- creating an evidence index

### Recommended Outputs

```text
Normalized Notes.md
Timeline.md
Evidence Index.md
Open Questions.md
Source Material Index.md
```

### Normalization Rules

- Do not change meaning.
- Do not smooth over uncertainty.
- Preserve approximate times if exact times are unknown.
- Mark unresolved conflicts.
- Label inferred information as inferred.
- Keep original notes available for reference.

---

## 3. Analyze

Analysis turns organized facts into meaning.

The purpose is to identify what matters, why it matters, and what actions should follow.

Analysis may identify:

- patterns
- gaps
- risks
- vulnerabilities
- causes
- contributing factors
- impact
- likelihood
- priority
- recommended actions
- unresolved questions

### Analytical Frameworks

Use the framework that fits the report. Do not force every framework into every product.

Possible frameworks include:

- TCREI
- SWOT
- CARVER
- Risk Matrix
- Kill Chain
- MITRE ATT&CK
- 5 Whys
- Timeline Analysis
- Gap Analysis
- Root Cause Analysis
- Course of Action Comparison
- Lessons Learned Analysis

### Analysis Rules

- Separate confirmed observations from analyst judgment.
- Identify the evidence supporting each finding.
- Label assumptions clearly.
- Avoid unsupported certainty.
- Do not inflate weak evidence into strong conclusions.
- State limitations when information is incomplete.

---

## 4. Draft

Drafting converts analysis into a structured report.

The draft should follow the intended audience, report type, and governing template.

### Standard Report Structure

A general analytical report may include:

```text
Title
Executive Summary
Purpose
Scope
Methodology
Background
Timeline
Findings
Analysis
Recommendations
Limitations
Conclusion
Appendices
```

### Security / Investigation Report Structure

For security, investigative, physical security, or assessment reports, use:

```text
Title
Executive Summary
Purpose
Scope
Methodology
Narrative
Timeline of Events
Findings
Vulnerabilities
Risk Assessment
Recommendations
Supporting Documentation
Appendices
```

### Technical Report Structure

For technical or cyber-focused reports, use:

```text
Title
Executive Summary
Scope
Environment
Methodology
Technical Findings
Evidence
Impact
Recommendations
Validation Steps
Limitations
Appendices
```

### Drafting Rules

- Use plain professional language.
- Keep paragraphs short and readable.
- Make findings specific.
- Make recommendations actionable.
- Keep executive summaries concise.
- Do not bury the main point.
- Preserve uncertainty where applicable.
- Avoid jargon unless the audience requires it.
- Match the final format expected by the audience.

---

## 5. Review

Review ensures the report is accurate, clear, defensible, and ready for release.

### Review Stages

```text
Self Review
AI Review
Peer Review
Final Human Review
```

AI may support review, but the human author remains responsible for accuracy and judgment.

### Review Criteria

Check for:

- accuracy
- clarity
- logic
- tone
- formatting
- source support
- missing facts
- unsupported claims
- inconsistent timelines
- weak recommendations
- sensitive information
- client or audience suitability
- proper appendix references

### Review Questions

Before finalizing, every report should answer:

- Is the purpose clear?
- Is the scope defined?
- Are facts separated from assumptions?
- Are findings supported by evidence?
- Are timelines internally consistent?
- Are recommendations actionable?
- Is the tone professional?
- Is sensitive information controlled?
- Are appendices referenced correctly?
- Has the report been reviewed?
- Is the final version stored separately from drafts?

---

## 6. Finalize

Finalization prepares the report for delivery or long-term recordkeeping.

Possible final products include:

- Word document
- PDF
- PowerPoint briefing
- executive summary
- one page summary
- appendix package
- timeline chart
- finding matrix
- action tracker
- lessons learned document

### Finalization Rules

- Store final products separately from drafts.
- Preserve the final version exactly as delivered.
- Maintain source material and working notes.
- Record the date of finalization.
- Record the intended audience.
- Record any known limitations.
- Archive related working material when the report is complete.

### Recommended Final Storage

```text
05_Reports/
└── 07_Final/
```

---

## 7. Archive and Lessons Learned

Completed reporting projects should be archived.

Archiving should preserve:

- final report
- source material index
- evidence index
- timeline
- key drafts
- review notes
- lessons learned
- reusable report sections
- reusable prompts
- reusable templates

### Lessons Learned Questions

After completing a report, capture:

- What worked well?
- What slowed the process down?
- What information was missing?
- What template should be improved?
- What prompts were useful?
- What review issues repeated?
- What should be automated next time?

---

## Recommended Report Folder Structure

Use this structure inside the Obsidian vault:

```text
05_Reports/
├── 00_Report Inbox/
├── 01_Source Material/
├── 02_Normalized Notes/
├── 03_Timelines/
├── 04_Analysis/
├── 05_Drafts/
├── 06_Review/
├── 07_Final/
├── 08_Appendices/
├── 09_Templates/
└── 10_Lessons Learned/
```

### Folder Purpose

| Folder | Purpose |
|---|---|
| `00_Report Inbox/` | Temporary holding area for raw reporting material |
| `01_Source Material/` | Original notes, evidence references, documents, and source indexes |
| `02_Normalized Notes/` | Cleaned and structured working notes |
| `03_Timelines/` | Chronological timelines and event sequencing |
| `04_Analysis/` | Findings, risk analysis, gap analysis, and assessment notes |
| `05_Drafts/` | Working report drafts |
| `06_Review/` | Review notes, peer feedback, AI review outputs, and corrections |
| `07_Final/` | Finalized reports and delivered products |
| `08_Appendices/` | Supporting photos, screenshots, exhibits, logs, and supplemental material |
| `09_Templates/` | Report templates and reusable structures |
| `10_Lessons Learned/` | Post-report observations and process improvements |

---

## AI Role in Reporting

AI is an assistant, not the source of truth.

### Appropriate AI Uses

AI may help with:

- organizing notes
- creating outlines
- identifying gaps
- building timelines
- rewriting for clarity
- checking grammar
- summarizing long notes
- creating executive summaries
- generating tables
- turning findings into recommendations
- making briefing slide outlines
- formatting appendices
- reviewing tone and consistency

### Inappropriate AI Uses

AI must not:

- invent facts
- fill gaps without labeling assumptions
- change the meaning of source notes
- remove uncertainty
- overstate conclusions
- create unsupported findings
- hide limitations
- rewrite raw evidence as verified fact
- replace human judgment
- make final determinations without review

### Governing AI Rule

> AI may improve structure, clarity, and analysis.  
> AI may not create facts.

---

## Evidence Standards

Every major claim should trace back to a source.

### Evidence Categories

Use clear evidence labels:

```text
Direct Observation
Documented Record
Photo or Screenshot
Log Output
Interview Statement
Tool Result
Open Source Reference
Analyst Inference
Assumption
Unknown
```

### Recommended Claim Labels

Use these labels to separate fact from interpretation:

```text
Observed:
Documented:
Reported:
Inferred:
Assessed:
Unknown:
```

### Example Use

```text
Observed: The north gate was unsecured at the time of inspection.

Reported: Security personnel stated the gate is normally checked once per shift.

Inferred: The gate may present an after-hours access risk if inspections are inconsistent.

Assessed: This condition increases the likelihood of unauthorized access to the exterior perimeter.

Unknown: It is unknown whether the gate condition was temporary or recurring.
```

---

## Report Tone Standards

Default tone should be:

- professional
- clear
- direct
- neutral
- evidence based
- plain language
- concise
- readable

### Avoid

Avoid:

- overly dramatic language
- unsupported certainty
- slang
- speculation presented as fact
- excessive jargon
- unnecessary passive voice
- bloated sentences
- emotional conclusions
- vague findings
- generic recommendations

### Preferred Phrasing

Use wording such as:

```text
The team observed...
The assessment identified...
Available evidence indicates...
The most likely cause is...
This finding may increase risk by...
Further validation is required to determine...
The available information does not confirm...
The report assesses that...
```

---

## Recommendation Standards

Recommendations should be actionable.

A useful recommendation should identify:

- what should change
- who should act, if known
- why the change matters
- priority
- expected effect
- any dependency or limitation

### Recommendation Format

```markdown
## Recommendation Title

**Priority:** High / Medium / Low

**Issue:** What problem does this address?

**Recommendation:** What should be done?

**Rationale:** Why does this matter?

**Expected Effect:** What improvement should occur?

**Notes / Dependencies:** What else must be considered?
```

---

## Finding Standards

Findings should be specific, evidence-supported, and tied to impact.

### Finding Format

```markdown
## Finding Title

**Status:** Confirmed / Probable / Possible / Unresolved

**Observation:** What was observed?

**Evidence:** What supports this?

**Assessment:** Why does this matter?

**Impact:** What could happen?

**Recommendation:** What should be done?

**Limitations:** What is unknown or unconfirmed?
```

---

## TCREI Reporting Workflow

TCREI is the preferred structure for planning and guiding report generation.

### Task

Define the report product.

Questions:

- What report are we producing?
- What is the required output?
- What is the deadline?
- What is the intended use?

### Context

Define the background.

Questions:

- Who is the audience?
- What happened?
- Why does the report matter?
- What constraints apply?
- What tone is appropriate?
- What sensitivity level applies?

### References

Identify the source material.

Questions:

- What notes are available?
- What evidence is available?
- What templates apply?
- What previous reports are relevant?
- What standards or policies apply?
- What images, logs, timelines, or appendices support the report?

### Evaluate

Define quality criteria.

A strong report should be:

- accurate
- complete
- clear
- defensible
- properly sourced
- audience appropriate
- formatted correctly
- actionable
- internally consistent

### Iterate

Define the next review cycle.

Possible iteration tasks:

- fill gaps
- tighten executive summary
- verify timeline
- clean findings
- improve recommendations
- reduce wordiness
- adjust tone
- prepare final export
- create briefing slides
- build appendix package

---

## Recommended AI Reporting Prompts

Use AI in stages.

### Stage 1 — Organize

```text
Organize these raw notes into a structured outline. Do not add facts. Preserve uncertainty and identify gaps.
```

### Stage 2 — Timeline

```text
Create a chronological timeline from these notes. Preserve approximate times and flag conflicts or missing timestamps.
```

### Stage 3 — Findings

```text
Identify potential findings from these notes. Separate confirmed observations, possible inferences, and unresolved questions.
```

### Stage 4 — Draft

```text
Draft a professional report section using only the provided source notes. Maintain neutral tone and do not add unsupported claims.
```

### Stage 5 — Review

```text
Review this report for clarity, unsupported claims, missing evidence, inconsistent timeline, tone issues, and formatting problems.
```

### Stage 6 — Final Polish

```text
Polish this report for professional readability while preserving all meaning, facts, and uncertainty.
```

---

## Supporting Productivity Methods

The reporting workflow should integrate with the broader AI operations ecosystem.

### PARA

Use PARA for storage and organization.

```text
Projects = active reporting products
Areas = long-term reporting responsibilities
Resources = reusable writing standards, examples, and research
Archives = completed reports and retired materials
```

### GTD

Use GTD for report task management.

Possible task lists:

```text
Next Actions
Waiting For
Open Questions
Review Items
Finalization Tasks
Someday / Maybe
```

### Time Blocking

Use time blocks for report production.

Recommended blocks:

```text
Source Review
Timeline Building
Findings Development
Drafting
Peer Review
Final Polish
Export / Delivery
```

### Pomodoro

Use Pomodoro sessions for tactical execution.

Examples:

```text
2 Pomodoros = clean raw notes
3 Pomodoros = build timeline
4 Pomodoros = draft findings
1 Pomodoro = review executive summary
```

### Zettelkasten

Convert reusable lessons into permanent knowledge notes.

Examples:

```text
How to Write Strong Findings
Common Report Weaknesses
Executive Summary Patterns
Physical Security Report Language
Cybersecurity Recommendation Patterns
Timeline Writing Standards
```

---

## Standard Report Templates to Build

The ecosystem should eventually include:

```text
Investigation Report Template.md
Security Assessment Report Template.md
Executive Summary Template.md
Timeline Template.md
Finding Template.md
Recommendation Template.md
Evidence Index Template.md
After Action Review Template.md
Technical Report Template.md
Briefing Slide Outline Template.md
Lessons Learned Template.md
Report Review Checklist.md
```

---

## Report Quality Checklist

Before a report is finalized, verify:

```markdown
- [ ] Purpose is clear
- [ ] Scope is defined
- [ ] Methodology is described
- [ ] Facts are separated from assumptions
- [ ] Findings are supported by evidence
- [ ] Timeline is internally consistent
- [ ] Recommendations are actionable
- [ ] Tone is professional
- [ ] Sensitive information is controlled
- [ ] Appendices are referenced correctly
- [ ] AI-generated material has been reviewed
- [ ] Unsupported claims have been removed
- [ ] Limitations are stated
- [ ] Final product is stored separately from drafts
- [ ] Lessons learned have been captured
```

---

## Security and Sensitivity Rules

Not all reporting material belongs in a normal Obsidian vault.

### Do Not Store in Plain Obsidian

Avoid storing the following unless the vault is properly protected:

- passwords
- API keys
- client-sensitive raw data
- personally identifying information
- legally sensitive material
- active operational details
- confidential investigative material
- protected evidence
- sensitive screenshots
- restricted logs
- unredacted reports

### Recommended Handling

```text
General reporting standards → Obsidian
Reusable templates → Obsidian
Sanitized notes → Obsidian
Sensitive raw material → encrypted storage
Credentials / keys → password manager
Client deliverables → controlled storage location
Final sensitive reports → encrypted archive
```

### Operating Rule

> Obsidian may organize the workflow.  
> Protected storage should hold sensitive material.

---

## Final Governing Standard

The reporting workflow uses this operating model:

```text
Capture → Normalize → Analyze → Draft → Review → Finalize → Archive
```

Supported by:

```text
TCREI for structure
GTD for task tracking
PARA for storage
Zettelkasten for reusable lessons
Time Blocking for report production
Pomodoro for focused execution
AI for organization and review
Human author for judgment and accountability
```

This document should be reviewed and improved as reporting needs mature.

