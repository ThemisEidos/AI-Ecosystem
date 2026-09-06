"""Device pairing for the Cockpit (Step 15i).

Problem: the Cockpit is reachable from the home network, but a phone has no way
to get the API key short of typing 39 characters by hand.

Solution: the already-unlocked desktop asks for a six-digit code; the phone
enters it and receives the key, which its browser then keeps. The claim endpoint
is necessarily UNAUTHENTICATED -- the claiming device has no key yet, which is
the entire point -- so the code is the only secret standing in front of the API
key, and every rule here exists to keep that window small:

  * ONE pending code at a time. Issuing a new code invalidates the old one, so
    the guessable surface is exactly one code, never a growing pile.
  * Short TTL (5 minutes by default).
  * Single use. A claimed code is gone.
  * A GLOBAL attempt budget, not per-code. Per-code counting is useless against
    enumeration, because a wrong guess belongs to no code and would cost the
    attacker nothing. Five wrong guesses kill the pending code outright.
  * Constant-time comparison, so the code cannot be recovered a digit at a time.

State is in memory on purpose: a restart should forget pending codes, and a
pairing secret has no business being written to disk.
"""
import hmac
import secrets
import time
from typing import Optional


class PairingStore:
    def __init__(self, ttl_seconds: int = 300, max_attempts: int = 5):
        self.ttl = int(ttl_seconds)
        self.max_attempts = int(max_attempts)
        self._code: Optional[str] = None
        self._key: Optional[str] = None
        self._expires: float = 0.0
        self._attempts: int = 0

    def new_code(self, api_key: str) -> str:
        """Issue a pairing code, replacing any code already outstanding."""
        self._code = f"{secrets.randbelow(1_000_000):06d}"
        self._key = str(api_key)
        self._expires = time.monotonic() + self.ttl
        self._attempts = 0
        return self._code

    def pending(self) -> Optional[dict]:
        """The outstanding code and its remaining life, or None."""
        if not self._code or time.monotonic() >= self._expires:
            return None
        return {"code": self._code, "expires_in": int(round(self._expires - time.monotonic()))}

    def claim(self, code: str) -> Optional[str]:
        """Exchange a code for the API key. Returns None on any failure.

        Deliberately returns the same None for unknown / expired / exhausted /
        wrong, so a caller learns nothing from which way it failed.
        """
        if not self._code:
            return None
        if time.monotonic() >= self._expires:
            self._clear()
            return None
        if self._attempts >= self.max_attempts:
            self._clear()
            return None
        if not hmac.compare_digest(str(code or ""), self._code):
            self._attempts += 1
            if self._attempts >= self.max_attempts:
                self._clear()
            return None
        key = self._key
        self._clear()
        return key

    def _clear(self) -> None:
        self._code = None
        self._key = None
        self._expires = 0.0
        self._attempts = 0
