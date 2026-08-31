# Step 15d — Council Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-model deliberation to COOPER — a planning-time critique panel that reviews a drafted job envelope before the owner approves it, and a tiered final-review step (council for L4+/file-writing jobs, single reviewer otherwise) whose verdicts land in the evidence record.

**Architecture:** New `cooper-core/council.py` module reusing `review.py`'s existing JSON-schema-constrained LLM-call pattern (same `_ollama_complete`/`_openai_complete` primitives from `decision.py`, same fail-open convention). `model_routing.py` gains a `council_roster(workshop)` lookup reading a new `council_roster` key in `Scripts/PDA_ModelRouting.json`. `jobs.py`'s `run_job()` calls the new tiered `council.final_review()` before writing evidence; a new `POST /jobs/critique/{job_id}` endpoint runs the planning-time `council.critique_envelope()` and writes its verdicts to an Obsidian inbox note — the owner's approval prompt for job envelopes, since jobs have no chat-based approval ticket (the owner still hand-flips `approved: true` in the YAML, same as today; the note is what they read first). `evidence.py` gains an optional `verdicts` field validator so completion records can carry named per-member verdicts without breaking any existing fixture.

**Tech Stack:** Python 3.12, FastAPI, `decision._ollama_complete`/`_openai_complete` (existing async LLM-call primitives), pytest, PyYAML.

**Spec:** `Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md` (§ decision record, target architecture diagram, slice table row for 15d, §7 rejected-and-recorded). Companion context: `PROGRESS.md`'s 2026-08-18 and 2026-08-30 entries, `Obsidian Vault/brain/North Star.md`'s M6 traceability note.

## Global Constraints

- **Mid-run council checkpoints are out of scope — explicitly rejected by the owner** (spec §7): "deliberation cannot outperform a hash check at boundary enforcement; cost is 10+ calls per checkpoint. Mechanisms enforce bounds; councils judge quality." Nothing in this plan adds a checkpoint inside `run_job`'s step loop.
- **Council members must be independent** — every member call runs concurrently (`asyncio.gather`), and no member sees another member's verdict. Anchoring one member on another's answer defeats the point of a panel.
- **Fail-open per member, same convention as `review.py`** — a broken council member returns `verdict="pass"` with the error in `reason`, never raises. This is safe because the panel's own rule is "any flag surfaces" (`has_objection`) — one silently-passing broken member doesn't suppress a real objection raised by any other member.
- **Private workshop has one real model** (`COOPER-Private`, aliased to `gemma4:e4b-it-qat` per Step 15c) — there is no local model diversity. G1 (2026-08-23, `PROGRESS.md:1264`) already decided Private does not get cloud-routed planning. This plan's `council_roster.private` therefore repeats `COOPER-Private` three times at varied temperatures (behavioral spread, not true model diversity) rather than fabricating a diverse local roster that doesn't exist. This is the documented, honest ceiling the spec's own M6 traceability note names: *"4–5: needs the gemma4:e4b-as-reviewer benchmark; if 4b review quality fails, honest ceiling is 4 (same-model review)."* Open's roster spans three distinct providers (OpenAI, Anthropic, Google via existing `litellm/litellm_config.yaml` aliases `openai`, `claude`, `gemini`) for genuine diversity.
- **Never flip `approved: true` on a real job entry as part of implementation or verification** — that flag is an owner-only governance decision (14b shipped the one real job, `link-checker`, inert on purpose). All live verification in Task 6 uses synthetic, throwaway job entries that are fully reverted afterward; `Config/jobs_registry.yaml`'s real `link-checker` entry is never touched.
- **Every behavior change lands with tests in the sibling `test_*.py`**; full suite (`cd cooper-core && .venv/bin/python -m pytest`) must pass before any task is called done.

---

### Task 1: `council_roster` lookup in `model_routing.py`

**Files:**
- Modify: `Scripts/PDA_ModelRouting.json`
- Modify: `cooper-core/model_routing.py`
- Test: `cooper-core/test_model_routing.py`

**Interfaces:**
- Produces: `model_routing.council_roster(workshop: str, routing: Optional[dict] = None) -> List[str]` — used by Task 2's `council.py`.

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_model_routing.py` (check the file's existing imports first — it already imports `model_routing` and uses a `SAMPLE_ROUTING`-style dict fixture per the existing `model_for` tests; add these alongside them):

```python
def test_council_roster_returns_configured_list_for_workshop():
    routing = {
        "roles": {},
        "council_roster": {"open": ["openai", "claude", "gemini"], "private": ["COOPER-Private"]},
    }
    assert model_routing.council_roster("open", routing) == ["openai", "claude", "gemini"]
    assert model_routing.council_roster("private", routing) == ["COOPER-Private"]


def test_council_roster_raises_for_unknown_workshop():
    routing = {"roles": {}, "council_roster": {"open": ["openai"]}}
    with pytest.raises(model_routing.ModelRoutingError):
        model_routing.council_roster("private", routing)


def test_council_roster_loads_from_real_routing_file():
    roster = model_routing.council_roster("open")
    assert len(roster) >= 3
    roster = model_routing.council_roster("private")
    assert len(roster) >= 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_model_routing.py -v -k council_roster`
Expected: FAIL with `AttributeError: module 'model_routing' has no attribute 'council_roster'`

- [ ] **Step 3: Add `council_roster` to `Scripts/PDA_ModelRouting.json`**

Add this key as a sibling of `"roles"` (after the closing `}` of `"roles"`, before the file's final closing `}`):

```json
  "council_roster": {
    "private": ["COOPER-Private", "COOPER-Private", "COOPER-Private"],
    "open": ["openai", "claude", "gemini"],
    "notes": "Step 15d. 3-5 diverse aliases per the spec. Private has one local model (G1, 2026-08-23: no cloud-routed planning on Private) so its roster repeats COOPER-Private at varied temperatures (council.py's _MEMBER_TEMPERATURES) for behavioral spread rather than true model diversity -- the documented honest ceiling per North Star's M6 traceability note ('if 4b review quality fails, honest ceiling is 4 -- same-model review'). Open's roster spans three distinct providers (OpenAI, Anthropic, Google) already configured in litellm/litellm_config.yaml."
  }
