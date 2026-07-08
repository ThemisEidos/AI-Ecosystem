import pytest
from fastapi.testclient import TestClient

import approval
import main


def test_check_auth_config_raises_without_key():
    with pytest.raises(RuntimeError, match="COOPER_API_KEY"):
        main._check_auth_config(set(), False)


def test_check_auth_config_passes_with_key():
    main._check_auth_config({"cooper-local"}, False)  # must not raise


def test_check_auth_config_passes_with_explicit_anon():
    main._check_auth_config(set(), True)  # must not raise


def test_chat_rejects_missing_bearer_when_key_set(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"sekrit"})
    client = TestClient(main.app)  # no `with` -> lifespan does not run
    resp = client.post("/chat", json={"message": "hi"})
    assert resp.status_code == 401


def test_chat_rejects_wrong_bearer_when_key_set(monkeypatch):
    monkeypatch.setattr(main, "_API_KEYS", {"sekrit"})
    client = TestClient(main.app)
    resp = client.post(
        "/chat", json={"message": "hi"},
        headers={"Authorization": "Bearer wrong"},
    )
    assert resp.status_code == 401


def test_health_is_open_without_auth():
    client = TestClient(main.app)
    assert client.get("/health").status_code == 200


def test_derive_session_id_is_stable_and_anonymous_safe():
    import main
    a = main._derive_session_id("key-alpha")
    assert a == main._derive_session_id("key-alpha")      # stable
    assert a != main._derive_session_id("key-beta")       # distinct per key
    assert len(a) == 12
    assert main._derive_session_id(None) == "anon"
    assert main._derive_session_id("") == "anon"


def test_parse_api_keys_multi_and_legacy():
    import main
    assert main._parse_api_keys("k1, k2 ,k3", "") == {"k1", "k2", "k3"}
    assert main._parse_api_keys("", "legacy") == {"legacy"}
    assert main._parse_api_keys("k1", "legacy") == {"k1", "legacy"}
    assert main._parse_api_keys("", "") == set()


def test_pending_and_chat_are_isolated_per_bearer_token(monkeypatch):
    """HTTP-level regression test (Step 13): two different bearer tokens must never
    see or consume each other's approval tickets. Seeds a ticket directly via
    approval.request() for key-a's derived session, then drives /pending and /chat
    over the real FastAPI app with key-a and key-b — no live LLM backend needed."""
    monkeypatch.setattr(main, "_API_KEYS", {"key-a", "key-b"})
    approval._pending.clear()

    session_a = main._derive_session_id("key-a")
    tool = {"id": "t", "name": "T", "permission_level": 2}
    approval.request(main.WORKSHOP, tool, "do the thing", session_id=session_a)

    client = TestClient(main.app)  # no `with` -> lifespan does not run

    resp_a = client.get("/pending", headers={"Authorization": "Bearer key-a"})
    assert resp_a.status_code == 200
    assert resp_a.json()["pending"] is not None

    resp_b = client.get("/pending", headers={"Authorization": "Bearer key-b"})
    assert resp_b.status_code == 200
    assert resp_b.json()["pending"] is None

    # key-b's "approve" must not consume key-a's ticket.
    resp_chat_b = client.post(
        "/chat", json={"message": "approve"},
        headers={"Authorization": "Bearer key-b"},
    )
    assert resp_chat_b.status_code == 200

    resp_a_again = client.get("/pending", headers={"Authorization": "Bearer key-a"})
    assert resp_a_again.status_code == 200
    assert resp_a_again.json()["pending"] is not None
