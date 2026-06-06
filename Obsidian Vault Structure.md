# Obsidian Vault Structure

## Purpose

This document defines the recommended Obsidian vault structure for the AI Operations Ecosystem.

The vault is intended to function as the knowledge, planning, workflow, and documentation layer for a long-term Personal Digital Analyst environment. It should support productivity, project execution, report writing, AI-assisted workflows, automation planning, and long-term learning without becoming cluttered or overengineered.

The system combines practical productivity frameworks with an AI operations architecture.

## Governing Concept

The Obsidian vault should not be treated as a generic note dump. It should operate as a structured personal operating system.

The recommended model is:

```text
PARA + GTD + TCREI as the core system.
OKRs and SMART Goals for direction and goal definition.
Time Blocking and Pomodoro for execution.
Bullet Journal principles for daily and weekly logging.
Zettelkasten for long-term knowledge development.
```

Each method has a specific job.

| Method | Role in the Ecosystem |
|---|---|
| PARA | Organizes files and notes |
| GTD | Manages task capture and execution flow |
| TCREI | Structures projects, workflows, prompts, and analysis |
| OKRs | Defines quarterly or monthly strategic direction |
| SMART Goals | Makes goals specific and measurable |
| Time Blocking | Protects focused work on the calendar |
| Eisenhower Matrix | Prioritizes tasks by urgency and importance |
| Pomodoro | Supports focused execution sessions |
| Bullet Journal | Provides lightweight daily and weekly logging |
| Zettelkasten | Builds long-term linked knowledge |

## Core Design Principles

The vault should be:

- Simple enough to maintain
- Modular enough to expand
- Structured around outcomes
- Useful for daily execution
- Effective for long-term retrieval
- Compatible with AI-assisted workflows
- Security-conscious and compartmentalized
- Focused on productivity, learning, and project completion

Avoid unnecessary complexity. Start lean and expand only when a recurring need appears.

## Security and Compartmentalization Rule

Obsidian is useful for organizing knowledge and workflows, but it should not automatically become the storage location for sensitive material.

Recommended rule:

```text
Obsidian stores structure, workflows, sanitized notes, references, and planning material.
Sensitive raw material goes into protected storage.
```

Suggested storage boundaries:

| Material Type | Recommended Storage |
|---|---|
| General knowledge | Obsidian |
| Productivity system | Obsidian |
| Sanitized project notes | Obsidian |
| Report templates | Obsidian |
| Reusable prompts | Obsidian |
| API keys | Password manager only |
| Passwords | Password manager only |
| Sensitive personal notes | StandardNotes or encrypted storage |
| Client/operational material | Separate encrypted container |
| Sensitive source documents | VeraCrypt, encrypted drive, or controlled storage |
| Final reports | Controlled export location |

Do not store API keys, passwords, client-sensitive raw notes, or operationally sensitive details directly in a normal Obsidian vault.

---

# Recommended Vault Structure

```text
PDA-Obsidian-Vault/
│
├── 00_Inbox/
├── 01_Dashboard/
├── 02_Projects/
├── 03_Areas/
├── 04_Resources/
├── 05_Reports/
├── 06_AI-Systems/
├── 07_Automations/
├── 08_Prompts/
├── 09_Templates/
├── 10_Archive/
└── _Attachments/
```

This structure is based on PARA, adapted for an AI operations ecosystem.

---

# Folder Definitions

## 00_Inbox

Temporary capture area.

Use this for:

- Raw notes
- Quick captures
- Pasted ideas
- Unprocessed links
- Meeting notes
- Draft thoughts
- Unsorted research
- Items that need clarification

Example:

```text
00_Inbox/
├── quick-capture.md
├── unsorted-links.md
├── raw-report-notes.md
└── ideas-to-process.md
```

Rule:

```text
Nothing should live permanently in the Inbox.
```

The Inbox supports the GTD capture step.

---

## 01_Dashboard

Command center for navigation, review, and execution.

Use this for:

- Active priorities
- Task lists
- Review notes
- Project status
- Personal operating dashboard
- Links to important vault areas

Recommended files:

```text
01_Dashboard/
├── Home.md
├── Active Projects.md
├── Next Actions.md
├── Waiting For.md
├── Someday Maybe.md
├── Weekly Review.md
├── Monthly Review.md
├── Quarterly OKRs.md
└── System Status.md
```

The Dashboard should answer:

```text
What am I working on?
What needs attention?
What is blocked?
What is next?
Where do I go?
```

---

## 02_Projects

Active, outcome-driven work.

A project is anything with a defined result and an end state.

Examples:

```text
02_Projects/
├── AI Tool Ecosystem/
├── Aegis Password Manager/
├── Report Writing System/
├── DFIR Career Package/
└── Local AI Assistant Stack/
```

Each project should have its own folder.

Recommended project folder structure:

```text
Project Name/
├── Project Overview.md
├── TCREI.md
├── Goals.md
├── Tasks.md
├── Decision Log.md
├── References.md
├── Working Notes.md
└── Archive/
```

For the current project:

```text
02_Projects/
└── AI Tool Ecosystem/
    ├── Project Overview.md
    ├── AI Ecosystem Architecture.md
    ├── Obsidian Vault Structure.md
    ├── Source Documents Index.md
    ├── Tool Evaluation Matrix.md
    ├── Automation Roadmap.md
    └── Implementation Roadmap.md
```

Projects should use TCREI for structure:

```markdown
# TCREI

## Task
What are we trying to accomplish?

## Context
What background, constraints, and environment details matter?

## References
What documents, tools, links, and prior decisions matter?

## Evaluate
How will quality, usefulness, or success be judged?

## Iterate
What is the next improvement cycle?
```

---

## 03_Areas

Long-term responsibilities and ongoing domains.

Areas do not have a fixed end date. They represent things to maintain over time.

Examples:

```text
03_Areas/
├── Productivity System/
├── Career Development/
├── Training and Certifications/
├── Cybersecurity/
├── Digital Privacy/
├── Leadership/
├── Home Lab/
└── AI Operations Ecosystem/
```

Use Areas for long-term responsibilities such as:

- Professional development
- Cybersecurity knowledge
- AI operations
- Personal privacy
- Leadership growth
- Training and certifications
- Home lab maintenance

---

## 04_Resources

Reference material and reusable knowledge.

Resources are not tied to a single active project. They are reusable.

Examples:

```text
04_Resources/
├── AI Tools/
├── Cybersecurity Concepts/
├── Writing and Analysis/
├── Physical Security/
├── OSINT/
├── Local LLMs/
├── Linux/
├── Docker/
├── n8n/
├── Obsidian/
└── Productivity Methods/
```

Recommended productivity method resource folder:

```text
04_Resources/
└── Productivity Methods/
    ├── PARA.md
    ├── GTD.md
    ├── Bullet Journal.md
    ├── Time Blocking.md
    ├── Eisenhower Matrix.md
    ├── Pomodoro.md
    ├── Zettelkasten.md
    ├── OKRs.md
    └── SMART Goals.md
```

Resources are where Zettelkasten-style knowledge notes should live.

---

## 05_Reports

Analytical and professional writing workspace.

Use this for:

- Draft reports
- Report templates
- Executive summaries
- Timelines
- Appendices
- Report components
- Lessons learned
- Export-ready writing

Recommended structure:

```text
05_Reports/
├── Templates/
├── Drafts/
├── Final/
├── Report Components/
├── Executive Summaries/
├── Timelines/
├── Appendices/
└── Lessons Learned/
```

Sensitive reports should not live in the general vault unless the storage environment is appropriate.

Recommended use:

```text
Draft in Obsidian.
Export to Word or PDF.
Store sensitive final products in controlled storage.
```

---

## 06_AI-Systems

Documentation for the AI operations environment.

Use this for:

- Local AI architecture
- Cloud AI tools
- Model notes
- API routing
- Prompt systems
- Security boundaries
- Tool configuration
- Integration plans

Recommended structure:

```text
06_AI-Systems/
├── Architecture/
├── Local LLMs/
├── Cloud AI/
├── LiteLLM/
├── Open WebUI/
├── Ollama/
├── SillyTavern/
├── Claude/
├── ChatGPT/
├── Gemini/
├── Perplexity/
├── Model Notes/
└── Security Boundaries/
```

This folder should document how the AI ecosystem works and why certain decisions were made.

---

## 07_Automations

Automation planning and documentation.

Use this for:

- n8n workflows
- API integrations
- automation ideas
- automation SOPs
- active automations
- failed experiments
- security review notes

Recommended structure:

```text
07_Automations/
├── n8n/
├── Workflow Ideas/
├── Active Workflows/
├── Failed Experiments/
├── API Integrations/
└── Automation SOPs/
```