```

- [ ] **Step 4: Implement `council_roster` in `model_routing.py`**

Add `List` to the existing `from typing import Optional` import line (`from typing import List, Optional`), then append at the end of the file:

```python
def council_roster(workshop: str, routing: Optional[dict] = None) -> List[str]:
    """Resolve the council member roster for `workshop` ('private' or 'open')."""
    routing = routing if routing is not None else load_routing()
    rosters = routing.get("council_roster", {})
    if workshop not in rosters:
        raise ModelRoutingError(
            f"no council_roster mapping for workshop '{workshop}'"
        )
    return list(rosters[workshop])
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_model_routing.py -v`
Expected: PASS, all tests including the three new ones.

- [ ] **Step 6: Commit**

```bash
git add Scripts/PDA_ModelRouting.json cooper-core/model_routing.py cooper-core/test_model_routing.py
git commit -m "feat(routing): add council_roster(workshop) lookup (15d)"
```

---

### Task 2: `council.py` — verdict primitives, planning-time critique, tiering

**Files:**
- Create: `cooper-core/council.py`
- Test: `cooper-core/test_council.py`

**Interfaces:**
- Consumes: `model_routing.council_roster(workshop)` (Task 1); `decision._ollama_complete`, `decision._openai_complete` (existing); `review.review(tool, message, raw_output, *, base_url, api_key, model, backend) -> review.ReviewVerdict` (existing, used by the single-reviewer tier).
- Produces (for Task 4/5):
  - `council.CouncilVerdict` dataclass: `member: str`, `verdict: str`, `reason: str`
  - `async def council.critique_envelope(job_entry: dict, workshop: str, *, base_url: str, api_key: str, backend: str, roster: Optional[List[str]] = None) -> List[CouncilVerdict]`
  - `def council.has_objection(verdicts: List[CouncilVerdict]) -> bool`
  - `def council.needs_council_tier(job_entry: dict) -> bool`
  - `def council.verdicts_to_dicts(verdicts: List[CouncilVerdict]) -> List[dict]`
  - `async def council.final_review(job_entry: dict, workshop: str, message: str, raw_output: str, *, base_url: str, api_key: str, backend: str, reviewer_model: str, roster: Optional[List[str]] = None) -> List[dict]`

- [ ] **Step 1: Write the failing tests**

Create `cooper-core/test_council.py`:

```python
import asyncio

import council
import review


JOB = {
    "id": "test-job",
    "workshop": "open",
    "steps": ["noop"],
    "read_scope": [],
    "write_scope": [],
    "quota": {"rows_per_run": 1},
    "permission_level": 3,
    "approved": False,
}


def test_needs_council_tier_true_for_l4_plus():
    assert council.needs_council_tier({**JOB, "permission_level": 4, "write_scope": []})


def test_needs_council_tier_true_for_file_writing_below_l4():
    assert council.needs_council_tier({**JOB, "permission_level": 3, "write_scope": ["a.csv"]})


def test_needs_council_tier_false_for_low_level_no_write():
    assert not council.needs_council_tier({**JOB, "permission_level": 3, "write_scope": []})


def test_has_objection_true_if_any_member_flags():
    verdicts = [
        council.CouncilVerdict(member="a", verdict="pass", reason=""),
        council.CouncilVerdict(member="b", verdict="flag", reason="too broad"),
    ]
    assert council.has_objection(verdicts)


def test_has_objection_false_if_all_pass():
    verdicts = [council.CouncilVerdict(member="a", verdict="pass", reason="")]
    assert not council.has_objection(verdicts)


def test_verdicts_to_dicts_shape():
    verdicts = [council.CouncilVerdict(member="a", verdict="flag", reason="why")]
    assert council.verdicts_to_dicts(verdicts) == [
        {"member": "a", "verdict": "flag", "reason": "why"}
    ]


def test_member_verdict_fails_open_and_logs(monkeypatch, capsys):
    async def boom(*a, **k):
        raise RuntimeError("network down")

    monkeypatch.setattr(council, "_ollama_complete", boom)
    result = asyncio.run(council._member_verdict(
        "system", "user", "some-model",
        base_url="http://x", api_key="", backend="ollama", temperature=0.0,
    ))
    assert result.verdict == "pass"
    assert "fail-open" in result.reason
    assert "fail-open" in capsys.readouterr().out


def test_critique_envelope_runs_each_roster_member(monkeypatch):
    calls = []

    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        calls.append(member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake)
    verdicts = asyncio.run(council.critique_envelope(
        JOB, "open", base_url="http://x", api_key="", backend="openai",
        roster=["m1", "m2", "m3"],
    ))
    assert sorted(calls) == ["m1", "m2", "m3"]
    assert [v.member for v in verdicts] == ["m1", "m2", "m3"]


def test_critique_envelope_surfaces_objection_from_seeded_flaw(monkeypatch):
    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        # simulate one member catching an over-broad write_scope mentioned in the envelope
        verdict = "flag" if "write_scope" in user_msg and "/" in user_msg else "pass"
        return council.CouncilVerdict(member=member, verdict=verdict, reason="over-broad write_scope")

    monkeypatch.setattr(council, "_member_verdict", fake)
    flawed = {**JOB, "write_scope": ["/"]}
    verdicts = asyncio.run(council.critique_envelope(
        flawed, "open", base_url="http://x", api_key="", backend="openai",
        roster=["m1", "m2", "m3"],
    ))
    assert council.has_objection(verdicts)


def test_final_review_uses_council_tier_for_file_writing_job(monkeypatch):
    calls = []

    async def fake(system, user_msg, member, *, base_url, api_key, backend, temperature):
        calls.append(member)
        return council.CouncilVerdict(member=member, verdict="pass", reason="ok")

    monkeypatch.setattr(council, "_member_verdict", fake)
    job = {**JOB, "permission_level": 3, "write_scope": ["a.csv"]}
    result = asyncio.run(council.final_review(
        job, "open", "job run: test-job", "ran fine",
        base_url="http://x", api_key="", backend="openai", reviewer_model="rev",
        roster=["m1", "m2", "m3"],
    ))
    assert len(result) == 3
    assert {r["member"] for r in result} == {"m1", "m2", "m3"}
    assert all(r["verdict"] == "pass" for r in result)


