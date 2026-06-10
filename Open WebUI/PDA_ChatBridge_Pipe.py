"""
title: COOPER
author: Codex
version: 1.0.0
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from pydantic import BaseModel, Field
except ImportError:  # pragma: no cover - local validation fallback only
    class BaseModel:  # type: ignore[override]
        def __init__(self, **kwargs):
            for key, value in kwargs.items():
                setattr(self, key, value)

    def Field(default=None, description: str = ""):
        return default


class Pipe:
    class Valves(BaseModel):
        N8N_WEBHOOK_URL: str = Field(
            default="http://host.docker.internal:5678/webhook/pda-chat-bridge-http",
            description="n8n production webhook endpoint for the PDA bridge.",
        )
        HTTP_TIMEOUT_SECONDS: float = Field(
            default=30.0,
            description="Timeout for the webhook call in seconds.",
        )
        STATE_FILE: str = Field(
            default="/app/backend/data/pda/pda-chat-bridge-pending.json",
            description="File used to persist pending confirmations.",
        )
        PENDING_TTL_SECONDS: int = Field(
            default=900,
            description="How long a pending confirmation stays valid.",
        )
        CONFIRM_PHRASES: str = Field(
            default="confirm dispatch,confirm,approve dispatch,approve,yes dispatch,yes,dispatch it,go ahead",
            description="Comma-separated phrases that count as explicit approval.",
        )
        RESPONSE_LABEL: str = Field(
            default="PDA bridge response",
            description="Label shown before the JSON response block.",
        )
        DEBUG_MODE: bool = Field(
            default=False,
            description="When enabled, append raw bridge JSON to the rendered response for debugging.",
        )
        DEBUG_LOG_FILE: str = Field(
            default="/app/backend/data/pda/pda-chat-bridge-debug.jsonl",
            description="JSONL log file for raw request and bridge payload diagnostics.",
        )
        TITLE_SAFE_RESPONSE: str = Field(
            default="COOPER",
            description="Short harmless response returned for Open WebUI title-generation or internal prompts.",
        )

    def __init__(self):
        self.valves = self.Valves()
        self._state_lock = asyncio.Lock()

    def pipes(self):
        return [{"id": "cooper", "name": "COOPER"}]

    async def pipe(self, body: dict, __user__: dict | None = None, __request__: Any = None) -> str:
        session_key = self._get_session_key(body, __user__)
        conversation_context = self._extract_conversation_context(body, __user__, session_key)
        latest_message = self._extract_user_message(body)
        explicit_confirm = self._extract_confirm_flag(body)
        internal_prompt_reason = self._detect_internal_prompt(body, latest_message)
        now = time.time()

        if internal_prompt_reason:
            internal_payload = {
                "bridge_status": "ignored_internal_prompt",
                "dispatch_status": "ignored",
                "requires_confirmation": False,
                "response_text": self.valves.TITLE_SAFE_RESPONSE,
                "next_action": "No dispatch was attempted for this internal Open WebUI request.",
                "ignored_reason": internal_prompt_reason,
            }
            self._append_debug_log(
                event_type="internal_prompt_ignored",
                session_key=session_key,
                request_body=body,
                response_payload=internal_payload,
            )
            return self._render_internal_response(internal_payload)

        async with self._state_lock:
            pending_state = self._load_state()
            self._expire_pending(pending_state, now)
            pending_entry = pending_state.get(session_key)

            confirm_dispatch = explicit_confirm
            dispatch_message = latest_message
            if not confirm_dispatch and pending_entry and self._is_confirmation_message(latest_message):
                confirm_dispatch = True
                dispatch_message = str(pending_entry.get("user_message", latest_message))

        bridge_payload = await self._call_bridge(dispatch_message, confirm_dispatch, conversation_context)
        self._append_debug_log(
            event_type="bridge_response",
            session_key=session_key,
            request_body={
                "user_message": dispatch_message,
                "confirm_dispatch": confirm_dispatch,
                **conversation_context,
            },
            response_payload=bridge_payload,
        )

        async with self._state_lock:
            pending_state = self._load_state()
            self._expire_pending(pending_state, now)

            if bridge_payload.get("requires_confirmation") and bridge_payload.get("dispatch_status") == "not_dispatched":
                pending_state[session_key] = {
                    "user_message": dispatch_message,
                    "saved_at": now,
                }
            else:
                pending_state.pop(session_key, None)
            self._save_state(pending_state)

        return self._render_response(bridge_payload, confirm_dispatch)

    def _detect_internal_prompt(self, body: dict, latest_message: str) -> str:
        message_text = latest_message.strip()
        if not message_text:
            return ""

        metadata_values = self._collect_metadata_strings(body)
        metadata_text = "\n".join(metadata_values)

        title_patterns = [
            r"generate a concise,\s*3-5 word title",
            r"###\s*chat history",
            r'json format:\s*\{\s*"title"',
            r"write a short title",
            r"chat title",
        ]
        if any(re.search(pattern, message_text, re.IGNORECASE) for pattern in title_patterns):
            return "title_generation_content_pattern"

        if re.search(r"\b(title_generation|chat_title|auto_title|conversation_title)\b", metadata_text, re.IGNORECASE):
            return "title_generation_metadata"

        if re.search(r"\b(system_prompt|internal_prompt|title_prompt|task_type)\b", metadata_text, re.IGNORECASE) and re.search(
            r"\b(title|internal|system)\b", metadata_text, re.IGNORECASE
        ):
            return "internal_prompt_metadata"

        return ""

    def _extract_user_message(self, body: dict) -> str:
        candidate = body.get("user_message")
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()

        for message in reversed(self._as_list(body.get("messages"))):
            if not isinstance(message, dict):
                continue
            if message.get("role") != "user":
                continue
            content = message.get("content")
            text = self._content_to_text(content)
            if text.strip():
                return text.strip()

        for key in ("message", "prompt", "input"):
            candidate = body.get(key)
            if isinstance(candidate, str) and candidate.strip():
                return candidate.strip()

        return ""

    def _extract_confirm_flag(self, body: dict) -> bool:
        if "confirm_dispatch" in body:
            value = body.get("confirm_dispatch")
            if isinstance(value, bool):
                return value
            if isinstance(value, str):
                return value.strip().lower() in {"1", "true", "yes", "y", "on"}
            if isinstance(value, (int, float)):
                return bool(value)
        return False

    def _get_session_key(self, body: dict, __user__: dict | None) -> str:
        candidates = [
            body.get("chat_id"),
            body.get("conversation_id"),
            body.get("session_id"),
            body.get("id"),
        ]
        if isinstance(__user__, dict):
            candidates.extend(
                [
                    __user__.get("id"),
                    __user__.get("email"),
                    __user__.get("name"),
                ]
            )

        for candidate in candidates:
            if candidate:
                return str(candidate)
        return "default"

    def _extract_conversation_context(self, body: dict, __user__: dict | None, session_key: str) -> Dict[str, str]:
        conversation_id = ""
        session_id = ""
        user_id = ""
        title = ""

        for key in ("conversation_id", "chat_id"):
            candidate = body.get(key)
            if isinstance(candidate, str) and candidate.strip():
                conversation_id = candidate.strip()
                break

        candidate = body.get("session_id")
        if isinstance(candidate, str) and candidate.strip():
            session_id = candidate.strip()

        candidate = body.get("user_id")
        if isinstance(candidate, str) and candidate.strip():
            user_id = candidate.strip()

        candidate = body.get("conversation_title") or body.get("title")
        if isinstance(candidate, str) and candidate.strip():
            title = candidate.strip()

        chat = body.get("chat")
        if isinstance(chat, dict):
            if not conversation_id and isinstance(chat.get("id"), str) and chat["id"].strip():
                conversation_id = chat["id"].strip()
            if not title and isinstance(chat.get("title"), str) and chat["title"].strip():
                title = chat["title"].strip()

        if isinstance(__user__, dict) and not user_id:
            for candidate in (__user__.get("id"), __user__.get("email"), __user__.get("name")):
                if isinstance(candidate, str) and candidate.strip():
                    user_id = candidate.strip()
                    break

        if not conversation_id:
            conversation_id = session_key
        if not session_id:
            session_id = session_key

        context = {
            "conversation_id": conversation_id,
            "session_id": session_id,
            "user_id": user_id,
            "conversation_title": title,
        }
        return {key: value for key, value in context.items() if value}

    def _is_confirmation_message(self, text: str) -> bool:
        normalized = re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()
        if not normalized:
            return False

        for phrase in self._confirmation_phrases():
            phrase_norm = re.sub(r"[^a-z0-9]+", " ", phrase.lower()).strip()
            if not phrase_norm:
                continue
            if normalized == phrase_norm:
                return True
            if normalized.startswith(f"{phrase_norm} "):
                return True

        return False

    def _confirmation_phrases(self) -> List[str]:
        phrases = [part.strip() for part in self.valves.CONFIRM_PHRASES.split(",")]
        return [phrase for phrase in phrases if phrase]

    async def _call_bridge(self, user_message: str, confirm_dispatch: bool, conversation_context: Dict[str, str]) -> Dict[str, Any]:
        payload = {
            "user_message": user_message,
            "confirm_dispatch": confirm_dispatch,
        }
        payload.update(conversation_context)

        def _post() -> Dict[str, Any]:
            request = urllib.request.Request(
                self.valves.N8N_WEBHOOK_URL,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(request, timeout=self.valves.HTTP_TIMEOUT_SECONDS) as response:
                    raw = response.read().decode("utf-8").strip()
                    if not raw:
                        return {}
                    data = json.loads(raw)
                    return data if isinstance(data, dict) else {}
            except urllib.error.HTTPError as error:
                error_body = ""
                try:
                    error_body = error.read().decode("utf-8").strip()
                except Exception:
                    error_body = ""
                return {
                    "response_text": "PDA bridge request failed.",
                    "recommended_command": "",
                    "intent": "",
                    "confidence": 0,
                    "requires_confirmation": False,
                    "dispatch_status": "blocked",
                    "next_action": error_body or f"HTTP error {error.code} from the n8n webhook.",
                    "bridge_status": "fail_closed",
                }
            except Exception as error:
                return {
                    "response_text": "PDA bridge request failed.",
                    "recommended_command": "",
                    "intent": "",
                    "confidence": 0,
                    "requires_confirmation": False,
                    "dispatch_status": "blocked",
                    "next_action": str(error),
                    "bridge_status": "fail_closed",
                }

        data = await asyncio.to_thread(_post)
        if isinstance(data, dict):
            return data

        return {
            "response_text": "PDA bridge returned a non-object response.",
            "recommended_command": "",
            "intent": "",
            "confidence": 0,
            "requires_confirmation": False,
            "dispatch_status": "blocked",
            "next_action": "Inspect the webhook response payload.",
            "bridge_status": "fail_closed",
        }

    def _render_response(self, payload: Dict[str, Any], confirmed: bool) -> str:
        result = payload if isinstance(payload, dict) else {}
        rendered = self._render_friendly_response(result, confirmed)
        if self.valves.DEBUG_MODE:
            rendered += f"\n\n{self.valves.RESPONSE_LABEL}:\n```json\n{json.dumps(result, indent=2, ensure_ascii=False)}\n```"
        return rendered

    def _render_internal_response(self, payload: Dict[str, Any]) -> str:
        response_text = str(payload.get("response_text", "")).strip()
        if response_text:
            return response_text
        return self.valves.TITLE_SAFE_RESPONSE

    def _render_friendly_response(self, result: Dict[str, Any], confirmed: bool) -> str:
        recommended_command = str(result.get("recommended_command", "")).strip()
        dispatch_status = str(result.get("dispatch_status", "")).strip()
        requires_confirmation = bool(result.get("requires_confirmation"))
        response_text = str(result.get("response_text", "")).strip()
        next_action = str(result.get("next_action", "")).strip()
        bridge_status = str(result.get("bridge_status", "")).strip()
        task_id = self._first_non_empty(
            result.get("latest_task_id"),
            result.get("task_id"),
            result.get("dispatch_id"),
        )
        result_path = self._first_non_empty(
            result.get("latest_result_path"),
            result.get("result_artifact_path"),
            result.get("result_path"),
        )

        lines: List[str] = []
        if bridge_status == "fail_closed" or dispatch_status == "blocked":
            lines.append("PDA bridge is currently unavailable.")
            if next_action:
                lines.append(next_action)
            elif response_text:
                lines.append(response_text)
            return "\n".join(lines)

        if requires_confirmation and dispatch_status == "not_dispatched" and not confirmed:
            if recommended_command:
                lines.append(f"Recommended command: {recommended_command}. Reply `confirm dispatch` to submit.")
            elif response_text:
                lines.append(response_text)
            else:
                lines.append("This request needs confirmation before dispatch.")
            if next_action and "confirm dispatch" not in next_action.lower():
                lines.append(next_action)
            return "\n".join(lines)

        if confirmed or dispatch_status == "submitted":
            if recommended_command:
                lines.append(f"Dispatched {recommended_command}.")
            else:
                lines.append("Dispatch submitted through the governed PDA handoff.")
            if task_id:
                lines.append(f"Task queued: {task_id}.")
            if result_path:
                lines.append(f"Result path: `{result_path}`.")
            else:
                lines.append("Check PDA dashboard or task status for results.")
            return " ".join(lines)

        if result_path:
            if response_text:
                lines.append(response_text)
            lines.append(f"Result path: `{result_path}`.")
            if next_action:
                lines.append(next_action)
            return "\n".join(lines)

        if response_text:
            lines.append(response_text)
        if recommended_command and not any("Recommended command:" in line for line in lines):
            lines.append(f"Recommended command: {recommended_command}.")
        if next_action:
            lines.append(next_action)

        if lines:
            return "\n".join(lines)

        return "PDA bridge response received."

    def _first_non_empty(self, *values: Any) -> str:
        for value in values:
            if isinstance(value, str) and value.strip():
                return value.strip()
        return ""

    def _collect_metadata_strings(self, value: Any, prefix: str = "") -> List[str]:
        collected: List[str] = []
        if isinstance(value, dict):
            for key, item in value.items():
                next_prefix = f"{prefix}.{key}" if prefix else str(key)
                collected.extend(self._collect_metadata_strings(item, next_prefix))
        elif isinstance(value, list):
            for index, item in enumerate(value):
                next_prefix = f"{prefix}[{index}]"
                collected.extend(self._collect_metadata_strings(item, next_prefix))
        elif isinstance(value, str):
            if prefix:
                collected.append(f"{prefix}={value}")
            else:
                collected.append(value)
        return collected

    def _append_debug_log(
        self,
        event_type: str,
        session_key: str,
        request_body: Dict[str, Any],
        response_payload: Dict[str, Any],
    ) -> None:
        try:
            path = Path(self.valves.DEBUG_LOG_FILE)
            path.parent.mkdir(parents=True, exist_ok=True)
            record = {
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "event_type": event_type,
                "session_key": session_key,
                "request_body": request_body,
                "response_payload": response_payload,
            }
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        except Exception:
            return

    def _load_state(self) -> Dict[str, Dict[str, Any]]:
        path = Path(self.valves.STATE_FILE)
        if not path.exists():
            return {}

        try:
            with path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict):
                return data
        except Exception:
            return {}
        return {}

    def _save_state(self, state: Dict[str, Dict[str, Any]]) -> None:
        path = Path(self.valves.STATE_FILE)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = path.with_suffix(path.suffix + ".tmp")
        with temp_path.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, ensure_ascii=False)
        os.replace(temp_path, path)

    def _expire_pending(self, state: Dict[str, Dict[str, Any]], now: float) -> None:
        ttl = float(self.valves.PENDING_TTL_SECONDS)
        stale_keys = []
        for key, entry in state.items():
            saved_at = entry.get("saved_at", 0)
            try:
                saved_at_value = float(saved_at)
            except (TypeError, ValueError):
                saved_at_value = 0
            if now - saved_at_value > ttl:
                stale_keys.append(key)

        for key in stale_keys:
            state.pop(key, None)

    def _as_list(self, value: Any) -> List[Any]:
        if isinstance(value, list):
            return value
        return []

    def _content_to_text(self, content: Any) -> str:
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: List[str] = []
            for item in content:
                if isinstance(item, str):
                    parts.append(item)
                elif isinstance(item, dict):
                    if isinstance(item.get("text"), str):
                        parts.append(item["text"])
                    elif isinstance(item.get("content"), str):
                        parts.append(item["content"])
            return "\n".join(parts)
        if content is None:
            return ""
        return str(content)
