"""Shared test environment. Hermetic git identity: without it, `git clone` in
the tap-import tests derives a default committer ident by DNS-canonicalizing
the machine hostname — which hangs the whole suite on hosts where that lookup
stalls (seen 2026-08-02: hostname absent from /etc/hosts + unresponsive local
resolver). Tests must not depend on the machine's name resolution."""
import dataclasses
import os

# The suite's assertions are written against the OPEN workshop: test_main_*.py
# and test_gateway.py assert Open routing, the general tool registry and the
# LiteLLM base URL. main.py reads WORKSHOP once, at import time, so whatever is
# in the ambient environment when pytest starts decides what those tests see.
#
# Several test modules already tried to pin this with
# os.environ.setdefault("WORKSHOP", "open") — but setdefault is a no-op when the
# variable is ALREADY set, which is exactly the case that matters: running the
# suite inside pda-private-cooper-core (WORKSHOP=private) turned 12 tests red
# while the code was byte-identical to the green Open container. The in-image
# suite is the project's packaging check, so a check that cries wolf on one of
# the two stacks is worse than no check. Gotchas 2026-09-05.
#
# Assign, don't setdefault. A test that wants a different workshop must not rely
# on ambient env either — test_main_open_routing.py's _run_main_import_with_env
# re-imports main in a subprocess with an explicit env dict, which is the
# supported way to exercise the private configuration.
os.environ["WORKSHOP"] = "open"

os.environ.setdefault("GIT_AUTHOR_NAME", "cooper-tests")
os.environ.setdefault("GIT_AUTHOR_EMAIL", "cooper-tests@localhost")
os.environ.setdefault("GIT_COMMITTER_NAME", "cooper-tests")
os.environ.setdefault("GIT_COMMITTER_EMAIL", "cooper-tests@localhost")


import pytest

import retry_policy as _retry_policy


@pytest.fixture(autouse=True)
def _no_retry_backoff(monkeypatch):
    """Zero the retry backoff for the whole suite (Step 15f-ii).

    Production budgets carry a 0.5s exponential backoff, so every test that
    simulates a backend failure would otherwise pay real wall-clock sleep —
    the drafter's two retries alone cost 1.5s per test. Tripled the suite's
    runtime when the budgets were wired in.

    Only the delay is neutralised: timeouts, retry counts and the
    retryable/non-retryable decision are untouched, so the behaviour under
    test is still the real behaviour. A test that specifically wants backoff
    timing constructs its own Budget with an explicit backoff_base.
    """
    real = _retry_policy.budget_for

    def no_backoff(role, *a, **k):
        return dataclasses.replace(real(role, *a, **k), backoff_base=0.0)

    monkeypatch.setattr(_retry_policy, "budget_for", no_backoff)