def test_final_review_uses_single_reviewer_for_low_tier_job(monkeypatch):
    async def fake_review(tool, message, raw_output, *, base_url, api_key, model, backend):
        return review.ReviewVerdict(verdict="pass", reason="looks fine")

    monkeypatch.setattr(review, "review", fake_review)
    job = {**JOB, "permission_level": 3, "write_scope": []}
    result = asyncio.run(council.final_review(
        job, "open", "job run: test-job", "ran fine",
        base_url="http://x", api_key="", backend="openai", reviewer_model="rev",
    ))
    assert result == [{"member": "rev", "verdict": "pass", "reason": "looks fine"}]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_council.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'council'`

- [ ] **Step 3: Implement `cooper-core/council.py`**

```python
"""
COOPER Council -- multi-model deliberation subsystem (Step 15d).

Two tiers, per the spec (Docs/superpowers/specs/2026-08-18-step-15-max-metrics-design.md):
  Planning-time -- critique_envelope(): every council member independently
    critiques a drafted job envelope before the owner approves it. Any
    member's objection surfaces to the owner (dissents are never silently
    outvoted -- see has_objection).
  Final review  -- final_review(): tiered. needs_council_tier() jobs (L4+ or
    file-writing) get the full council; everything else gets review.py's
    existing single reviewer. Mechanisms (jobs.py's envelope hash + quotas +
    exception queue) still enforce bounds; councils only judge quality --
    mid-run council checkpoints were explicitly rejected (spec section 7).

Same fail-open convention as review.py: a broken council member must never
block a legitimate result on its own. Fail-open only costs one member's
vote -- council's any-flag rule (has_objection) means a live objection from
any other member still surfaces.
"""
import asyncio
import json
from dataclasses import dataclass
from typing import List, Optional

from decision import _ollama_complete, _openai_complete
import model_routing
import review

_CRITIQUE_SYSTEM = """\
You are one member of COOPER's planning-time Council. A job envelope is \
proposed below, drafted but not yet approved by the human owner. Check it \
for governance problems before it reaches the owner's approval prompt.

FLAG if: write_scope or read_scope is broader than the job's stated purpose \
needs, permission_level looks too low for what the steps actually do, quota \
looks unbounded or unreasonable, or any step could act outside what the \
envelope declares.

PASS if the envelope's scope, permission level, and quota all look \
proportionate to its steps.

Output JSON only -- no other text.
{"verdict":"pass"|"flag","reason":"<brief phrase>"}\
"""

_FINAL_REVIEW_SYSTEM = """\
You are one member of COOPER's final-review Council. A job run just \
completed; its summary is below. Check it before it reaches the evidence \
record.

FLAG if the summary shows a failed/refused write, an exception raised, a \
quota breach, or output that plainly did not accomplish the job's purpose.

PASS if the summary looks like normal, successful completion.

Output JSON only -- no other text.
{"verdict":"pass"|"flag","reason":"<brief phrase>"}\
"""

VALID_VERDICTS = frozenset({"pass", "flag"})
_MEMBER_TEMPERATURES = [0.0, 0.4, 0.8]
_MAX_TEXT_FOR_REVIEW = 4000


@dataclass
class CouncilVerdict:
    member: str
    verdict: str  # "pass" | "flag"
    reason: str


async def _member_verdict(
    system_prompt: str,
    user_msg: str,
    member: str,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    temperature: float,
) -> CouncilVerdict:
    """One council member's JSON-schema-constrained verdict call. Fails open
    (pass) on any error -- same convention as review.review()."""
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_msg},
    ]
    try:
        if backend == "openai":
            raw = await _openai_complete(
                base_url, api_key, member, messages,
                temperature=temperature,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "council_verdict",
                        "strict": True,
                        "schema": {
                            "type": "object",
                            "properties": {
                                "verdict": {"type": "string", "enum": ["pass", "flag"]},
                                "reason":  {"type": "string"},
                            },
                            "required": ["verdict", "reason"],
                            "additionalProperties": False,
                        },
                    },
                },
            )
        else:
            raw = await _ollama_complete(
                base_url, member, messages,
                options={"temperature": temperature},
                fmt={
                    "type": "object",
                    "properties": {
                        "verdict": {"type": "string", "enum": ["pass", "flag"]},
                        "reason":  {"type": "string"},
                    },
                    "required": ["verdict", "reason"],
                },
            )
        data = json.loads(raw)
        verdict = data.get("verdict", "pass")
        if verdict not in VALID_VERDICTS:
            verdict = "pass"
        return CouncilVerdict(member=member, verdict=verdict, reason=data.get("reason", ""))
    except Exception as exc:
        print(f"  [!!] council member '{member}' fail-open: {exc}")
        return CouncilVerdict(
            member=member, verdict="pass",
            reason=f"council member error (fail-open): {exc}",
        )


async def critique_envelope(
    job_entry: dict,
    workshop: str,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    roster: Optional[List[str]] = None,
) -> List[CouncilVerdict]:
    """Planning-time critique: every roster member independently reviews the
    drafted envelope, concurrently -- members don't see each other's
    verdicts (independence is the point)."""
    members = roster if roster is not None else model_routing.council_roster(workshop)
    envelope_json = json.dumps(
        {k: v for k, v in job_entry.items() if k != "envelope_hash"},
        sort_keys=True,
    )[:_MAX_TEXT_FOR_REVIEW]
    user_msg = f"Proposed job envelope:\n{envelope_json}"
    calls = [
        _member_verdict(
            _CRITIQUE_SYSTEM, user_msg, member,
            base_url=base_url, api_key=api_key, backend=backend,
            temperature=_MEMBER_TEMPERATURES[i % len(_MEMBER_TEMPERATURES)],
        )
        for i, member in enumerate(members)
    ]
    return list(await asyncio.gather(*calls))


