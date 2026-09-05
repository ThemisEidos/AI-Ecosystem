import asyncio
from pathlib import Path

import pytest

import executor
import registry
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


def test_resolve_named_script_finds_existing_script():
    script = executor._resolve_named_script("Test-Exec.ps1", executor._SCRIPTS_DIR)
    assert script is not None
    assert script.name == "Test-Exec.ps1"


def test_resolve_named_script_returns_none_for_unknown_script():
    assert executor._resolve_named_script("Definitely-Not-Real-XYZ.ps1", executor._SCRIPTS_DIR) is None


def test_resolve_named_script_neutralizes_traversal():
    script = executor._resolve_named_script("../../Test-Exec.ps1", executor._SCRIPTS_DIR)
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
    result = asyncio.run(
        executor.run(ALLOWED_TOOL, "run it", "private", {"script": "Test-PDAStack.ps1"})
    )
    assert "allowed_scripts" in result


def test_run_returns_stub_for_unwired_executor():
    result = asyncio.run(
        executor.run({"executor_type": "totally_unknown_type", "name": "X"}, "x", "open", {})
    )
    assert "not yet wired" in result


def test_skill_import_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_import",
        lambda *a, **kw: {"id": "tap-skill", "workshop": "open",
                          "content_hash": "ab" * 32},
    )
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "tap-skill", "tap_url": "https://x/y"}
    ))
    assert "tap-skill" in out and "imported" in out.lower()


def test_skill_import_executor_reports_failure(monkeypatch):
    def boom(*a, **kw):
        raise skills_mod.SkillError("bad tap")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert "failed" in out.lower() and "bad tap" in out


def test_skill_import_executor_degrades_on_unexpected_exception(monkeypatch):
    def boom(*a, **kw):
        raise RuntimeError("connection reset by peer")
    monkeypatch.setattr(skills_mod, "register_import", boom)
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert isinstance(out, str)
    assert "unexpectedly" in out.lower()
    assert "connection reset by peer" in out


def test_skill_import_executor_defends_malformed_entry_shape(monkeypatch):
    monkeypatch.setattr(skills_mod, "register_import", lambda *a, **kw: {})
    tool = {"id": "import_skill", "name": "Import Skill", "executor_type": "skill_import"}
    out = asyncio.run(executor.run(
        tool, "import", "open", {"skill_name": "x", "tap_url": "https://x/y"}
    ))
    assert isinstance(out, str)
    assert "?" in out


def test_skill_promote_executor(monkeypatch):
    monkeypatch.setattr(
        skills_mod, "register_promotion",
        lambda name, **kw: {"id": "stack-health-check", "workshop": kw.get("workshop", "open"),
                            "content_hash": "cd" * 32},
    )
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(
        tool, "promote", "open", {"skill_name": "stack-health-check"}
    ))
    assert "stack-health-check" in out and "promoted" in out.lower()


def test_skill_promote_executor_reports_failure(monkeypatch):
    def boom(name, **kw):
        raise skills_mod.SkillError("no draft named 'x'")
    monkeypatch.setattr(skills_mod, "register_promotion", boom)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert "failed" in out.lower() and "no draft named" in out


def test_skill_promote_executor_degrades_on_unexpected_exception(monkeypatch):
    def boom(name, **kw):
        raise RuntimeError("disk full")
    monkeypatch.setattr(skills_mod, "register_promotion", boom)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert isinstance(out, str)
    assert "unexpectedly" in out.lower()
    assert "disk full" in out


def test_skill_promote_executor_defends_malformed_entry_shape(monkeypatch):
    monkeypatch.setattr(skills_mod, "register_promotion", lambda name, **kw: {})
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    out = asyncio.run(executor.run(tool, "promote", "open", {"skill_name": "x"}))
    assert isinstance(out, str)
    assert "?" in out


def test_skill_promote_executor_passes_active_workshop(monkeypatch):
    seen = {}
    def spy(name, **kw):
        seen["workshop"] = kw.get("workshop")
        return {"id": "x", "workshop": kw.get("workshop"), "content_hash": "ef" * 32}
    monkeypatch.setattr(skills_mod, "register_promotion", spy)
    tool = {"id": "promote_skill", "name": "Promote Skill", "executor_type": "skill_promote"}
    asyncio.run(executor.run(tool, "promote", "private", {"skill_name": "x"}))
    assert seen["workshop"] == "private"