Recommended automation note structure:

```markdown
# Automation Name

## Purpose
What does this automation do?

## Trigger
What starts it?

## Inputs
What information or files does it use?

## Process
What happens step by step?

## Outputs
What does it produce?

## Tools Used
What services, APIs, or local tools are involved?

## Security Concerns
What data exposure, permissions, or risks exist?

## Status
Idea, testing, active, paused, retired.

## Next Step
What needs to happen next?
```

---

## 08_Prompts

Reusable prompt library.

Use this for:

- Report writing prompts
- Research prompts
- Coding prompts
- Cybersecurity prompts
- Automation prompts
- TCREI prompts
- Model-specific prompts
- Prompt experiments

Recommended structure:

```text
08_Prompts/
├── TCREI Prompts/
├── Report Writing Prompts/
├── Research Prompts/
├── Coding Prompts/
├── Cybersecurity Prompts/
├── Automation Prompts/
├── Model-Specific Prompts/
└── Deprecated Prompts/
```

Recommended prompt note structure:

```markdown
# Prompt Name

## Purpose
What is this prompt for?

## Best Used With
Which model, workflow, or task type?

## Prompt
The reusable prompt text.

## Variables
Fields to customize.

## Notes
Known limitations, tips, or examples.

## Last Updated
Date of last revision.
```

---

## 09_Templates

Standardized note templates.

Templates keep the vault consistent and reduce friction.

Recommended structure:

```text
09_Templates/
├── Project Template.md
├── TCREI Template.md
├── Daily Note Template.md
├── Weekly Review Template.md
├── Monthly Review Template.md
├── OKR Template.md
├── SMART Goal Template.md
├── Zettelkasten Note Template.md
├── Tool Evaluation Template.md
├── Automation Template.md
├── Source Note Template.md
├── Meeting Notes Template.md
├── Report Template.md
└── Decision Log Template.md
```

This folder is central to making the system repeatable.

---

## 10_Archive

Inactive, completed, or deprecated material.

Use this for:

- Completed projects
- Paused projects
- Retired prompts
- Deprecated systems
- Old reports
- Superseded notes
- Historical reference

Recommended structure:

```text
10_Archive/
├── Completed Projects/
├── Paused Projects/
├── Deprecated Systems/
├── Old Reports/
├── Old Prompts/
└── Retired Notes/
```

Archive does not mean delete. It means inactive.

---

## _Attachments

Centralized storage for images, PDFs, screenshots, diagrams, and exports.

Recommended structure:

```text
_Attachments/
├── Images/
├── PDFs/
├── Screenshots/
├── Diagrams/
└── Exports/
```

Recommended Obsidian setting:

```text
Files & Links → Default location for new attachments → In the folder specified below
Attachment folder path → _Attachments
```

---

# Productivity System Integration

## PARA

PARA provides the main vault structure.

```text
Projects = active outcomes
Areas = ongoing responsibilities
Resources = reusable knowledge
Archives = inactive or completed material
```

Implementation:

```text
02_Projects/
03_Areas/
04_Resources/
10_Archive/
```

Use PARA to decide where notes belong.

---

## GTD

GTD manages task flow.

Core flow:

```text
Capture → Clarify → Organize → Review → Execute
```

Implementation:

```text
00_Inbox/ = Capture
01_Dashboard/Next Actions.md = Clarified tasks
01_Dashboard/Waiting For.md = Blocked/delegated items
01_Dashboard/Someday Maybe.md = Deferred ideas
Weekly Review.md = Reflect and reset
```

Recommended GTD files:

```text
01_Dashboard/
├── Next Actions.md
├── Waiting For.md
├── Someday Maybe.md
└── Weekly Review.md
```

---

## Bullet Journal

Bullet Journal principles support daily logging and task migration.

Use a simplified digital version.

Daily note template:

```markdown
# Daily Log - YYYY-MM-DD

## Focus
Main priority for the day.

## Tasks
- [ ] Task

## Events
- Event or appointment

## Notes
- Quick note or observation

## Migrated
- [>] Task moved forward

## Closed
- [x] Completed task
- [-] Canceled task
```

Recommended symbols:

```text
[ ] Task
[x] Done
[>] Migrated
[-] Canceled
[?] Needs clarification
[!] Important
```

Use Bullet Journal principles to track daily reality without overcomplicating the system.

---

## Time Blocking

Time Blocking belongs primarily on the calendar.