def has_objection(verdicts: List[CouncilVerdict]) -> bool:
    """True if any member flagged. Dissent is never outvoted -- one flag is
    enough for the envelope to need the owner's attention."""
    return any(v.verdict == "flag" for v in verdicts)


def needs_council_tier(job_entry: dict) -> bool:
    """Final review is council-tier if the job is L4+ or writes files;
    everything else gets review.py's single reviewer."""
    return int(job_entry.get("permission_level", 0)) >= 4 or bool(job_entry.get("write_scope"))


def verdicts_to_dicts(verdicts: List[CouncilVerdict]) -> List[dict]:
    return [{"member": v.member, "verdict": v.verdict, "reason": v.reason} for v in verdicts]


async def final_review(
    job_entry: dict,
    workshop: str,
    message: str,
    raw_output: str,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    reviewer_model: str,
    roster: Optional[List[str]] = None,
) -> List[dict]:
    """Tiered final review over a job run's output. Council tier for L4+ /
    file-writing jobs (every member named); single reviewer otherwise,
    wrapped in the same {"member","verdict","reason"} shape so callers (and
    the evidence schema) see one uniform list regardless of tier."""
    if needs_council_tier(job_entry):
        members = roster if roster is not None else model_routing.council_roster(workshop)
        user_msg = f"Job: {message}\nRun summary:\n{raw_output[:_MAX_TEXT_FOR_REVIEW]}"
        calls = [
            _member_verdict(
                _FINAL_REVIEW_SYSTEM, user_msg, member,
                base_url=base_url, api_key=api_key, backend=backend,
                temperature=_MEMBER_TEMPERATURES[i % len(_MEMBER_TEMPERATURES)],
            )
            for i, member in enumerate(members)
        ]
        verdicts = list(await asyncio.gather(*calls))
        return verdicts_to_dicts(verdicts)

    verdict = await review.review(
        {"name": job_entry.get("id", "job")}, message, raw_output,
        base_url=base_url, api_key=api_key, model=reviewer_model, backend=backend,
    )
    return [{"member": reviewer_model, "verdict": verdict.verdict, "reason": verdict.reason}]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_council.py -v`
Expected: PASS, all 11 tests.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/council.py cooper-core/test_council.py
git commit -m "feat(council): add critique_envelope + tiered final_review (15d)"
```

---

### Task 3: `evidence.py` — optional `verdicts` field validation

**Files:**
- Modify: `cooper-core/evidence.py`
- Test: `cooper-core/test_evidence.py`

**Interfaces:**
- Consumes: nothing new from other tasks (pure schema addition).
- Produces: `evidence.validate_completion(record, context)` now also validates an optional `record["verdicts"]` field, shaped `[{"member": str, "verdict": "pass"|"flag", "reason": str}, ...]`. Existing required-field validation is unchanged; a record with no `verdicts` key is unaffected.

- [ ] **Step 1: Write the failing tests**

Append to `cooper-core/test_evidence.py` (it already has a `_COMPLETION_REQUIRED`-shaped minimal record helper pattern per its existing `test_job_linked_*` tests — build the same way: start from a valid completion dict and mutate):

```python
def _valid_completion(**overrides):
    record = {
        "workflow_id": "wf-1", "workflow_name": "Test", "execution_id": "exec-1",
        "status": "completed", "completion_time": "2026-08-31T00:00:00.000000Z",
        "workshop_id": "open", "workshop_name": "Open Workshop", "approval_id": "",
        "artifact_paths": [], "review_status": "unknown", "user_accepted": False,
        "job_id": "test-job", "envelope_hash": "abc123", "run_id": "run-1",
    }
    record.update(overrides)
    return record


def test_verdicts_field_absent_is_valid():
    record = _valid_completion()
    assert evidence.validate_completion(record, []) == []


def test_verdicts_field_valid_when_well_shaped():
    record = _valid_completion(verdicts=[
        {"member": "openai", "verdict": "pass", "reason": "looks fine"},
        {"member": "claude", "verdict": "flag", "reason": "quota concern"},
    ])
    assert evidence.validate_completion(record, []) == []


def test_verdicts_field_rejects_empty_list():
    record = _valid_completion(verdicts=[])
    errs = evidence.validate_completion(record, [])
    assert any("verdicts" in e for e in errs)


def test_verdicts_field_rejects_missing_subfield():
    record = _valid_completion(verdicts=[{"member": "openai", "verdict": "pass"}])
    errs = evidence.validate_completion(record, [])
    assert any("reason" in e for e in errs)


def test_verdicts_field_rejects_invalid_verdict_value():
    record = _valid_completion(verdicts=[{"member": "openai", "verdict": "maybe", "reason": "x"}])
    errs = evidence.validate_completion(record, [])
    assert any("verdict" in e for e in errs)


def test_verdicts_field_hygiene_checks_reason_text():
    record = _valid_completion(verdicts=[
        {"member": "openai", "verdict": "flag", "reason": "found api_key=sk-abc123 in output"}
    ])
    errs = evidence.validate_completion(record, [])
    assert any("hygiene" in e for e in errs)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cooper-core && .venv/bin/python -m pytest test_evidence.py -v -k verdicts`
Expected: FAIL — `test_verdicts_field_rejects_empty_list`, `_rejects_missing_subfield`, `_rejects_invalid_verdict_value`, and `_hygiene_checks_reason_text` all fail (no errors returned) because the field isn't validated yet; the "absent" and "valid" tests may already pass since extra fields already pass through untouched.

- [ ] **Step 3: Implement the validator in `evidence.py`**

Add after `_JOB_LINKAGE_REQUIRED = {"job_id": str, "envelope_hash": str, "run_id": str}`:

```python
_VERDICT_ITEM_REQUIRED = {"member": str, "verdict": str, "reason": str}
_VALID_VERDICT_VALUES = {"pass", "flag"}
```

Add a new function after `_sensitive_errors`:

```python
def _verdicts_errors(record: dict) -> List[str]:
    """Optional field: when present, 'verdicts' must be a non-empty list of
    {"member","verdict","reason"} dicts with verdict in {"pass","flag"}.
    Hygiene applies to each member's reason text too -- an LLM verdict is
    still untrusted input."""
    if "verdicts" not in record:
        return []
    verdicts = record["verdicts"]
    if not isinstance(verdicts, list) or not verdicts:
        return ["schema: field 'verdicts' must be a non-empty list"]
    errs: List[str] = []
    for i, item in enumerate(verdicts):
        if not isinstance(item, dict):
            errs.append(f"schema: verdicts[{i}] is not an object")
            continue
        errs += [f"schema: verdicts[{i}].{e}" for e in _schema_errors(item, _VERDICT_ITEM_REQUIRED)]
        if item.get("verdict") not in _VALID_VERDICT_VALUES:
            errs.append(f"schema: verdicts[{i}].verdict must be 'pass' or 'flag'")
        reason = item.get("reason")
        if isinstance(reason, str) and _SENSITIVE_RE.search(reason):
            errs.append(f"hygiene: sensitive marker in verdicts[{i}].reason")
    return errs
```

In `validate_completion`, immediately after the existing `errs += _sensitive_errors(record)` line, add:

```python
    errs += _verdicts_errors(record)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cooper-core && .venv/bin/python -m pytest test_evidence.py -v`
Expected: PASS, all tests including the six new ones and all pre-existing fixture-driven tests.

- [ ] **Step 5: Commit**

```bash
git add cooper-core/evidence.py cooper-core/test_evidence.py
git commit -m "feat(evidence): validate optional per-member verdicts field (15d)"
```

---

### Task 4: Wire tiered `final_review` into `run_job` + evidence write

**Files:**
- Modify: `cooper-core/jobs.py`
- Modify: `cooper-core/main.py`
- Test: `cooper-core/test_jobs.py`, `cooper-core/test_main_jobs.py`

**Interfaces:**
- Consumes: `council.final_review(...)` (Task 2), `evidence.py`'s new optional field (Task 3, exercised implicitly).
- Produces: `jobs.write_job_evidence(..., verdicts: List[dict])` (new required param); `jobs.run_job(job_id, conn, *, base_url, api_key, backend, workshop, reviewer_model, registry_path=None)` (five new required keyword params); every completed job run's evidence record now has a `verdicts` field.

- [ ] **Step 1: Update `write_job_evidence` — write the failing test first**

Add to `cooper-core/test_jobs.py` near the existing evidence-related assertions (after `_approved_job`/`_write_links_csv` helpers, before the `run_job` test section):

```python
def test_write_job_evidence_includes_verdicts():
    job_entry = _approved_job()
    verdicts = [{"member": "openai", "verdict": "pass", "reason": "ok"}]
    path = jobs.write_job_evidence(
        job_id="link-checker", run_id="run-1", job_entry=job_entry,
        status="completed", artifact_paths=["State/LinkAudit/links.csv"],
        notes="test run", verdicts=verdicts,
    )
    record = json.loads(path.read_text(encoding="utf-8"))
    assert record["verdicts"] == verdicts
    path.unlink()
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v -k write_job_evidence_includes_verdicts`
Expected: FAIL — `TypeError: write_job_evidence() got an unexpected keyword argument 'verdicts'`

- [ ] **Step 2: Add `verdicts` to `write_job_evidence`**

In `cooper-core/jobs.py`, change the `write_job_evidence` signature and body:

```python
def write_job_evidence(
    job_id: str,
    run_id: str,
    job_entry: dict,
    status: str,
    artifact_paths: List[str],
    notes: str,
    verdicts: List[dict],
) -> Path:
```

In the `record = {...}` dict inside that function, add a new key (anywhere after `"run_id": run_id,` is fine):

```python
        "run_id": run_id,
        "verdicts": verdicts,
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v -k write_job_evidence_includes_verdicts`
Expected: PASS

- [ ] **Step 3: Update `run_job`'s signature and call site — write the failing tests first**

Add a shared fake at the top of `cooper-core/test_jobs.py`, right after the existing `import jobs` line:

```python
import council


async def _fake_final_review(*a, **k):
    return [{"member": "test-reviewer", "verdict": "pass", "reason": "ok"}]


_RUN_JOB_KWARGS = dict(
    base_url="http://test", api_key="test-key", backend="ollama",
    workshop="open", reviewer_model="test-reviewer-model",
)
```

Now update every existing call to `jobs.run_job(...)` in the file to (a) pass `**_RUN_JOB_KWARGS` and (b) monkeypatch `jobs.council.final_review` in tests that reach the "completed" path (the two "refused" tests don't reach final review, so they don't need the monkeypatch — but passing the kwargs is harmless and keeps every call site uniform). Rewrite these five test functions in full:

```python
def test_run_job_refuses_unapproved_job(conn, tmp_path, monkeypatch):
    registry = {"jobs": [{**MINIMAL_JOB, "approved": False, "id": "link-checker"}]}
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: registry)
    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))
    assert result["status"] == "refused"
    assert "not approved" in result["reason"].lower()


def test_run_job_refuses_unknown_job_id(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": []})
    result = asyncio.run(jobs.run_job("does-not-exist", conn, **_RUN_JOB_KWARGS))
    assert result["status"] == "refused"


def test_run_job_enqueues_exception_for_out_of_scope_write(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])
    on_disk_before = csv_path.read_text()

    job_entry = _approved_job(write_scope=["State/LinkAudit/other.csv"])
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify())

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["exceptions_raised"] == 1
    pending = jobs.list_exceptions(conn, status="pending")
    assert len(pending) == 1
    assert pending[0]["job_id"] == "link-checker"
    assert csv_path.read_text() == on_disk_before


def test_run_job_full_success_writes_csv_and_evidence(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
    ])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2
    assert result["exceptions_raised"] == 0
    assert jobs.list_exceptions(conn, status="pending") == []

    updated = csv_path.read_text()
    assert "url,last_checked,status,notes" in updated
    assert ",,,\n" not in updated

    evidence_path = Path(result["evidence_path"])
    assert evidence_path.exists()
    record = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert record["job_id"] == "link-checker"
    assert record["run_id"] == result["run_id"]
    assert record["envelope_hash"] == job_entry["envelope_hash"]
    assert record["verdicts"] == [{"member": "test-reviewer", "verdict": "pass", "reason": "ok"}]
    errs = evidence.validate_completion(record, [])
    assert errs == []


def test_run_job_respects_rows_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 2, "fetches_per_run": 30})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 2

    updated = csv_path.read_text()
    assert "https://c.example,,," in updated.replace("\r", "")


def test_run_job_caps_fetches_at_fetches_per_run_quota(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(jobs.council, "final_review", _fake_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [
        ("https://a.example", "", "", ""),
        ("https://b.example", "", "", ""),
        ("https://c.example", "", "", ""),
    ])

    job_entry = _approved_job(quota={"rows_per_run": 10, "fetches_per_run": 1})
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    assert result["status"] == "completed"
    assert result["rows_checked"] == 1
```