PYTHON_ALLOWED_TOOL = {
    "id": "python_private",
    "name": "Python Private Runner",
    "executor_type": "python",
    "allowed_scripts": ["Test-Exec.py"],
}


def test_python_executor_runs_allowed_script():
    result = asyncio.run(
        executor.run(PYTHON_ALLOWED_TOOL, "run it", "private", {"script": "Test-Exec.py"})
    )
    assert "Test-Exec.py" in result
    assert "OK" in result


def test_python_executor_refuses_unlisted_script_without_spawning():
    tool = {"id": "python_private", "name": "Python Private Runner", "executor_type": "python"}
    result = asyncio.run(executor.run(tool, "run it", "private", {"script": "Test-Exec.py"}))
    assert "fail-closed" in result


def test_filesystem_executor_writes_new_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "notes.txt", "content": "hello world"},
    ))
    assert "Wrote 'notes.txt'" in out
    assert (tmp_path / "notes.txt").read_text() == "hello world"


def test_filesystem_executor_updates_existing_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    (tmp_path / "existing.txt").write_text("original")
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "existing.txt", "content": "replacement"},
    ))
    assert "Updated 'existing.txt'" in out
    assert (tmp_path / "existing.txt").read_text() == "replacement"


def test_filesystem_executor_neutralizes_traversal(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_DMZ_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "../../etc/passwd", "content": "pwned"},
    ))
    assert not (tmp_path.parent / "etc").exists()


def test_filesystem_executor_rejects_empty_content():
    out = asyncio.run(executor.run(
        {"executor_type": "filesystem"}, "write", "private",
        {"filename": "x.txt", "content": ""},
    ))
    assert "no content" in out.lower()


def test_local_llm_executor_calls_ollama(monkeypatch):
    async def fake_complete(base_url, model, messages, **kw):
        assert messages[0]["role"] == "system"
        assert messages[1]["content"] == "analyze this"
        return "  drafted analysis text  "
    monkeypatch.setattr(executor, "_ollama_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "local_llm"}, "run", "private", {"prompt": "analyze this"}
    ))
    assert "Qwen Local Assistant" in out
    assert "drafted analysis text" in out


def test_local_llm_executor_raises_execution_error_on_backend_failure(monkeypatch):
    async def boom(base_url, model, messages, **kw):
        raise RuntimeError("connection refused")
    monkeypatch.setattr(executor, "_ollama_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "local_llm"}, "run", "private", {"prompt": "analyze this"}
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection refused" in str(exc)


def test_note_editor_creates_new_note(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_OBSIDIAN_INBOX_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": "some idea content"},
    ))
    assert "Created note 'idea.md'" in out
    assert (tmp_path / "idea.md").read_text() == "some idea content"


def test_note_editor_updates_existing_note(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_OBSIDIAN_INBOX_DIR", tmp_path)
    (tmp_path / "idea.md").write_text("old")
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": "new content"},
    ))
    assert "Updated note 'idea.md'" in out
    assert (tmp_path / "idea.md").read_text() == "new content"


def test_note_editor_rejects_empty_content():
    out = asyncio.run(executor.run(
        {"executor_type": "note_editor"}, "write", "open",
        {"filename": "idea.md", "content": ""},
    ))
    assert "no content" in out.lower()


def test_llm_api_executor_routes_through_litellm(monkeypatch):
    async def fake_complete(base_url, api_key, model, messages, **kw):
        assert model == "claude-sonnet"
        return "  routed response  "
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open",
        {"prompt": "summarize this", "model": "claude-sonnet"},
    ))
    assert "routed response" in out
    assert "claude-sonnet" in out


def test_llm_api_executor_defaults_model_when_unspecified(monkeypatch):
    seen = {}
    async def fake_complete(base_url, api_key, model, messages, **kw):
        seen["model"] = model
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open", {"prompt": "summarize this"}
    ))
    assert seen["model"] == executor._LITELLM_DEFAULT_MODEL


def test_llm_api_executor_passes_prompt_through_clean(monkeypatch):
    seen = {}
    async def fake_complete(base_url, api_key, model, messages, **kw):
        seen["prompt"] = messages[0]["content"]
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "llm_api"}, "run", "open", {"prompt": "say the word banana"}
    ))
    assert seen["prompt"] == "say the word banana"


