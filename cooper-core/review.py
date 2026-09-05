"""
COOPER Reviewer — sub-agent review loop (Step 7).

Worker -> Reviewer -> Governor:
  Worker    = executor.run() output (already executed, step 5)
  Reviewer  = review() below — an LLM call that inspects the worker's raw
              output and returns a pass/flag verdict before it reaches the user
  Governor  = govern() — deterministic logic that decides what the user sees
              based on the reviewer's verdict

Design mirrors decision.py's classifier: JSON-schema-constrained output,
temperature=0, think:false for Ollama. The reviewer fails OPEN (pass) on any
error — a broken reviewer must never block a legitimate result. It's a safety
net on top of execution, not a second approval gate.
"""
import json
from dataclasses import dataclass

from typing import Optional

from decision import _ollama_complete, _openai_complete
import retry_policy

_REVIEWER_SYSTEM = """\
You are COOPER's Reviewer. A Workbench tool just ran and produced output below. \
Check it before it reaches the user.

FLAG if the output shows: a non-zero/failed exit code, an exception or stack trace, \
a timeout, a "not found" / "not wired" stub, or output that plainly did not \
accomplish the requested action.

PASS if the output looks like normal, successful tool execution matching the request.

Output JSON only — no other text.
{"verdict":"pass"|"flag","reason":"<brief phrase>"}\
"""

VALID_VERDICTS = frozenset({"pass", "flag"})
_MAX_OUTPUT_FOR_REVIEW = 4000


@dataclass
class ReviewVerdict:
    verdict: str  # "pass" | "flag"
    reason: str


async def review(
    tool: dict,
    message: str,
    raw_output: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    backend: str,
    budget: Optional["retry_policy.Budget"] = None,
) -> ReviewVerdict:
    """Reviewer: ask the model to check the worker's output. Fails open (pass).

    The backend call runs under the reviewer role's timeout/retry budget
    (Step 15f-ii). Before budgets a wedged backend held the turn for the
    client's full hardcoded timeout with no retry; now a transient fault gets
    one bounded retry, and a genuine hang fails open at the budget instead of
    the client timeout. `budget` is injectable so tests can shrink it."""
    tool_name = tool.get("name", tool.get("id", "unknown"))
    user_msg = (
        f"Requested action: {message}\n"
        f"Tool: {tool_name}\n"
        f"Tool output:\n{raw_output[:_MAX_OUTPUT_FOR_REVIEW]}"
    )
    messages = [
        {"role": "system", "content": _REVIEWER_SYSTEM},
        {"role": "user", "content": user_msg},
    ]

    budget = budget or retry_policy.budget_for("reviewer")

    async def _complete():
        if backend == "openai":
            return await _openai_complete(
                base_url, api_key, model, messages,
                temperature=0,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "review",
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
            return await _ollama_complete(
                base_url, model, messages,
                options={"temperature": 0},
                fmt={
                    "type": "object",
                    "properties": {
                        "verdict": {"type": "string", "enum": ["pass", "flag"]},
                        "reason":  {"type": "string"},
                    },
                    "required": ["verdict", "reason"],
                },
            )

    try:
        raw = await retry_policy.call_with_budget(_complete, budget)
        data = json.loads(raw)
        verdict = data.get("verdict", "pass")
        if verdict not in VALID_VERDICTS:
            verdict = "pass"
        return ReviewVerdict(verdict=verdict, reason=data.get("reason", ""))
    except Exception as exc:
        print(f"  [!!] reviewer fail-open: {exc}")
        return ReviewVerdict(verdict="pass", reason=f"reviewer error (fail-open): {exc}")


def govern(raw_output: str, verdict: ReviewVerdict) -> str:
    """Governor: decide what the user sees based on the reviewer's verdict."""
    if verdict.verdict == "flag":
        return f"[Reviewer flagged this result — {verdict.reason}]\n\n{raw_output}"
    return raw_output