Also add one new test proving the council tier actually names multiple members end to end (append after the rewritten `test_run_job_full_success_writes_csv_and_evidence`):

```python
def test_run_job_council_tier_produces_named_per_member_verdicts(conn, tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)

    async def fake_council_final_review(job_entry, workshop, message, raw_output, **kw):
        assert council.needs_council_tier(job_entry)  # link-checker writes files -> council tier
        return [
            {"member": "openai", "verdict": "pass", "reason": "ok"},
            {"member": "claude", "verdict": "pass", "reason": "ok"},
            {"member": "gemini", "verdict": "pass", "reason": "ok"},
        ]

    monkeypatch.setattr(jobs.council, "final_review", fake_council_final_review)
    csv_path = tmp_path / "State" / "LinkAudit" / "links.csv"
    _write_links_csv(csv_path, [("https://a.example", "", "", "")])

    job_entry = _approved_job()
    monkeypatch.setattr(jobs, "load_registry", lambda path=None: {"jobs": [job_entry]})
    monkeypatch.setattr(jobs, "url_verify", _fake_url_verify(reachable=True))

    result = asyncio.run(jobs.run_job("link-checker", conn, **_RUN_JOB_KWARGS))

    record = json.loads(Path(result["evidence_path"]).read_text(encoding="utf-8"))
    assert len(record["verdicts"]) == 3
    assert {v["member"] for v in record["verdicts"]} == {"openai", "claude", "gemini"}
    errs = evidence.validate_completion(record, [])
    assert errs == []
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v`
Expected: FAIL — every `run_job(...)` call raises `TypeError: run_job() got an unexpected keyword argument 'base_url'` (signature not updated yet).

- [ ] **Step 4: Update `run_job` in `cooper-core/jobs.py`**

Add `import council` near the top of `jobs.py`, alongside `import executor`.

Change the `run_job` signature:

```python
async def run_job(
    job_id: str,
    conn: sqlite3.Connection,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    workshop: str,
    reviewer_model: str,
    registry_path: Optional[Path] = None,
) -> dict:
```

Immediately before the existing `evidence_path = write_job_evidence(` call, insert:

```python
    verdicts = await council.final_review(
        job_entry, workshop, f"job run: {job_id}", notes,
        base_url=base_url, api_key=api_key, backend=backend, reviewer_model=reviewer_model,
    )
```

Then update the `write_job_evidence(...)` call to pass it through — add `verdicts=verdicts,` as a new argument in that call.

- [ ] **Step 5: Update `main.py`'s `POST /jobs/run/{job_id}` endpoint**

In `cooper-core/main.py`, change:

```python
    result = await jobs.run_job(job_id, _ARCHIVIST_CONN)
```

to:

```python
    result = await jobs.run_job(
        job_id, _ARCHIVIST_CONN,
        base_url=BACKEND_URL, api_key=BACKEND_KEY, backend=BACKEND,
        workshop=WORKSHOP, reviewer_model=REVIEWER_MODEL,
    )
```

- [ ] **Step 6: Fix `test_main_jobs.py`'s stub — it monkeypatches `jobs.run_job` itself**

`test_main_jobs.py`'s `test_post_jobs_run_returns_run_job_result` replaces `main.jobs.run_job` with its own `fake_run_job(job_id, conn)` stub, called from inside `main.py`'s endpoint — so it must accept the five new keyword arguments `main.py` now passes, or the call raises `TypeError: fake_run_job() got an unexpected keyword argument 'base_url'`. Update that one function's signature (nothing else in the file changes — `test_post_jobs_run_404s_for_unknown_job` and `test_post_jobs_run_requires_auth` never reach the `run_job` call):

```python
    async def fake_run_job(job_id, conn, **kwargs):
        assert job_id == "link-checker"
        assert conn is main._ARCHIVIST_CONN
        assert kwargs == {
            "base_url": main.BACKEND_URL, "api_key": main.BACKEND_KEY,
            "backend": main.BACKEND, "workshop": main.WORKSHOP,
            "reviewer_model": main.REVIEWER_MODEL,
        }
        return {
            "status": "completed",
            "run_id": "abc123",
            "rows_checked": 2,
            "rows_changed": 0,
            "exceptions_raised": 0,
            "fetches_used": 2,
            "fetches_capped": False,
            "evidence_path": "/tmp/fake.json",
        }
```

