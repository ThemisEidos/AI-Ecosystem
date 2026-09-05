"""COOPER's per-stage timeout/retry budgets (Step 15f-ii). Implements
Scripts/PDA_RetryPolicy.json — repo rule: no new policy files, implement the
existing one.

Why this exists: before it, every LLM call site used a hardcoded client timeout
(120s for Ollama, 60s for OpenAI) and there was no retry logic anywhere in
cooper-core. A chain of three calls could therefore burn ~360s before failing,
and a single transient 429/503 killed the whole turn — the Step 11 incident's
failure class. A budget makes each stage's worst case computable in advance
(see Budget.worst_case_seconds) and bounds retries so a flapping upstream can
never turn into an unbounded loop.

The policy file predates the v2 runtime: its `workers` map names v1 PowerShell
workers (reporter-worker, planner-worker, ...) that no longer exist. Rather than
invent a second policy file, this module reads a `roles` section keyed by the
same role names PDA_ModelRouting.json already uses, and leaves the legacy
`workers`/`dead_letter_folder` keys untouched for the v1 scripts that still
read them.
"""
import asyncio
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Awaitable, Callable, Optional, Tuple, TypeVar

_REPO_ROOT = Path(__file__).resolve().parent.parent
_POLICY_PATH = _REPO_ROOT / "Scripts" / "PDA_RetryPolicy.json"

# Conservative built-ins used when the policy file is missing or unreadable.
# Fail open: an unreadable policy must not take the runtime down.
_FALLBACK_TIMEOUT = 60.0
_FALLBACK_MAX_RETRIES = 1

_MIN_TIMEOUT = 1.0     # a zero/negative timeout is not a budget
_MAX_TIMEOUT = 300.0
_MAX_RETRIES_CAP = 5   # bounded by construction; a flapping upstream can't loop

T = TypeVar("T")


@dataclass(frozen=True)
class Budget:
    """One stage's execution envelope. `timeout` applies per attempt, so the
    worst case is timeout * (1 + max_retries) plus backoff."""
    timeout: float
    max_retries: int
    backoff_base: float = 0.5
    non_retryable: Tuple[str, ...] = field(default_factory=tuple)

    def worst_case_seconds(self) -> float:
        """Upper bound on wall clock, excluding backoff. Callers use this to
        reason about a chain's total budget before running it."""
        return self.timeout * (1 + self.max_retries)


def load_policy(path: Optional[Path] = None) -> dict:
    """Read the policy, failing open to an empty dict. Unlike model_routing,
    this must not raise: a missing retry policy degrades to defaults, it does
    not stop the runtime."""
    try:
        with open(path or _POLICY_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def _clamp(value, low: float, high: float, default: float) -> float:
    try:
        value = float(value)
    except (TypeError, ValueError):
        return default
    if value <= 0:
        return default
    return max(low, min(high, value))


def budget_for(
    role: str,
    policy: Optional[dict] = None,
    path: Optional[Path] = None,
) -> Budget:
    """Resolve `role`'s budget, filling anything undeclared from the policy's
    defaults and then from this module's built-ins."""
    policy = policy if policy is not None else load_policy(path)

    default_timeout = _clamp(
        policy.get("default_timeout_seconds"), _MIN_TIMEOUT, _MAX_TIMEOUT, _FALLBACK_TIMEOUT
    )
    try:
        default_retries = int(policy.get("default_max_retries", _FALLBACK_MAX_RETRIES))
    except (TypeError, ValueError):
        default_retries = _FALLBACK_MAX_RETRIES

    entry = (policy.get("roles") or {}).get(role) or {}
    timeout = _clamp(
        entry.get("timeout_seconds"), _MIN_TIMEOUT, _MAX_TIMEOUT, default_timeout
    )
    try:
        retries = int(entry.get("max_retries", default_retries))
    except (TypeError, ValueError):
        retries = default_retries

    return Budget(
        timeout=timeout,
        max_retries=max(0, min(_MAX_RETRIES_CAP, retries)),
        non_retryable=tuple(policy.get("non_retryable_reasons") or ()),
    )


def _is_retryable(exc: BaseException, budget: Budget) -> bool:
    """A governance refusal or a malformed request is not worth hammering N
    more times — only transient faults are. Matching is on the message because
    the backends raise plain exceptions with reason text, not typed errors."""
    text = str(exc).lower()
    return not any(reason.lower() in text for reason in budget.non_retryable)


async def call_with_budget(
    operation: Callable[[], Awaitable[T]],
    budget: Budget,
) -> T:
    """Run `operation` under the budget: `timeout` per attempt, at most
    `max_retries` retries, exponential backoff between them. Re-raises the last
    error once the budget is spent, so a caller's own error handling still sees
    a real failure rather than a silent None.

    `operation` is a zero-arg factory returning a fresh awaitable, not a
    coroutine object — a coroutine cannot be awaited twice, so a retry needs a
    new one each attempt.
    """
    last: Optional[BaseException] = None
    for attempt in range(budget.max_retries + 1):
        try:
            return await asyncio.wait_for(operation(), timeout=budget.timeout)
        except asyncio.CancelledError:
            raise
        except (asyncio.TimeoutError, Exception) as exc:  # noqa: B014 - explicit for clarity
            last = exc
            if not _is_retryable(exc, budget):
                raise
            if attempt >= budget.max_retries:
                raise
            if budget.backoff_base > 0:
                await asyncio.sleep(budget.backoff_base * (2 ** attempt))
    raise last if last is not None else RuntimeError("call_with_budget: no attempt ran")


async def stream_with_budget(events, budget: Budget):
    """Bound a streaming response without capping its total length.

    A blocking call gets one timeout around the whole thing. A stream cannot:
    a legitimately long generation would be killed for being long. The
    meaningful bounds are instead:

      * time to FIRST event -- a backend that accepts the connection but never
        starts generating is wedged, and used to hang the turn indefinitely;
      * time BETWEEN events -- a backend that dies mid-generation leaves the
        stream open forever, so a stall is the only observable symptom.

    Both use `budget.timeout` per gap, so the cap is per-chunk, never total.

    `budget.max_retries` is deliberately IGNORED. Retrying a partially consumed
    stream would replay tokens the caller has already forwarded to the user;
    once the first chunk is out, the only honest options are finish or fail.

    Raises asyncio.TimeoutError on either bound, after closing the source
    iterator so the underlying HTTP response is released rather than leaked.
    """
    iterator = events.__aiter__()
    while True:
        try:
            item = await asyncio.wait_for(iterator.__anext__(), timeout=budget.timeout)
        except StopAsyncIteration:
            return
        except (asyncio.TimeoutError, asyncio.CancelledError):
            aclose = getattr(iterator, "aclose", None)
            if aclose is not None:
                try:
                    await aclose()
                except Exception:
                    pass
            raise
        yield item