Use it to protect:

- Deep work
- Report writing
- Study blocks
- Project build sessions
- Weekly reviews
- Admin cleanup
- Fitness/training
- Planning sessions

Example:

```text
0900-1030 Deep Work: AI Ecosystem
1030-1100 Inbox Processing
1300-1430 Report Writing
1600-1630 Daily Review
```

Obsidian should track plans and reviews. The calendar should protect the time.

---

## Eisenhower Matrix

Use the Eisenhower Matrix when prioritizing tasks.

```text
Urgent + Important = Do now
Important + Not Urgent = Schedule
Urgent + Not Important = Delegate or minimize
Not Urgent + Not Important = Delete
```

Recommended file:

```text
01_Dashboard/Eisenhower Matrix.md
```

Use this during weekly review or when overloaded.

---

## Pomodoro

Pomodoro is an execution aid, not a planning system.

Use it for:

- Starting difficult work
- Maintaining focus
- Working through tedious tasks
- Tracking effort
- Building momentum

Example:

```text
4 Pomodoros = draft report section
2 Pomodoros = process inbox
3 Pomodoros = study technical topic
1 Pomodoro = clean project notes
```

Optional daily log entry:

```markdown
## Focus Sessions
- 2 Pomodoros - Report writing
- 1 Pomodoro - Inbox processing
- 3 Pomodoros - AI system documentation
```

---

## Zettelkasten

Zettelkasten supports long-term knowledge development.

Use it for:

- Cybersecurity concepts
- AI system design
- Automation patterns
- Report writing techniques
- Leadership lessons
- Tool comparisons
- Lessons learned

Recommended location:

```text
04_Resources/
```

Atomic note template:

```markdown
# Atomic Note Title

## Core Idea
One clear idea.

## Context
Where this applies.

## Links
- Related note
- Related concept

## Source
Where the idea came from.

## Application
How this could be used.
```

Guidelines:

```text
One idea per note.
Use clear titles.
Link related concepts.
Summarize in your own words.
Capture why the idea matters.
```

---

## OKRs

OKRs define strategic direction.

Use them monthly or quarterly.

Recommended file:

```text
01_Dashboard/Quarterly OKRs.md
```

Template:

```markdown
# OKRs - Quarter / Month

## Objective 1
Qualitative outcome.

### Key Results
- [ ] Measurable result
- [ ] Measurable result
- [ ] Measurable result

## Objective 2
Qualitative outcome.

### Key Results
- [ ] Measurable result
- [ ] Measurable result
- [ ] Measurable result
```

Example:

```markdown
## Objective
Build a functional AI operations ecosystem.

### Key Results
- [ ] Complete five source documents
- [ ] Stand up initial Obsidian vault structure
- [ ] Build tool evaluation matrix
- [ ] Document three reusable AI workflows
- [ ] Create first automation roadmap
```

---

## SMART Goals

SMART Goals make goals executable.

SMART means:

```text
Specific
Measurable
Achievable
Relevant
Time-bound
```

Bad goal:

```text
Learn more AI tools.
```

Better goal:

```text
By July 31, evaluate five AI tools using the tool evaluation matrix and select two tools for integration into the AI operations ecosystem.
```

Recommended use:

- Inside project notes
- Inside OKRs
- During weekly planning
- During project scoping

---

## TCREI

TCREI is the preferred structure for designing workflows, prompts, analytical products, automations, and projects.

```text
Task
Context
References
Evaluate
Iterate
```

Recommended use cases:

- Project planning
- Prompt design
- Report drafting
- Tool evaluation
- Automation design
- AI workflow creation
- Source document planning

Template:

```markdown
# TCREI

## Task
What are we trying to accomplish?

## Context
What background, constraints, and environment details matter?

## References
What documents, tools, sources, or previous decisions matter?

## Evaluate
How will success, accuracy, or usefulness be judged?

## Iterate
What should be improved in the next cycle?
```

---

# Recommended Operating Workflow

The full workflow:

```text
1. Capture everything into Inbox.
2. Clarify tasks using GTD.
3. Assign material to its PARA location.
4. Define goals using SMART Goals or OKRs.
5. Prioritize using the Eisenhower Matrix.
6. Schedule execution using Time Blocking.
7. Execute using Pomodoro when useful.
8. Log progress using Bullet Journal-style daily notes.
9. Convert durable lessons into Zettelkasten-style resource notes.
10. Review weekly and improve using TCREI.
```