def test_llm_api_executor_raises_execution_error_on_failure(monkeypatch):
    async def boom(base_url, api_key, model, messages, **kw):
        raise RuntimeError("502 bad gateway")
    monkeypatch.setattr(executor, "_openai_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "llm_api"}, "run", "open", {"prompt": "hi"}
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "502 bad gateway" in str(exc)


def test_browser_executor_extracts_text_from_fetched_html(monkeypatch):
    class FakeResponse:
        content = b"<html><body><script>ignoreMe()</script><p>Hello world</p></body></html>"
        encoding = "utf-8"
        def raise_for_status(self): pass

    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def get(self, url): return FakeResponse()

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    out = asyncio.run(executor.run(
        {"executor_type": "browser"}, "research", "open",
        {"urls": ["https://example.com/page"]},
    ))
    assert "Hello world" in out
    assert "ignoreMe" not in out
    assert "https://example.com/page" in out


def test_browser_executor_rejects_no_urls():
    out = asyncio.run(executor.run(
        {"executor_type": "browser"}, "look something up", "open", {"urls": []}
    ))
    assert "no http" in out.lower()


def test_browser_executor_raises_execution_error_on_fetch_failure(monkeypatch):
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def get(self, url): raise RuntimeError("connection reset")

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    try:
        asyncio.run(executor.run(
            {"executor_type": "browser"}, "research", "open",
            {"urls": ["https://example.com"]},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection reset" in str(exc)


WORKFLOW_TOOL = {
    "id": "n8n_general_workflows",
    "name": "n8n General Workflows",
    "executor_type": "workflow_engine",
    "allowed_workflows": {"pda_command_router": "pda-command-router"},
}


def test_workflow_engine_refuses_on_private_workshop():
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "private", {"workflow": "pda_command_router", "payload": "hi"}
    ))
    assert "no n8n" in out.lower()


def test_workflow_engine_fails_closed_without_allowlist():
    tool = {"id": "n8n_general_workflows", "name": "n8n", "executor_type": "workflow_engine"}
    out = asyncio.run(executor.run(
        tool, "run", "open", {"workflow": "pda_command_router", "payload": "hi"}
    ))
    assert "fail-closed" in out


def test_workflow_engine_rejects_unknown_workflow_id():
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "open", {"workflow": "some_other_flow", "payload": "hi"}
    ))
    assert "no known workflow_id" in out.lower()


def test_workflow_engine_calls_n8n_webhook(monkeypatch):
    class FakeResponse:
        text = '{"status":"ok"}'
        def raise_for_status(self): pass

    seen = {}
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, url, json):
            seen["url"] = url
            seen["json"] = json
            return FakeResponse()

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    out = asyncio.run(executor.run(
        WORKFLOW_TOOL, "run", "open",
        {"workflow": "pda_command_router", "payload": "do the thing"},
    ))
    assert "pda_command_router" in out
    assert "ok" in out
    assert seen["url"].endswith("/webhook/pda-command-router")
    assert seen["json"] == {"command": "do the thing", "message": "do the thing"}


