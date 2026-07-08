import pytest
from fastapi.testclient import TestClient

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
