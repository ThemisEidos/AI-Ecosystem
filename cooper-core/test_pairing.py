"""Device pairing: hand the API key to a phone without typing it.

The claim endpoint is UNAUTHENTICATED by necessity -- the whole point is that
the claiming device has no key yet. That makes the code itself the only secret,
so everything here exists to keep the window small: short TTL, single use, and a
hard attempt cap so a code cannot be brute-forced within its own lifetime.
"""
import time

import pytest

import pairing


def test_new_code_is_six_digits():
    store = pairing.PairingStore()
    code = store.new_code("secret-key")
    assert len(code) == 6 and code.isdigit()


def test_codes_are_unique_across_calls():
    store = pairing.PairingStore()
    codes = {store.new_code("k") for _ in range(50)}
    assert len(codes) == 50


def test_claim_returns_the_key_once_then_never_again():
    store = pairing.PairingStore()
    code = store.new_code("secret-key")
    assert store.claim(code) == "secret-key"
    assert store.claim(code) is None, "a pairing code must be single use"


def test_claim_rejects_an_unknown_code():
    assert pairing.PairingStore().claim("000000") is None


def test_claim_rejects_an_expired_code():
    store = pairing.PairingStore(ttl_seconds=0)
    code = store.new_code("secret-key")
    time.sleep(0.01)
    assert store.claim(code) is None


def test_wrong_guesses_burn_the_attempt_budget_for_everyone():
    # The cap is global, not per-code: otherwise an attacker enumerates codes
    # and each wrong guess is "free" because it belongs to no code.
    store = pairing.PairingStore(max_attempts=3)
    code = store.new_code("secret-key")
    for _ in range(3):
        assert store.claim("999999") is None
    assert store.claim(code) is None, "budget exhausted must lock out the real code too"


def test_attempt_budget_resets_when_a_new_code_is_issued():
    store = pairing.PairingStore(max_attempts=2)
    store.new_code("k")
    store.claim("111111")
    store.claim("222222")
    code = store.new_code("k")
    assert store.claim(code) == "k", "issuing a fresh code must clear the lockout"


def test_issuing_a_code_invalidates_the_previous_one():
    # One pending code at a time keeps the guessable surface at exactly one.
    store = pairing.PairingStore()
    first = store.new_code("k")
    second = store.new_code("k")
    assert store.claim(first) is None
    assert store.claim(second) == "k"


def test_pending_reports_seconds_remaining():
    store = pairing.PairingStore(ttl_seconds=300)
    code = store.new_code("k")
    p = store.pending()
    assert p["code"] == code
    assert 290 <= p["expires_in"] <= 300


def test_pending_is_none_when_nothing_is_outstanding():
    assert pairing.PairingStore().pending() is None


def test_claim_is_constant_time_comparison():
    # Guard against a timing oracle on the code; hmac.compare_digest is the
    # marker we assert on because behaviour cannot be tested reliably here.
    import inspect
    assert "compare_digest" in inspect.getsource(pairing.PairingStore.claim)
