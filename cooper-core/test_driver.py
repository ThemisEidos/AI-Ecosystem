"""Driver selection: any LLM can drive COOPER-Open (owner-directed 2026-09-07).

The 'driver' is the brain model for the Open workshop, switchable at runtime
from the Cockpit dropdown. Governance: the pick is validated against a closed
set -- the LiteLLM aliases plus the live OpenRouter catalog -- never a
free-form string; the choice is persisted and audited; Private is untouched.
"""
import sqlite3

import pytest

import archivist
import driver


@pytest.fixture()
def conn(tmp_path):
    c = archivist.get_conn(tmp_path / "m.db")
    archivist.init_db(c)
    return c


def _fake_catalog(monkeypatch, ids):
    monkeypatch.setattr(driver, "_fetch_catalog_ids", lambda: set(ids))
    driver._CATALOG_CACHE.update({"ids": None, "at": 0.0})


def test_default_driver_is_the_configured_brain(conn):
    assert driver.current(conn, default="openai") == "openai"


def test_set_driver_to_a_litellm_alias(conn, monkeypatch):
    _fake_catalog(monkeypatch, [])
    out = driver.set_driver(conn, "claude", default="openai")
    assert out == "claude"
    assert driver.current(conn, default="openai") == "claude"


def test_set_driver_to_a_catalog_slug(conn, monkeypatch):
    _fake_catalog(monkeypatch, ["meta-llama/llama-3.3-70b-instruct"])
    out = driver.set_driver(conn, "openrouter/meta-llama/llama-3.3-70b-instruct", default="openai")
    assert out == "openrouter/meta-llama/llama-3.3-70b-instruct"


def test_set_driver_refuses_an_unknown_slug(conn, monkeypatch):
    _fake_catalog(monkeypatch, ["real/model"])
    with pytest.raises(driver.DriverError):
        driver.set_driver(conn, "openrouter/fake/notamodel", default="openai")


def test_set_driver_refuses_free_form_strings(conn, monkeypatch):
    _fake_catalog(monkeypatch, ["real/model"])
    for bad in ("gpt-9", "anthropic/claude-x", "", "   ", "openrouter/"):
        with pytest.raises(driver.DriverError):
            driver.set_driver(conn, bad, default="openai")


def test_reset_returns_to_default(conn, monkeypatch):
    _fake_catalog(monkeypatch, [])
    driver.set_driver(conn, "claude", default="openai")
    driver.set_driver(conn, "openai", default="openai")
    assert driver.current(conn, default="openai") == "openai"


def test_driver_persists_across_reads(conn, monkeypatch):
    _fake_catalog(monkeypatch, [])
    driver.set_driver(conn, "gemini", default="openai")
    # a fresh read (new module cache) must come from the DB, not memory
    driver._STATE.update({"value": None, "loaded": False})
    assert driver.current(conn, default="openai") == "gemini"


def test_catalog_unreachable_fails_closed_for_slugs(conn, monkeypatch):
    def boom():
        raise driver.DriverError("catalog unreachable")
    monkeypatch.setattr(driver, "_fetch_catalog_ids", boom)
    driver._CATALOG_CACHE.update({"ids": None, "at": 0.0})
    with pytest.raises(driver.DriverError):
        driver.set_driver(conn, "openrouter/meta-llama/llama-3.3-70b-instruct", default="openai")
    # aliases don't need the catalog, so they still work
    assert driver.set_driver(conn, "claude", default="openai") == "claude"


def test_catalog_keeps_only_tool_capable_models(monkeypatch):
    """COOPER's dispatch is native tool-calls (15a); a driver that cannot emit
    them chats but silently loses dispatch -- observed live 2026-09-07 with
    llama-3.3-70b. The dropdown must only offer drivers that can drive."""
    class FakeResp:
        status_code = 200
        def raise_for_status(self): pass
        def json(self):
            return {"data": [
                {"id": "good/tooler", "supported_parameters": ["tools", "temperature"]},
                {"id": "bad/chatter", "supported_parameters": ["temperature"]},
                {"id": "bad/unknown"},
            ]}
    monkeypatch.setattr(driver.httpx, "get", lambda *a, **k: FakeResp())
    assert driver._fetch_catalog_ids() == {"good/tooler"}