def test_workflow_engine_raises_execution_error_on_call_failure(monkeypatch):
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, url, json): raise RuntimeError("connection refused")

    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: FakeClient())
    try:
        asyncio.run(executor.run(
            WORKFLOW_TOOL, "run", "open",
            {"workflow": "pda_command_router", "payload": "hi"},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "connection refused" in str(exc)


def test_codex_task_title_strips_leading_phrase():
    assert executor._codex_task_title("create a task to fix the login bug") == "Fix The Login Bug"


def test_codex_task_title_defaults_when_empty():
    # Ported verbatim from the PowerShell original: after stripping the leading
    # phrase, "this project decision" is the documented default-trigger case.
    assert executor._codex_task_title("create a task for this project decision") == "Codex Task"


def test_codex_task_slug_filters_stopwords_and_caps_at_six():
    slug = executor._codex_task_slug("create a task to fix the login bug page for real")
    assert slug == "fix-login-bug-page-real"


def test_codex_task_slug_defaults_when_no_words():
    assert executor._codex_task_slug("the a to and") == "codex-task"


def test_codex_task_markdown_contains_required_sections():
    md = executor._codex_task_markdown("Fix Login Bug", "fix the login bug")
    for section in ("## Objective", "## Background", "## Required Work",
                     "## Constraints", "## Validation", "## Definition of Done"):
        assert section in md
    assert "fix the login bug" in md


def test_cli_launcher_writes_task_file(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_CODEX_TASKS_DIR", tmp_path)
    out = asyncio.run(executor.run(
        {"executor_type": "cli_launcher"}, "create", "open",
        {"request": "fix the login bug"},
    ))
    assert "Created Codex task" in out
    files = list(tmp_path.glob("TASK-*.md"))
    assert len(files) == 1
    assert "Fix The Login Bug" in files[0].read_text()
    assert "fix-login-bug" in files[0].name


def test_informational_executor_summarizes_current_turn():
    tool = {"id": "status_summary", "name": "Status Summary", "executor_type": "informational"}
    out = asyncio.run(executor.run(tool, "give me a status summary", "open"))
    assert "Status Summary" in out
    assert "give me a status summary" in out
    assert "open" in out


def test_local_read_executor_reuses_registry_snapshot(monkeypatch):
    monkeypatch.setattr(registry, "format_tool_list", lambda ws: f"snapshot-for-{ws}")
    tool = {"id": "registry_inspector", "name": "Registry Inspector", "executor_type": "local_read"}
    out = asyncio.run(executor.run(tool, "what's in the registry?", "private"))
    assert "Registry Inspector" in out
    assert "snapshot-for-private" in out


def test_fabric_catalog_finds_shipped_patterns():
    catalog = executor._fabric_catalog()
    assert "report-summary" in catalog
    assert "security-triage" in catalog
    assert catalog["report-summary"].parent.name == "Reporting"


def test_fabric_catalog_empty_when_dir_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_FABRIC_DIR", tmp_path / "nope")
    assert executor._fabric_catalog() == {}


def test_resolve_pattern_matches_exact_key():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("report-summary", catalog)
    assert key == "report-summary"
    assert path.parent.name == "Reporting"


def test_resolve_pattern_matches_loosely_spaced_name():
    catalog = executor._fabric_catalog()
    key, _ = executor._resolve_pattern("Report Summary", catalog)
    assert key == "report-summary"


def test_resolve_pattern_falls_back_to_category():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("security", catalog)
    assert path.parent.name == "Security"


def test_resolve_pattern_returns_none_when_unmatched():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("something nobody named", catalog)
    assert key is None and path is None


def test_resolve_pattern_returns_none_for_empty_name():
    catalog = executor._fabric_catalog()
    key, path = executor._resolve_pattern("", catalog)
    assert key is None and path is None


def test_fabric_fill_pattern_substitutes_known_and_defaults():
    out = executor._fill_pattern(
        "A={{content_input}} B={{pattern_name}} C={{audience}} D={{mystery}}",
        {"content_input": "raw", "pattern_name": "report-summary"},
    )
    assert "A=raw" in out
    assert "B=report-summary" in out
    assert "C=the owner" in out
    assert "D=unspecified" in out


def test_fabric_executor_open_routes_through_litellm(monkeypatch):
    captured = {}

    async def fake_complete(base_url, api_key, model, messages, **kw):
        captured["prompt"] = messages[1]["content"]
        return "  finished report  "
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "report-summary", "content_input": "we shipped the link checker today"},
    ))
    assert "finished report" in out
    assert "report-summary" in out
    assert "we shipped the link checker today" in captured["prompt"]
    assert "{{" not in captured["prompt"]


def test_fabric_executor_private_routes_through_ollama(monkeypatch):
    async def fake_complete(base_url, model, messages, **kw):
        return "local draft"
    monkeypatch.setattr(executor, "_ollama_complete", fake_complete)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "private",
        {"pattern_name": "security-triage", "content_input": "odd inbound traffic on port 8788"},
    ))
    assert "local draft" in out
    assert "security-triage" in out


def test_fabric_executor_applies_overrides(monkeypatch):
    captured = {}

    async def fake_complete(base_url, api_key, model, messages, **kw):
        captured["prompt"] = messages[1]["content"]
        return "ok"
    monkeypatch.setattr(executor, "_openai_complete", fake_complete)
    asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {
            "pattern_name": "report-summary",
            "content_input": "quarterly numbers",
            "audience": "the board",
            "tone": "formal",
        },
    ))
    assert "the board" in captured["prompt"]
    assert "formal" in captured["prompt"]


def test_fabric_executor_lists_patterns_when_name_unresolved():
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "something nobody named", "content_input": "hi"},
    ))
    assert "report-summary" in out
    assert "security-triage" in out
    assert "use this exact" not in out.lower()


def test_fabric_executor_rejects_oversized_input(monkeypatch):
    monkeypatch.setattr(executor, "_MAX_FABRIC_INPUT_BYTES", 10)
    out = asyncio.run(executor.run(
        {"executor_type": "fabric_pattern"}, "run", "open",
        {"pattern_name": "report-summary", "content_input": "x" * 50},
    ))
    assert "over the" in out


