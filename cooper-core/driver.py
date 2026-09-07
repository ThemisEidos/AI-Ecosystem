"""Runtime driver selection — any LLM can drive COOPER-Open.

Owner-directed 2026-09-07: the Open workshop's brain model is switchable at
runtime from the Cockpit, with the choice drawn from the OpenRouter catalog
plus the local LiteLLM aliases. Governance rules:

  * The pick is validated against a CLOSED set — a LiteLLM alias, or an
    "openrouter/<slug>" whose slug appears in the live OpenRouter catalog.
    Never a free-form string.
  * Catalog unreachable ⇒ slug picks fail CLOSED (aliases keep working —
    they need no catalog).
  * The choice persists in cooper_memory.db (settings table) so a restart
    keeps the chosen driver, and every change is printed for the audit trail.
  * Open workshop only. Private's brain is not driven from here.
"""
import json
import time
from typing import Optional

import httpx

import model_routing

_SETTING_KEY = "open_driver"
_CATALOG_URL = "https://openrouter.ai/api/v1/models"
_CATALOG_TTL = 3600.0
_CATALOG_CACHE: dict = {"ids": None, "at": 0.0}
_STATE: dict = {"value": None, "loaded": False}


class DriverError(Exception):
    pass


def _ensure_table(conn) -> None:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS settings ("
        "key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )


def _aliases() -> set:
    """Locally-routable names: the roster aliases plus the default pool."""
    names = {"openai", "claude", "gemini", "gemini-pro"}
    for spec in model_routing.load_specialists().values():
        names.add(spec["alias"])
    return names


def _fetch_catalog_ids() -> set:
    try:
        resp = httpx.get(_CATALOG_URL, timeout=20)
        resp.raise_for_status()
        data = resp.json().get("data") or []
    except Exception as exc:
        raise DriverError(f"OpenRouter catalog unreachable: {exc}")
    # Only models that support native tool calling may drive. COOPER's dispatch
    # is tool-calls (15a); a driver without them can chat but silently loses
    # dispatch -- observed live 2026-09-07 with llama-3.3-70b, whose delegation
    # request came back as plain text. The catalog's supported_parameters tells
    # us up front, so the dropdown only offers drivers that can actually drive.
    return {
        str(m.get("id", "")).strip() for m in data
        if m.get("id") and "tools" in (m.get("supported_parameters") or [])
    }


def catalog(force: bool = False) -> list:
    """Cached OpenRouter model list for the dropdown (id strings, sorted)."""
    now = time.monotonic()
    if force or _CATALOG_CACHE["ids"] is None or now - _CATALOG_CACHE["at"] > _CATALOG_TTL:
        _CATALOG_CACHE["ids"] = _fetch_catalog_ids()
        _CATALOG_CACHE["at"] = now
    return sorted(_CATALOG_CACHE["ids"])


def current(conn, default: str) -> str:
    """The model currently driving COOPER-Open."""
    if not _STATE["loaded"]:
        _ensure_table(conn)
        row = conn.execute(
            "SELECT value FROM settings WHERE key = ?", (_SETTING_KEY,)
        ).fetchone()
        _STATE["value"] = row[0] if row else None
        _STATE["loaded"] = True
    return _STATE["value"] or default


def set_driver(conn, model: str, default: str) -> str:
    """Validate and persist a new driver. Raises DriverError on anything
    outside the closed set — the dropdown is a convenience, not the gate."""
    pick = str(model or "").strip()
    if not pick:
        raise DriverError("no model named")
    if pick in _aliases():
        pass  # locally routable, no catalog needed
    elif pick.startswith("openrouter/"):
        slug = pick[len("openrouter/"):]
        if not slug:
            raise DriverError("empty OpenRouter slug")
        ids = set(catalog())
        if slug not in ids:
            raise DriverError(
                f"'{slug}' is not in the OpenRouter catalog — refusing to route"
            )
    else:
        raise DriverError(
            f"'{pick}' is neither a LiteLLM alias ({', '.join(sorted(_aliases()))}) "
            "nor an 'openrouter/<slug>' from the catalog"
        )
    _ensure_table(conn)
    from archivist import _DB_LOCK
    with _DB_LOCK:
        conn.execute(
            "INSERT OR REPLACE INTO settings (key, value, updated_at) "
            "VALUES (?, ?, datetime('now'))", (_SETTING_KEY, pick))
        conn.commit()
    _STATE.update({"value": pick, "loaded": True})
    print(f"  [ok] COOPER-Open driver set to '{pick}'")
    return pick
