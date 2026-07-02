import pytest
from fastapi.testclient import TestClient

import main


def test_check_auth_config_raises_without_key():
    with pytest.raises(RuntimeError, match="COOPER_API_KEY"):
        main._check_auth_config("", False)


def test_check_auth_config_passes_with_key():
    main._check_auth_config("cooper-local", False)  # must not raise


def test_check_auth_config_passes_with_explicit_anon():
    main._check_auth_config("", True)  # must not raise


def test_chat_rejects_missing_bearer_when_key_set(monkeypatch):
    monkeypatch.setattr(main, "_API_KEY", "sekrit")
    client = TestClient(main.app)  # no `with` -> lifespan does not run
    resp = client.post("/chat", json={"message": "hi"})
    assert resp.status_code == 401


def test_chat_rejects_wrong_bearer_when_key_set(monkeypatch):
    monkeypatch.setattr(main, "_API_KEY", "sekrit")
    client = TestClient(main.app)
    resp = client.post(
        "/chat", json={"message": "hi"},
        headers={"Authorization": "Bearer wrong"},
    )
    assert resp.status_code == 401


def test_health_is_open_without_auth():
    client = TestClient(main.app)
    assert client.get("/health").status_code == 200
