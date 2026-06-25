from __future__ import annotations

import asyncio
import importlib.util
import tempfile
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("PDA_ChatBridge_Pipe.py")
SPEC = importlib.util.spec_from_file_location("pda_chat_bridge_pipe", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)
Pipe = MODULE.Pipe


def make_pipe() -> Pipe:
    pipe = Pipe()
    temp_dir = Path(tempfile.mkdtemp(prefix="pda-chat-bridge-pipe-"))
    pipe.valves.STATE_FILE = str(temp_dir / "state.json")
    pipe.valves.DEBUG_LOG_FILE = str(temp_dir / "debug.jsonl")
    pipe.valves.DEBUG_MODE = False
    return pipe


def run(coro):
    return asyncio.run(coro)


def test_normal_reporter_request() -> None:
    pipe = make_pipe()
    calls = []

    async def fake_call(message, confirm_dispatch, conversation_context):
        calls.append((message, confirm_dispatch, conversation_context))
        return {
            "response_text": "Recommended command: /reporter. Confirm to dispatch.",
            "recommended_command": "/reporter",
            "intent": "report",
            "confidence": 0.98,
            "requires_confirmation": True,
            "dispatch_status": "not_dispatched",
            "next_action": "Reply with confirmation to submit through the governed handoff.",
            "bridge_status": "ready",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    body = {
        "messages": [{"role": "user", "content": "generate a report on my latest tasks"}],
        "chat_id": "chat-normal",
    }

    rendered = run(pipe.pipe(body))
    assert "Recommended command: /reporter." in rendered
    assert "confirm dispatch" in rendered
    assert "```json" not in rendered
    assert len(calls) == 1


def test_pipe_exposes_cooper_pipe_identity() -> None:
    pipe = make_pipe()
    entries = pipe.pipes()

    assert entries == [
        {"id": "cooper", "name": "COOPER"},
        {"id": "cooper_private", "name": "COOPER - Private"},
    ]
    assert pipe.valves.TITLE_SAFE_RESPONSE == "COOPER"


def test_private_selection_sets_private_workshop_context() -> None:
    pipe = make_pipe()
    calls = []

    async def fake_call(message, confirm_dispatch, conversation_context):
        calls.append((message, confirm_dispatch, conversation_context))
        return {
            "response_text": "Recommended command: /status.",
            "recommended_command": "/status",
            "intent": "status",
            "confidence": 1.0,
            "requires_confirmation": False,
            "dispatch_status": "not_dispatched",
            "next_action": "Check system status.",
            "bridge_status": "ready",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    body = {
        "messages": [{"role": "user", "content": "show status"}],
        "chat_id": "chat-private-model",
        "model": "cooper_private",
    }

    rendered = run(pipe.pipe(body))
    assert "Recommended command: /status." in rendered
    assert len(calls) == 1
    assert calls[0][2]["selected_model_identity"] == "COOPER - Private"
    assert calls[0][2]["selected_model_id"] == "cooper_private"
    assert calls[0][2]["workshop_mode"] == "Private Workshop"
    assert calls[0][2]["workshop_identity"] == "COOPER - Private"


def test_confirm_dispatch_replays_pending_message() -> None:
    pipe = make_pipe()
    calls = []

    async def fake_call(message, confirm_dispatch, conversation_context):
        calls.append((message, confirm_dispatch, conversation_context))
        if confirm_dispatch:
            return {
                "response_text": "Dispatched via governed PDA handoff using /reporter.",
                "recommended_command": "/reporter",
                "intent": "report",
                "confidence": 0.99,
                "requires_confirmation": False,
                "dispatch_status": "submitted",
                "latest_task_id": "08254f3b",
                "next_action": "Check PDA dashboard or task status for results.",
                "bridge_status": "submitted",
            }
        return {
            "response_text": "Recommended command: /reporter. Confirm to dispatch.",
            "recommended_command": "/reporter",
            "intent": "report",
            "confidence": 0.99,
            "requires_confirmation": True,
            "dispatch_status": "not_dispatched",
            "next_action": "Reply with confirmation to submit through the governed handoff.",
            "bridge_status": "ready",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    initial_body = {
        "messages": [{"role": "user", "content": "generate a report for this conversation"}],
        "chat_id": "chat-confirm",
    }
    confirm_body = {
        "messages": [{"role": "user", "content": "confirm dispatch"}],
        "chat_id": "chat-confirm",
    }

    run(pipe.pipe(initial_body))
    rendered = run(pipe.pipe(confirm_body))

    assert len(calls) == 2
    assert calls[1][0] == "generate a report for this conversation"
    assert calls[1][1] is True
    assert "Dispatched /reporter." in rendered
    assert "Task queued: 08254f3b." in rendered
    assert "```json" not in rendered


def test_title_generation_prompt_is_ignored() -> None:
    pipe = make_pipe()

    async def should_not_call(*args, **kwargs):
        raise AssertionError("Internal title prompt should not call the bridge.")

    pipe._call_bridge = should_not_call  # type: ignore[method-assign]
    body = {
        "messages": [
            {
                "role": "user",
                "content": 'Generate a concise, 3-5 word title for this conversation.\n### Chat History\nJSON format: { "title": "..." }',
            }
        ],
        "chat_id": "chat-title",
        "task_type": "title_generation",
    }

    rendered = run(pipe.pipe(body))
    assert rendered == "COOPER"


def test_fail_closed_response_is_human_readable() -> None:
    pipe = make_pipe()

    async def fake_call(message, confirm_dispatch, conversation_context):
        return {
            "response_text": "PDA bridge request failed.",
            "recommended_command": "",
            "intent": "",
            "confidence": 0,
            "requires_confirmation": False,
            "dispatch_status": "blocked",
            "next_action": "Start Scripts/Start-PDAWebhookServer.ps1 and retry the request.",
            "bridge_status": "fail_closed",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    body = {"messages": [{"role": "user", "content": "status of my latest report"}], "chat_id": "chat-fail"}
    rendered = run(pipe.pipe(body))
    assert "PDA bridge is currently unavailable." in rendered
    assert "Start Scripts/Start-PDAWebhookServer.ps1" in rendered
    assert "```json" not in rendered


def test_completed_task_result_path_is_rendered() -> None:
    pipe = make_pipe()

    async def fake_call(message, confirm_dispatch, conversation_context):
        return {
            "response_text": "Latest result for this conversation is available.",
            "recommended_command": "/reporter",
            "intent": "status_lookup",
            "confidence": 1,
            "requires_confirmation": False,
            "dispatch_status": "not_dispatched",
            "latest_result_path": r"C:\repo\PDA-Tasks\results\08254f3b-result.json",
            "next_action": "Open the result artifact for details.",
            "bridge_status": "ready",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    body = {"messages": [{"role": "user", "content": "what happened to my last report?"}], "chat_id": "chat-result"}
    rendered = run(pipe.pipe(body))
    assert "Latest result for this conversation is available." in rendered
    assert "Result path: `C:\\repo\\PDA-Tasks\\results\\08254f3b-result.json`." in rendered


def test_workspace_context_is_forwarded() -> None:
    pipe = make_pipe()
    calls = []

    async def fake_call(message, confirm_dispatch, conversation_context):
        calls.append((message, confirm_dispatch, conversation_context))
        return {
            "response_text": "Current roadmap phase: Phase 8 - Open WebUI Workspace Knowledge Layer.",
            "recommended_command": "",
            "intent": "roadmap_state",
            "confidence": 1,
            "requires_confirmation": False,
            "dispatch_status": "not_dispatched",
            "next_action": "",
            "bridge_status": "ready",
        }

    pipe._call_bridge = fake_call  # type: ignore[method-assign]
    body = {
        "messages": [{"role": "user", "content": "Using the AI Ecosystem Governance knowledge collection, what is the current roadmap phase?"}],
        "chat_id": "chat-workspace-context",
        "knowledge_context": {
            "collection_name": "AI Ecosystem Governance",
            "summary": "Phase 8 is current.",
        },
    }

    run(pipe.pipe(body))

    assert len(calls) == 1
    assert calls[0][2]["workspace_context_available"] == "true"
    assert calls[0][2]["workspace_context_label"] == "AI Ecosystem Governance"
    assert "Phase 8 is current." in calls[0][2]["workspace_context_summary"]


if __name__ == "__main__":
    test_normal_reporter_request()
    test_pipe_exposes_cooper_pipe_identity()
    test_confirm_dispatch_replays_pending_message()
    test_title_generation_prompt_is_ignored()
    test_fail_closed_response_is_human_readable()
    test_completed_task_result_path_is_rendered()
    test_workspace_context_is_forwarded()
    print("PASS")
