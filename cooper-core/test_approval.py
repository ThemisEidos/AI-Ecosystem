import time

import approval


TOOL = {"name": "PowerShell Private Runner", "permission_level": 4, "approval_required": True}


def setup_function():
    approval._pending.clear()


def test_needs_approval_for_level_2_plus():
    assert approval.needs_approval({"permission_level": 2}) is True
    assert approval.needs_approval({"permission_level": 0}) is False
    assert approval.needs_approval({"permission_level": 0, "approval_required": True}) is True


def test_exact_yes_is_a_response():
    assert approval.is_response("yes") is True
    assert approval.is_response("  Approve.  ") is True
    assert approval.is_response("go ahead!") is True


def test_exact_no_is_a_response():
    assert approval.is_response("no") is True
    assert approval.is_response("Cancel") is True


def test_qualified_yes_is_not_a_response():
    assert approval.is_response("yes, but first tell me what it does") is False


def test_compound_approve_phrases_are_responses():
    # Regression: these exact phrases are documented in PROGRESS.md as live-verified
    # approve/deny replies; a prior full-match-only regex silently stopped matching them.
    assert approval.is_response("yes, go ahead") is True
    assert approval.is_response("no, cancel that") is True
    assert approval.is_approved("yes, go ahead") is True
    assert approval.is_denied("no, cancel that") is True


def test_prefixed_deny_words_are_not_responses():
    assert approval.is_response("note that the server is down") is False
    assert approval.is_response("stop the webhook server and restart it") is False


def test_ticket_lifecycle():
    approval.request("private", TOOL, "run Test-Exec.ps1")
    assert approval.has_pending("private") is True
    ticket = approval.consume("private")
    assert ticket is not None and ticket.tool["name"] == TOOL["name"]
    assert approval.has_pending("private") is False


def test_ticket_expires():
    ticket = approval.request("private", TOOL, "run Test-Exec.ps1")
    ticket.created_at = time.time() - (approval._TICKET_TTL_SECONDS + 1)
    assert approval.has_pending("private") is False


def _tool():
    return {"id": "t", "name": "T", "permission_level": 2}


def test_ticket_bound_to_opening_session():
    approval._pending.clear()
    approval.request("open", _tool(), "do it", session_id="client-a")
    # a different session sees nothing and cannot consume
    assert not approval.has_pending("open", "client-b")
    assert approval.peek("open", "client-b") is None
    assert approval.consume("open", "client-b") is None
    # the opening session still holds a live ticket after the foreign attempt
    assert approval.has_pending("open", "client-a")
    ticket = approval.consume("open", "client-a")
    assert ticket is not None and ticket.session_id == "client-a"
    assert not approval.has_pending("open", "client-a")


def test_sessions_have_independent_tickets():
    approval._pending.clear()
    approval.request("open", _tool(), "task a", session_id="client-a")
    approval.request("open", _tool(), "task b", session_id="client-b")
    assert approval.consume("open", "client-a").message == "task a"
    assert approval.consume("open", "client-b").message == "task b"


def test_default_session_is_local():
    approval._pending.clear()
    approval.request("open", _tool(), "solo")
    assert approval.has_pending("open")
    assert approval.consume("open").session_id == "local"


def test_ticket_stores_and_returns_args():
    ticket = approval.request(
        "open", _tool(), "write note x.md: hi", session_id="c",
        args={"filename": "x.md", "content": "hi"},
    )
    assert ticket.args == {"filename": "x.md", "content": "hi"}
    consumed = approval.consume("open", "c")
    assert consumed.args == {"filename": "x.md", "content": "hi"}


def test_ticket_args_defaults_to_empty_dict():
    ticket = approval.request("open", _tool(), "do it", session_id="c2")
    assert ticket.args == {}
