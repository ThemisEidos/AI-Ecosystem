import asyncio
from pathlib import Path

import executor

ALLOWED_TOOL = {
    "id": "powershell_private",
    "name": "PowerShell Private Runner",
    "executor_type": "powershell",
    "allowed_scripts": ["Test-Exec.ps1"],
}
NO_LIST_TOOL = {
    "id": "powershell_private",
    "name": "PowerShell Private Runner",
    "executor_type": "powershell",
}


def test_resolve_script_finds_existing_script():
    script = executor._resolve_script("please run Test-Exec.ps1 now")
    assert script is not None
    assert script.name == "Test-Exec.ps1"


def test_resolve_script_returns_none_for_unknown_script():
    assert executor._resolve_script("run Definitely-Not-Real-XYZ.ps1") is None


def test_resolve_script_neutralizes_traversal():
    # Path("../..\\Test-Exec.ps1").name strips directories; must resolve inside Scripts/
    script = executor._resolve_script("run ../../Test-Exec.ps1")
    assert script is None or script.parent == executor._SCRIPTS_DIR.resolve()


def test_authorize_accepts_listed_script():
    script = executor._SCRIPTS_DIR / "Test-Exec.ps1"
    assert executor._authorize_script(script, ALLOWED_TOOL) is None


def test_authorize_rejects_unlisted_script():
    script = executor._SCRIPTS_DIR / "Start-PDAWebhookServer.ps1"
    denial = executor._authorize_script(script, ALLOWED_TOOL)
    assert denial is not None
    assert "allowed_scripts" in denial


def test_authorize_fails_closed_without_allowlist():
    script = executor._SCRIPTS_DIR / "Test-Exec.ps1"
    denial = executor._authorize_script(script, NO_LIST_TOOL)
    assert denial is not None
    assert "fail-closed" in denial


def test_run_refuses_unlisted_script_without_spawning():
    # Names a real script that is NOT in the allowlist — must return denial text,
    # never reach subprocess.
    result = asyncio.run(
        executor.run(ALLOWED_TOOL, "run Test-PDAStack.ps1", "private")
    )
    assert "allowed_scripts" in result


def test_run_returns_stub_for_unwired_executor():
    result = asyncio.run(
        executor.run({"executor_type": "browser", "name": "B"}, "x", "open")
    )
    assert "not yet wired" in result
