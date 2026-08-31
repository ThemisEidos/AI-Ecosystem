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
from collections import Counter
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


def _disambiguate_labels(members: List[str]) -> List[str]:
    """Labels for CouncilVerdict.member, one per roster position. A roster
    entry that repeats (e.g. Private's ["COOPER-Private"] x3 -- same local
    model run at different temperatures, no real model diversity available)
    would otherwise produce indistinguishable verdicts; disambiguate those
    with a positional suffix (f"{member}#{i+1}"). Rosters with no duplicates
    (e.g. Open's ["openai","claude","gemini"]) are returned unchanged --
    this only ever affects the *label* recorded on the verdict, never the
    model alias used for the actual backend call."""
    counts = Counter(members)
    return [f"{m}#{i + 1}" if counts[m] > 1 else m for i, m in enumerate(members)]


async def _member_verdict(
    system_prompt: str,
    user_msg: str,
    member: str,
    *,
    base_url: str,
    api_key: str,
    backend: str,
    temperature: float,
    label: Optional[str] = None,
) -> CouncilVerdict:
    """One council member's JSON-schema-constrained verdict call. Fails open
    (pass) on any error -- same convention as review.review().

    `member` is the real model alias -- it's what actually gets sent to the
    backend (Ollama model name / OpenAI-compatible model id). `label` is
    what's recorded on the returned CouncilVerdict; it defaults to `member`
    but callers with a repeated-alias roster (Private) pass a disambiguated
    label so the evidence record's per-member verdicts stay distinguishable
    without changing what model actually gets called."""
    label = label if label is not None else member
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
        return CouncilVerdict(member=label, verdict=verdict, reason=data.get("reason", ""))
    except Exception as exc:
        print(f"  [!!] council member '{label}' fail-open: {exc}")
        return CouncilVerdict(
            member=label, verdict="pass",
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
    labels = _disambiguate_labels(members)
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
            label=labels[i],
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
        labels = _disambiguate_labels(members)
        user_msg = f"Job: {message}\nRun summary:\n{raw_output[:_MAX_TEXT_FOR_REVIEW]}"
        calls = [
            _member_verdict(
                _FINAL_REVIEW_SYSTEM, user_msg, member,
                base_url=base_url, api_key=api_key, backend=backend,
                temperature=_MEMBER_TEMPERATURES[i % len(_MEMBER_TEMPERATURES)],
                label=labels[i],
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