Short version:

```text
Capture → Clarify → Organize → Prioritize → Schedule → Execute → Log → Learn → Review → Iterate
```

---

# Recommended Tags

Use folders for structure and tags for status, type, and domain.

Keep tags limited.

## Status Tags

```text
#status/active
#status/backlog
#status/paused
#status/complete
#status/waiting
#status/archived
```

## Type Tags

```text
#type/project
#type/resource
#type/prompt
#type/report
#type/template
#type/automation
#type/source
#type/decision
#type/meeting
```

## Domain Tags

```text
#domain/ai
#domain/cybersecurity
#domain/reporting
#domain/automation
#domain/privacy
#domain/local-llm
#domain/productivity
#domain/career
```

Avoid excessive tagging. Too many tags reduce usefulness.

---

# Naming Standards

Use clear, direct names.

Good:

```text
AI Ecosystem Architecture.md
Obsidian Vault Structure.md
Report Writing Workflow.md
n8n Automation Index.md
Local LLM Security Boundaries.md
```

Avoid:

```text
Stuff.md
AI Notes.md
Misc.md
New Note 12.md
Thoughts.md
```

Recommended format:

```text
Descriptive Title.md
```

Optional date-based notes:

```text
YYYY-MM-DD Daily Log.md
YYYY-MM Weekly Review.md
YYYY-MM Monthly Review.md
```

---

# Recommended Plugins

Start minimal.

## Core Obsidian Features

```text
Templates
Daily Notes
Backlinks
Graph View
File Recovery
```

## Optional Later

```text
Dataview
Tasks
Calendar
Templater
Excalidraw
Omnisearch
Advanced Tables
Kanban
```

Do not overload the vault with plugins before the structure is stable.

---

# Initial Implementation Checklist

## Phase 1: Create Folder Structure

```text
[ ] Create 00_Inbox
[ ] Create 01_Dashboard
[ ] Create 02_Projects
[ ] Create 03_Areas
[ ] Create 04_Resources
[ ] Create 05_Reports
[ ] Create 06_AI-Systems
[ ] Create 07_Automations
[ ] Create 08_Prompts
[ ] Create 09_Templates
[ ] Create 10_Archive
[ ] Create _Attachments
```

## Phase 2: Create Dashboard Files

```text
[ ] Home.md
[ ] Active Projects.md
[ ] Next Actions.md
[ ] Waiting For.md
[ ] Someday Maybe.md
[ ] Weekly Review.md
[ ] Monthly Review.md
[ ] Quarterly OKRs.md
[ ] System Status.md
```

## Phase 3: Create Core Templates

```text
[ ] Project Template.md
[ ] TCREI Template.md
[ ] Daily Note Template.md
[ ] Weekly Review Template.md
[ ] OKR Template.md
[ ] SMART Goal Template.md
[ ] Zettelkasten Note Template.md
[ ] Automation Template.md
[ ] Prompt Template.md
[ ] Decision Log Template.md
```

## Phase 4: Create Current Project Folder

```text
[ ] Create 02_Projects/AI Tool Ecosystem
[ ] Add Project Overview.md
[ ] Add AI Ecosystem Architecture.md
[ ] Add Obsidian Vault Structure.md
[ ] Add Source Documents Index.md
[ ] Add Tool Evaluation Matrix.md
[ ] Add Automation Roadmap.md
[ ] Add Implementation Roadmap.md
```

## Phase 5: Begin Weekly Review Habit

```text
[ ] Review Inbox
[ ] Update Next Actions
[ ] Update Waiting For
[ ] Review active projects
[ ] Review calendar/time blocks
[ ] Review OKRs
[ ] Archive inactive material
[ ] Identify next week’s top priorities
```

---

# Recommended Starting Rule

Start with structure, not plugins.

Start with workflows, not dashboards.

Start with useful templates, not aesthetic customization.

The first version of the vault should be simple, functional, and easy to maintain. Add complexity only after repeated use proves a need for it.

---

# Summary

This vault structure combines:

```text
PARA for organization
GTD for task flow
TCREI for structured thinking
OKRs for direction
SMART Goals for precision
Time Blocking for execution
Eisenhower for prioritization
Pomodoro for focus
Bullet Journal for daily tracking
Zettelkasten for long-term knowledge
```

The result is a practical operating system for productivity, project completion, learning, report writing, automation planning, and AI ecosystem development.