- [ ] **Step 7: Run the full suite to verify everything passes**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`
Expected: PASS, all tests.

- [ ] **Step 8: Commit**

```bash
git add cooper-core/jobs.py cooper-core/main.py cooper-core/test_jobs.py cooper-core/test_main_jobs.py
git commit -m "feat(jobs): wire tiered council.final_review into run_job (15d)"
```

---

### Task 5: Planning-time critique endpoint + owner-facing note

**Files:**
- Modify: `cooper-core/jobs.py`
- Modify: `cooper-core/main.py`
- Test: `cooper-core/test_jobs.py`, `cooper-core/test_main_jobs.py`

**Interfaces:**
- Consumes: `council.critique_envelope`, `council.has_objection`, `council.verdicts_to_dicts` (Task 2).
- Produces: `jobs.write_critique_note(job_id: str, verdict_dicts: List[dict]) -> Path`; `POST /jobs/critique/{job_id}` returning `{"job_id", "objection", "verdicts", "note_path"}`.

- [ ] **Step 1: Write the failing test for `write_critique_note`**

Add to `cooper-core/test_jobs.py`:

```python
def test_write_critique_note_reports_objection(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    verdicts = [
        {"member": "openai", "verdict": "pass", "reason": "looks fine"},
        {"member": "claude", "verdict": "flag", "reason": "write_scope too broad"},
    ]
    path = jobs.write_critique_note("test-job", verdicts)
    assert path.exists()
    text = path.read_text(encoding="utf-8")
    assert "test-job" in text
    assert "OBJECTION" in text
    assert "claude" in text and "write_scope too broad" in text


def test_write_critique_note_reports_clear_when_all_pass(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs, "_DIGEST_DIR", tmp_path / "inbox")
    verdicts = [{"member": "openai", "verdict": "pass", "reason": "fine"}]
    path = jobs.write_critique_note("test-job", verdicts)
    text = path.read_text(encoding="utf-8")
    assert "clear" in text.lower()
    assert "OBJECTION" not in text
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v -k write_critique_note`
Expected: FAIL — `AttributeError: module 'jobs' has no attribute 'write_critique_note'`

- [ ] **Step 2: Implement `write_critique_note` in `cooper-core/jobs.py`**

Add near `write_digest` (same file, same `_DIGEST_DIR` constant):

```python
def write_critique_note(job_id: str, verdicts: List[dict]) -> Path:
    """Write the planning-time council's critique to the Obsidian inbox --
    the owner's approval prompt for job envelopes. There's no chat-based
    approval ticket for job entries (unlike tool calls); the owner reads
    this note, then hand-flips 'approved: true' in
    Config/jobs_registry.yaml themselves, same as today. One file per job id
    -- a re-critique overwrites the prior note so the owner always sees the
    current envelope's critique, never a stale one."""
    objections = [v for v in verdicts if v.get("verdict") == "flag"]
    lines = [f"# Council Critique -- job `{job_id}`", ""]
    lines.append(
        f"## Verdict: {'OBJECTION' if objections else 'clear'} "
        f"({len(objections)}/{len(verdicts)} flagged)"
    )
    lines.append("")
    for v in verdicts:
        lines.append(f"- **{v.get('member')}**: {v.get('verdict')} -- {v.get('reason')}")
    lines.append("")
    text = "\n".join(lines).rstrip() + "\n"

    _DIGEST_DIR.mkdir(parents=True, exist_ok=True)
    out_path = _DIGEST_DIR / f"COOPER-Job-Critique-{job_id}.md"
    out_path.write_text(text, encoding="utf-8")
    return out_path
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_jobs.py -v -k write_critique_note`
Expected: PASS

- [ ] **Step 3: Write the failing test for the endpoint**

`test_main_jobs.py` has no `client`/`AUTH_HEADERS` fixtures — every test disables auth per-call via `monkeypatch.setattr(main, "_API_KEYS", set())` / `monkeypatch.setattr(main, "_ALLOW_ANON", True)` and opens its own `with TestClient(main.app) as client:` block (see `test_post_jobs_run_returns_run_job_result`). Add `from pathlib import Path` to the file's imports if not already present, then follow that exact same pattern:

```python
def test_critique_endpoint_returns_objection_and_writes_note(monkeypatch, tmp_path):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "_DIGEST_DIR", tmp_path / "inbox")
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: {
        "id": job_id, "workshop": "open", "permission_level": 3,
        "write_scope": ["/"], "read_scope": [], "quota": {}, "approved": False,
    })

    async def fake_critique_envelope(job_entry, workshop, **kw):
        return [
            main.council.CouncilVerdict(member="openai", verdict="pass", reason="ok"),
            main.council.CouncilVerdict(member="claude", verdict="flag", reason="write_scope is repo-wide"),
        ]

    monkeypatch.setattr(main.council, "critique_envelope", fake_critique_envelope)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/critique/test-job")

    assert resp.status_code == 200
    body = resp.json()
    assert body["objection"] is True
    assert len(body["verdicts"]) == 2
    assert Path(body["note_path"]).exists()


