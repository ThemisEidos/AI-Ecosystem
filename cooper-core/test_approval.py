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