def test_fabric_executor_raises_execution_error_on_backend_failure(monkeypatch):
    async def boom(base_url, api_key, model, messages, **kw):
        raise RuntimeError("gateway down")
    monkeypatch.setattr(executor, "_openai_complete", boom)
    try:
        asyncio.run(executor.run(
            {"executor_type": "fabric_pattern"}, "run", "open",
            {"pattern_name": "report-summary", "content_input": "text"},
        ))
        assert False, "expected ExecutionError"
    except executor.ExecutionError as exc:
        assert "gateway down" in str(exc)


def test_fabric_fill_pattern_prefers_provided_value_over_default():
    out = executor._fill_pattern("{{tone}}", {"tone": "formal"})
    assert out == "formal"


def test_file_edit_writes_within_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    args = {
        "filename": "State/LinkAudit/links.csv",
        "content": "url,status\nhttps://example.com,ok\n",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    result = asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert "wrote" in result.lower() or "updated" in result.lower()
    written = (tmp_path / "State/LinkAudit/links.csv").read_text()
    assert written == args["content"]


def test_file_edit_refuses_path_outside_write_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    args = {
        "filename": "PDA-Runtime/.env",
        "content": "malicious",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert not (tmp_path / "PDA-Runtime/.env").exists()


def test_file_edit_refuses_path_traversal_even_if_it_resolves_into_scope(tmp_path, monkeypatch):
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    (tmp_path / "State/LinkAudit").mkdir(parents=True)
    args = {
        "filename": "State/LinkAudit/../../PDA-Runtime/.env",
        "content": "malicious",
        "write_scope": ["State/LinkAudit/links.csv"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))


def test_file_edit_refuses_when_write_scope_missing_or_empty():
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit(
            {}, "edit", "open", {"filename": "x.csv", "content": "y", "write_scope": []}
        ))


def test_file_edit_refuses_when_write_scope_entry_itself_traverses_out(tmp_path, monkeypatch):
    """Adversarial case: even if the caller's write_scope list itself contains
    a traversal entry (write_scope is caller-supplied, not LLM-supplied, but
    defense in depth assumes it could be malformed), the resolve()-based
    containment re-check must still refuse — the string-equality match alone
    is not sufficient once the entry itself escapes the repo root."""
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    args = {
        "filename": "../outside.txt",
        "content": "malicious",
        "write_scope": ["../outside.txt"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert not (tmp_path.parent / "outside.txt").exists()


def test_file_edit_refuses_absolute_path_filename(tmp_path, monkeypatch):
    """Adversarial case: an absolute-path filename that also happens to
    literally match a write_scope entry (both caller-supplied) must still be
    refused — pathlib's `/` operator replaces the whole path when the RHS is
    absolute, so a naive `_REPO_ROOT / filename` join would silently escape
    containment without the resolve()+relative_to() re-check."""
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    absolute_target = str(tmp_path.parent / "escaped.txt")
    args = {
        "filename": absolute_target,
        "content": "malicious",
        "write_scope": [absolute_target],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert not Path(absolute_target).exists()


def test_file_edit_refuses_self_cancelling_traversal_in_write_scope(tmp_path, monkeypatch):
    """Reviewer-reproduced Critical: filename and write_scope both literally
    read 'State/LinkAudit/../../PDA-Runtime/.env'. A plain string-equality
    check (check 1) passes trivially — they're the identical string. A naive
    resolve()-based check (check 2 alone) ALSO passes, because the two '..'
    segments cancel 'State/LinkAudit' out and the result
    (repo_root/PDA-Runtime/.env) is still nominally under repo_root — even
    though it is not what write_scope='State/LinkAudit/links.csv'-shaped
    entries are supposed to mean, and is a completely different file than
    the literal entry visually names. The '..'-segment rejection (check 0)
    must refuse this outright, before either of the other checks run."""
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    (tmp_path / "PDA-Runtime").mkdir(parents=True)
    (tmp_path / "PDA-Runtime" / ".env").write_text("original-secret")
    args = {
        "filename": "State/LinkAudit/../../PDA-Runtime/.env",
        "content": "malicious",
        "write_scope": ["State/LinkAudit/../../PDA-Runtime/.env"],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))
    assert (tmp_path / "PDA-Runtime" / ".env").read_text() == "original-secret"


def test_file_edit_refuses_null_byte_filename_as_execution_error(tmp_path, monkeypatch):
    """Important: a null byte in filename (with a matching write_scope entry,
    so it clears check 1) makes Path.resolve() raise a raw ValueError. That
    must surface as executor.ExecutionError, not escape as a bare stdlib
    exception a caller (e.g. Task 6's job runner) might not be catching."""
    monkeypatch.setattr(executor, "_REPO_ROOT", tmp_path)
    poisoned = "State/LinkAudit/li\x00nks.csv"
    args = {
        "filename": poisoned,
        "content": "malicious",
        "write_scope": [poisoned],
    }
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit({}, "edit", "open", args))


def test_file_edit_refuses_non_list_write_scope():
    with pytest.raises(executor.ExecutionError):
        asyncio.run(executor._run_file_edit(
            {}, "edit", "open",
            {"filename": "x.csv", "content": "y", "write_scope": "State/LinkAudit/links.csv"},
        ))


def test_file_edit_wired_in_handlers_and_run():
    assert "file_edit" in executor.WIRED_EXECUTOR_TYPES
    assert executor._HANDLERS["file_edit"] is not None


# ── web_search (Step 14c) ────────────────────────────────────────────────
class _FakeSearxResponse:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status_code = status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


def _fake_searx_client(response):
    class _Client:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def get(self, url, params=None):
            _Client.last_url = url
            _Client.last_params = params
            return response

    return _Client


def test_web_search_returns_normalized_results(monkeypatch):
    payload = {"results": [
        {"title": "Broker A", "url": "https://a.example", "content": "sells data"},
        {"title": "Broker B", "url": "https://b.example", "content": "collects data"},
    ]}
    client = _fake_searx_client(_FakeSearxResponse(payload))
    monkeypatch.setattr(executor.httpx, "AsyncClient", lambda **kw: client())

    results = asyncio.run(executor._run_web_search("data broker opt out"))

    assert results == [
        {"title": "Broker A", "url": "https://a.example", "snippet": "sells data"},
        {"title": "Broker B", "url": "https://b.example", "snippet": "collects data"},
    ]
    assert client.last_params["format"] == "json"
    assert client.last_params["q"] == "data broker opt out"


def test_web_search_caps_at_max_results(monkeypatch):
    payload = {"results": [
        {"title": f"R{i}", "url": f"https://{i}.example", "content": "x"}
        for i in range(25)
    ]}
    monkeypatch.setattr(
        executor.httpx, "AsyncClient",
        lambda **kw: _fake_searx_client(_FakeSearxResponse(payload))(),
    )
    results = asyncio.run(executor._run_web_search("q", max_results=3))
    assert len(results) == 3


def test_web_search_returns_empty_list_when_no_results(monkeypatch):
    monkeypatch.setattr(
        executor.httpx, "AsyncClient",
        lambda **kw: _fake_searx_client(_FakeSearxResponse({"results": []}))(),
    )
    assert asyncio.run(executor._run_web_search("q")) == []


def test_web_search_raises_execution_error_on_http_failure(monkeypatch):
    monkeypatch.setattr(
        executor.httpx, "AsyncClient",
        lambda **kw: _fake_searx_client(_FakeSearxResponse({}, status=502))(),
    )
    with pytest.raises(executor.ExecutionError, match="web_search"):
        asyncio.run(executor._run_web_search("q"))


def test_web_search_raises_execution_error_on_malformed_json(monkeypatch):
    monkeypatch.setattr(
        executor.httpx, "AsyncClient",
        lambda **kw: _fake_searx_client(_FakeSearxResponse(ValueError("bad json")))(),
    )
    with pytest.raises(executor.ExecutionError, match="web_search"):
        asyncio.run(executor._run_web_search("q"))


def test_web_search_skips_results_missing_a_url(monkeypatch):
    payload = {"results": [
        {"title": "No URL", "content": "x"},
        {"title": "Good", "url": "https://good.example", "content": "y"},
    ]}
    monkeypatch.setattr(
        executor.httpx, "AsyncClient",
        lambda **kw: _fake_searx_client(_FakeSearxResponse(payload))(),
    )
    results = asyncio.run(executor._run_web_search("q"))
    assert results == [{"title": "Good", "url": "https://good.example", "snippet": "y"}]


def test_web_search_is_wired_in_handlers():
    assert "web_search" in executor.WIRED_EXECUTOR_TYPES