def test_critique_endpoint_404s_for_unknown_job(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", set())
    monkeypatch.setattr(main, "_ALLOW_ANON", True)
    monkeypatch.setattr(main.jobs, "get_job", lambda job_id, registry=None: None)

    with TestClient(main.app) as client:
        resp = client.post("/jobs/critique/nonexistent")

    assert resp.status_code == 404
```

Run: `cd cooper-core && .venv/bin/python -m pytest test_main_jobs.py -v -k critique`
Expected: FAIL — 404/`AttributeError` since the route and `main.council` don't exist yet.

- [ ] **Step 4: Implement the endpoint in `cooper-core/main.py`**

Add `import council` near the existing `import jobs` line. Add the route right after the existing `POST /jobs/run/{job_id}` handler:

```python
@app.post("/jobs/critique/{job_id}", dependencies=[Depends(_require_auth)])
async def critique_job(job_id: str):
    job_entry = jobs.get_job(job_id)
    if job_entry is None:
        raise HTTPException(status_code=404, detail=f"unknown job id '{job_id}'")
    verdicts = await council.critique_envelope(
        job_entry, WORKSHOP,
        base_url=BACKEND_URL, api_key=BACKEND_KEY, backend=BACKEND,
    )
    verdict_dicts = council.verdicts_to_dicts(verdicts)
    note_path = jobs.write_critique_note(job_id, verdict_dicts)
    return {
        "job_id": job_id,
        "objection": council.has_objection(verdicts),
        "verdicts": verdict_dicts,
        "note_path": str(note_path),
    }
```

- [ ] **Step 5: Run the full suite**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`
Expected: PASS, all tests.

- [ ] **Step 6: Commit**

```bash
git add cooper-core/jobs.py cooper-core/main.py cooper-core/test_jobs.py cooper-core/test_main_jobs.py
git commit -m "feat(jobs): add POST /jobs/critique/{job_id} planning-time council (15d)"
```

---

### Task 6: Live end-to-end verification against the real running Open stack

**Files:**
- Modify (temporarily, fully reverted at the end): `Config/jobs_registry.yaml`
- Modify: `PROGRESS.md`, `Obsidian Vault/brain/North Star.md`, `CLAUDE.md` (test count only, if it changed)

This task never touches the real `link-checker` entry's `approved` field and never runs `link-checker` for real — both stay exactly as 14b left them. It adds two throwaway synthetic job entries, exercises the live endpoints, then removes them.

- [ ] **Step 1: Rebuild and bring up the Open stack with this branch's code**

```bash
docker compose -f PDA-Runtime/docker-compose.yml up -d --build cooper-core
sleep 5
curl -s http://localhost:8001/health
```

Expected: `{"status":"ok","workshop":"open",...}`. If this compose file also declares other services' `env_file` and this checkout is missing any of those `.env`/`.env.local` files, follow the mitigation in `Obsidian Vault/brain/Gotchas.md`'s 2026-08-30 entry (two-checkout method) rather than editing the compose file.

- [ ] **Step 2: Live-prove planning-time critique surfaces a seeded flaw**

```bash
KEY=$(grep '^COOPER_API_KEYS=' PDA-Runtime/.env | cut -d= -f2)
```

Temporarily append this entry to `Config/jobs_registry.yaml`'s `jobs:` list (do not touch the existing `link-checker` entry):

```yaml
  - id: 15d-test-flawed-envelope
    workshop: open
    schedule_hint: "manual"
    steps: [noop]
    read_scope: []
    write_scope: ["/"]
    quota: {}
    permission_level: 3
    approved: false
```

```bash
docker compose -f PDA-Runtime/docker-compose.yml restart cooper-core
sleep 3
curl -s -X POST http://localhost:8001/jobs/critique/15d-test-flawed-envelope \
  -H "Authorization: Bearer $KEY" | python3 -m json.tool
```

Expected: `"objection": true`, with at least one member's `"verdict": "flag"` and a `reason` naming the over-broad `write_scope`. Confirm the note landed:

```bash
cat "Obsidian Vault/00_Inbox/COOPER-Job-Critique-15d-test-flawed-envelope.md"
```

- [ ] **Step 3: Live-prove a passing L4+ job's evidence record carries named per-member verdicts**

Replace the entry added in Step 2 with this one (still not touching `link-checker`):

```yaml
  - id: 15d-test-l4-job
    workshop: open
    schedule_hint: "manual"
    steps: [noop]
    read_scope: []
    write_scope: []
    quota: {}
    permission_level: 4
    approved: true
    envelope_hash: "PLACEHOLDER"
```

Compute the real hash and patch it in:

```bash
cd cooper-core
.venv/bin/python -c "
import jobs, yaml
reg = yaml.safe_load(open('../Config/jobs_registry.yaml'))
entry = jobs.get_job('15d-test-l4-job', reg)
entry['envelope_hash'] = jobs.compute_envelope_hash(entry)
print(entry['envelope_hash'])
"
cd ..
```

Edit `Config/jobs_registry.yaml`, replacing `PLACEHOLDER` with the printed hash. This synthetic job has `steps: [noop]` and empty scopes, so `run_job`'s CSV-driven loop does nothing (no `read_scope[0]` to read) — it exercises purely the verify → final-review → evidence-write path, which is exactly what this step needs to prove, with zero risk of touching real files.

```bash
docker compose -f PDA-Runtime/docker-compose.yml restart cooper-core
sleep 3
curl -s -X POST http://localhost:8001/jobs/run/15d-test-l4-job \
  -H "Authorization: Bearer $KEY" | python3 -m json.tool
```

Expected: `"status": "completed"`. Find and inspect the resulting evidence record:

```bash
ls -t State/Workflow_Evidence/completion/workflow_completion_15d-test-l4-job_*.json | head -1 | xargs cat | python3 -m json.tool
```

Expected: a `"verdicts"` array with 3 entries (the Open roster: `openai`, `claude`, `gemini`), each with a non-empty `member`, `verdict` in `{"pass","flag"}`, and `reason`.

- [ ] **Step 4: Revert every temporary change**

```bash
git checkout -- Config/jobs_registry.yaml
rm -f "Obsidian Vault/00_Inbox/COOPER-Job-Critique-15d-test-flawed-envelope.md"
rm -f State/Workflow_Evidence/completion/workflow_completion_15d-test-l4-job_*.json
docker compose -f PDA-Runtime/docker-compose.yml restart cooper-core
sleep 3
curl -s http://localhost:8001/health
git status --short Config/jobs_registry.yaml
```

Expected: `git status` shows no diff on `jobs_registry.yaml`; `/health` still ok; `docker exec pda-open-cooper-core printenv | grep -c API_KEY` unchanged from before this task (sanity check per the Gotchas 2026-08-30 entry, if the compose-file mitigation was needed in Step 1).

- [ ] **Step 5: Run the full test suite one final time**

Run: `cd cooper-core && .venv/bin/python -m pytest -q`
Expected: PASS, all tests. Note the new total test count.

- [ ] **Step 6: Update docs and commit**

Update `PROGRESS.md`: check off `15d` in the roadmap checklist table, add a dated entry (model on the 14b/15c entries' style) summarizing what shipped, the live-verification evidence from Steps 2-3, and the Private-roster design decision from Global Constraints. Update `Obsidian Vault/brain/North Star.md`'s "Next up" line to point at `15e`. If the test count in `CLAUDE.md`'s "Running tests" section is stale, correct it (same pattern as 15c's finding-4 fix).

```bash
git add PROGRESS.md "Obsidian Vault/brain/North Star.md" CLAUDE.md
git commit -m "docs: 15d shipped -- council subsystem live and live-verified"
```
