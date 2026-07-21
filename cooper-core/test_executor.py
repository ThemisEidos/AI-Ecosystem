import asyncio
from pathlib import Path

import executor
import skills as skills_mod

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


def test_skill_import_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_import",
        lambda message, **kw: {"id": "tap-skill", "workshop": "open",
                               "content_hash": "ab" * 32},
    )
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(
        executor.run(tool, "import skill tap-skill from https://x/y", "open")
    )
    assert "tap-skill" in out and "imported" in out.lower()


def test_skill_import_executor_reports_failure(monkeypatch):
    def boom(message, **kw):
        raise skills_mod.SkillError("bad tap")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(
        executor.run(tool, "import skill x from https://x/y", "open")
    )
    assert "failed" in out.lower() and "bad tap" in out


def test_skill_import_executor_degrades_on_unexpected_exception(monkeypatch):
    # register_import() can hit a raw subprocess/network/IO exception that
    # skills.py never wraps in SkillError. The executor must still never raise
    # — it degrades to a chat-facing string, same contract as _run_powershell's
    # broad except Exception fallback.
    def boom(message, **kw):
        raise RuntimeError("connection reset by peer")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(
        executor.run(tool, "import skill x from https://x/y", "open")
    )
    assert isinstance(out, str)
    assert "unexpectedly" in out.lower()
    assert "connection reset by peer" in out


def test_skill_import_executor_defends_malformed_entry_shape(monkeypatch):
    # register_import() returning a dict missing expected keys must not raise
    # KeyError inside the executor's success path — .get(..., "?") fallback.
    monkeypatch.setattr(skills_mod, "register_import", lambda message, **kw: {})
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(
        executor.run(tool, "import skill x from https://x/y", "open")
    )
    assert isinstance(out, str)
    assert "?" in out
