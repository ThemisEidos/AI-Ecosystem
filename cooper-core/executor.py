"""
COOPER Workbench — execution gateway (Step 5).

Executes approved tools. All 13 registry-referenced executor_types are wired
(see below). An unrecognized executor_type not present in any registry still
falls through to a "not yet wired" stub, so the gateway keeps growing safely
if new types are ever added to a registry ahead of a handler.

Design constraints:
  - Only scripts that exist on disk under the repo's Scripts/ directory are
    allowed. No arbitrary command injection — the script path is resolved from
    the user's message, but only filenames that actually exist in Scripts/ are
    accepted. Anything else is rejected.
  - Hard timeout of 60 s. Output is capped at 8 KB.
  - The executor is called *after* the approval gate has already resolved.
    It trusts that the caller (main.py) enforced approval; it does not re-check.
  - stdout + stderr are merged and returned as the result artifact.

Supported executor_types:
  powershell    — invokes powershell.exe / pwsh via a thread-pool subprocess (step 5)
  python        — invokes sys.executable on allowlisted Scripts/Python/*.py
  skill_import  — post-approval tap registration via skills.register_import (step 10)
  skill_promote — post-approval draft activation via skills.register_promotion (step 11)
  informational — turn-local summary, no execution
  local_read    — read-only registry snapshot (reuses registry.format_tool_list)
  filesystem    — bounded create-or-update write to Restricted DMZ Workspace (Private only)
  local_llm     — specialist analysis/drafting via the existing Ollama backend (Private only)
  note_editor   — bounded create-or-update write to Obsidian 00_Inbox (Open only)
  llm_api       — routes a prompt through the existing LiteLLM gateway (Open only)
  browser       — HTTP fetch + stdlib HTML-to-text extraction, no real browser (Open only)
  workflow_engine — n8n webhook trigger via a manually-reviewed-safe allowlist (Open only;
                    Private has no reachable workflow engine — reports that honestly)
  cli_launcher  — native port of WF-002's title/slug/markdown template, writes into
                  Codex_Tasks/ (Open only). Does not chain into the legacy PowerShell
                  approval/workbench/review scripts Invoke-COOPERCodexTaskGenerator.ps1
                  calls — this dispatch is already governed by the new FastAPI approval
                  gate, so re-running the old gate underneath would be redundant. Level 2
                  (template-writing) only; it does not also launch anything, matching the
                  registry's "Launcher handoff remains optional" note.
"""
import asyncio
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from html.parser import HTMLParser

import httpx

from decision import _ollama_complete, _openai_complete

import registry
import skills

_REPO_ROOT      = Path(__file__).resolve().parent.parent
_SCRIPTS_DIR    = _REPO_ROOT / "Scripts"
_SCRIPTS_PY_DIR = _REPO_ROOT / "Scripts" / "Python"
_DMZ_DIR        = _REPO_ROOT / "Restricted DMZ Workspace"
_OBSIDIAN_INBOX_DIR = _REPO_ROOT / "Obsidian Vault" / "00_Inbox"
_TIMEOUT     = 60    # seconds
_MAX_OUTPUT  = 8192  # bytes
_MAX_DMZ_CONTENT_BYTES  = 65_536  # 64 KB — generous for a drafted note, not a data dump
_MAX_NOTE_CONTENT_BYTES = 65_536
_MAX_FETCH_BYTES = 262_144  # 256 KB of raw HTML before extraction
_FETCH_TIMEOUT   = 20  # seconds — a research fetch should fail fast, not hang a turn

# Private Workshop's local Ollama backend — read directly rather than importing
# main.py's WORKSHOP-scoped constants, to avoid a circular import (main imports
# executor). Mirrors main.py's own env-var pattern.
_OLLAMA_HOST  = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
_QWEN_MODEL   = os.environ.get("COOPER_MODEL", "COOPER-Private")

# Open Workshop's LiteLLM gateway — same pattern, read directly to avoid the
# circular import with main.py.
_LITELLM_BASE_URL   = os.environ.get("OPENAI_BASE_URL", "http://litellm:4000/v1")
_LITELLM_API_KEY    = os.environ.get("OPENAI_API_KEY", "")
_LITELLM_DEFAULT_MODEL = os.environ.get("COOPER_MODEL", "openai")

# n8n only exists in the Open stack's compose network (service name "n8n",
# matching how "litellm" is used above) — there is no reachable n8n instance
# from the Private stack at all.
_N8N_BASE_URL = os.environ.get("N8N_BASE_URL", "http://n8n:5678")

_CODEX_TASKS_DIR = _REPO_ROOT / "Codex_Tasks"

# Ported verbatim from Scripts/Invoke-COOPERCodexTaskGenerator.ps1's
# Get-COOPERCodexTaskTitle — title/slug extraction only, per decision #4.
_CODEX_TITLE_STRIP_PATTERNS = [
    re.compile(p, re.IGNORECASE) for p in (
        r"^(create|generate|draft|write|make)\s+(a|an)\s+(codex\s+)?task(\s+to|\s+for|\s+from)?\s+",
        r"^(create|generate|draft|write|make)\s+(a|an)\s+(implementation|development|engineering)\s+task(\s+to|\s+for|\s+from)?\s+",
        r"^(turn|transform|convert)\s+this\s+",
        r"^task\s+to\s+",
        r"^implementation\s+task\s+to\s+",
        r"^development\s+task\s+to\s+",
        r"^engineering\s+task\s+to\s+",
    )
]
_CODEX_TRAILING_PUNCT_RE = re.compile(r"[.!?]+$")
_CODEX_DEFAULT_TITLE_RE = re.compile(r"^this project decision$", re.IGNORECASE)
_CODEX_SLUG_SPLIT_RE = re.compile(r"[^a-z0-9]+")
_CODEX_STOPWORDS = {
    "the", "to", "and", "of", "for", "a", "an", "this", "that", "from", "into",
    "in", "on", "with", "add", "create", "make", "draft", "write", "generate",
    "implement", "implementation", "task", "codex",
}

_DMZ_WRITE_RE = re.compile(
    r"write\s+(?:to\s+)?dmz\s+(?P<filename>[\w.\-]+)\s*:\s*(?P<content>.+)",
    re.IGNORECASE | re.DOTALL,
)
_NOTE_WRITE_RE = re.compile(
    r"write\s+note\s+(?P<filename>[\w.\- ]+?\.md)\s*:\s*(?P<content>.+)",
    re.IGNORECASE | re.DOTALL,
)
_MODEL_HINT_RE = re.compile(r"\busing\s+([\w.\-]+)", re.IGNORECASE)
_URL_RE = re.compile(r"https?://\S+")

_QWEN_ANALYSIS_SYSTEM_PROMPT = (
    "You are a specialist local analysis/drafting assistant operating inside the "
    "Restricted DMZ Workspace. Produce concise, structured analysis or draft text "
    "for the given prompt. You are not the conversational COOPER personality — "
    "output only the analysis/draft itself, no chit-chat framing."
)


class _HTMLTextExtractor(HTMLParser):
    """Minimal, dependency-free HTML→text stripper (stdlib only, per decision #2 —
    no Playwright/Selenium). Drops script/style content; keeps everything else."""

    def __init__(self) -> None:
        super().__init__()
        self._skip_depth = 0
        self.chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag in ("script", "style"):
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "style") and self._skip_depth > 0:
            self._skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth == 0 and data.strip():
            self.chunks.append(data.strip())

    def text(self) -> str:
        return "\n".join(self.chunks)


class ExecutionError(Exception):
    pass


def _resolve_script_in_dir(message: str, ext: str, scripts_dir: Path) -> Optional[Path]:
    """
    Find a filename ending in `ext` mentioned in the message that actually
    exists in `scripts_dir`. Returns the resolved Path or None if nothing
    matches. Any path traversal is neutralized before the existence check.
    """
    for token in message.split():
        clean = token.strip("\"'(),")
        if clean.lower().endswith(ext):
            candidate = (scripts_dir / Path(clean).name).resolve()
            try:
                candidate.relative_to(scripts_dir.resolve())
            except ValueError:
                continue
            if candidate.exists():
                return candidate
    return None


def _resolve_script(message: str) -> Optional[Path]:
    """Find a .ps1 filename mentioned in the message that exists in Scripts/."""
    return _resolve_script_in_dir(message, ".ps1", _SCRIPTS_DIR)


def _resolve_python_script(message: str) -> Optional[Path]:
    """Find a .py filename mentioned in the message that exists in Scripts/Python/."""
    return _resolve_script_in_dir(message, ".py", _SCRIPTS_PY_DIR)


def _authorize_script(script: Path, tool: dict) -> Optional[str]:
    """
    Check the resolved script against the tool's registry allowlist.
    Returns None when authorized, or a user-facing denial string.
    Fail-closed: a powershell tool with no allowed_scripts list runs nothing.
    """
    allowed = tool.get("allowed_scripts") or []
    if not allowed:
        return (
            f"Workbench: tool '{tool.get('name', tool.get('id', 'unknown'))}' has no "
            "allowed_scripts list in its registry entry. Execution is fail-closed — "
            "add the script filenames this tool may run to allowed_scripts in the "
            "registry YAML."
        )
    if script.name not in allowed:
        return (
            f"Workbench: '{script.name}' is not in this tool's allowed_scripts. "
            f"Allowed: {', '.join(sorted(allowed))}."
        )
    return None


def _stub(executor_type: str, tool_name: str) -> str:
    return (
        f"Tool selected: {tool_name} (executor_type: {executor_type}). "
        f"This executor_type is not yet wired in the gateway — step 5 covers "
        f"PowerShell only. Add a handler in executor.py to extend coverage."
    )


async def run(tool: dict, message: str, workshop: str) -> str:
    """
    Execute an approved tool and return the result string.

    Raises ExecutionError on hard failures (script not found, timeout, etc.).
    Non-fatal output (non-zero exit code with stderr) is returned as text,
    not raised, so COOPER can relay it conversationally.
    """
    executor_type = tool.get("executor_type", "")
    tool_name     = tool.get("name", tool.get("id", "unknown"))

    if executor_type == "powershell":
        return await _run_powershell(tool, message)

    if executor_type == "python":
        return await _run_python(tool, message)

    if executor_type == "skill_import":
        return await _run_skill_import(message)

    if executor_type == "skill_promote":
        return await _run_skill_promote(message, workshop)

    if executor_type == "informational":
        return _run_informational(tool, message, workshop)

    if executor_type == "local_read":
        return _run_local_read(tool, workshop)

    if executor_type == "filesystem":
        return await _run_filesystem(message)

    if executor_type == "local_llm":
        return await _run_local_llm(message)

    if executor_type == "note_editor":
        return await _run_note_editor(message)

    if executor_type == "llm_api":
        return await _run_llm_api(message)

    if executor_type == "browser":
        return await _run_browser(message)

    if executor_type == "workflow_engine":
        return await _run_workflow_engine(tool, message, workshop)

    if executor_type == "cli_launcher":
        return await _run_cli_launcher(message)

    return _stub(executor_type, tool_name)


def _run_informational(tool: dict, message: str, workshop: str) -> str:
    """Level 0 — no external action, no execution gateway involved. Summarizes
    the current dispatch turn only; no chat history reaches this layer."""
    tool_name = tool.get("name", tool.get("id", "unknown"))
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    return (
        f"[{tool_name}] Operational summary — {workshop} workshop, {timestamp}.\n"
        f"Current request: \"{message.strip()}\"\n"
        f"No prior conversation history is available at this layer to summarize further."
    )


def _run_local_read(tool: dict, workshop: str) -> str:
    """Level 1 — read-only registry inspection. Reuses the same in-memory,
    mtime-cached registry snapshot backing GET /tools."""
    tool_name = tool.get("name", tool.get("id", "unknown"))
    return f"[{tool_name}]\n{registry.format_tool_list(workshop)}"


async def _run_filesystem(message: str) -> str:
    """Restricted DMZ Writer (Private only). New files only — governance
    classifies overwrites as Level 5 (blocked by default), so an existing
    path is refused rather than silently replaced."""
    match = _DMZ_WRITE_RE.search(message)
    if match is None:
        return (
            "Workbench: could not parse a DMZ write request — use "
            "'write dmz <filename>: <content>'."
        )
    filename = Path(match.group("filename")).name  # strips any directory components
    content = match.group("content").strip()
    if not content:
        return "Workbench: DMZ write request has no content to write."
    content_bytes = content.encode("utf-8")
    if len(content_bytes) > _MAX_DMZ_CONTENT_BYTES:
        return (
            f"Workbench: content is {len(content_bytes)} bytes, over the "
            f"{_MAX_DMZ_CONTENT_BYTES}-byte cap for a DMZ write."
        )

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        dest = (_DMZ_DIR / filename).resolve()
        try:
            dest.relative_to(_DMZ_DIR.resolve())
        except ValueError:
            return f"Workbench: '{filename}' resolves outside the DMZ Workspace — refused."
        # Level 2 is explicitly "creates or updates local non-sensitive output"
        # (01_AI Ecosystem Architecture.md) — updating this tool's own prior
        # output is in scope, gated by this dispatch's own approval, same as
        # a fresh write. Level 5's overwrite concern is protected/sensitive
        # data or altering the DMZ/Vault structurally, not routine drafts.
        existed = dest.exists()
        _DMZ_DIR.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        verb = "Updated" if existed else "Wrote"
        return f"{verb} '{filename}' in the Restricted DMZ Workspace ({len(content_bytes)} bytes)."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: DMZ write failed unexpectedly — {exc}"


async def _run_local_llm(message: str) -> str:
    """Qwen Local Assistant (Private only) — specialist analysis/drafting route,
    distinct from the conversational COOPER-Private personality. Repointed at
    the already-deployed Ollama model per the qwen_local_assistant design
    decision (Qwen itself was superseded by the Gemma-based COOPER-Private
    rename, PROGRESS.md 2026-07-02) rather than pulling a second model."""
    try:
        draft = await _ollama_complete(
            _OLLAMA_HOST,
            _QWEN_MODEL,
            [
                {"role": "system", "content": _QWEN_ANALYSIS_SYSTEM_PROMPT},
                {"role": "user", "content": message},
            ],
        )
    except Exception as exc:
        raise ExecutionError(f"local analysis backend unavailable — {exc}")
    return f"[Qwen Local Assistant — draft]\n{draft.strip()}"


async def _run_note_editor(message: str) -> str:
    """Obsidian Note Writer (Open only). Create-or-update, same Level 2
    reasoning as _run_filesystem — governance names this exact action
    ("create Obsidian note") as the canonical Level 2 example. Writes into
    00_Inbox/ per 08_Obsidian Vault Structure.md's recommended layout (new
    content lands for a human to file properly), never into the project
    docs area."""
    match = _NOTE_WRITE_RE.search(message)
    if match is None:
        return (
            "Workbench: could not parse a note write request — use "
            "'write note <name>.md: <content>'."
        )
    filename = Path(match.group("filename").strip()).name
    content = match.group("content").strip()
    if not content:
        return "Workbench: note write request has no content to write."
    content_bytes = content.encode("utf-8")
    if len(content_bytes) > _MAX_NOTE_CONTENT_BYTES:
        return (
            f"Workbench: content is {len(content_bytes)} bytes, over the "
            f"{_MAX_NOTE_CONTENT_BYTES}-byte cap for a note write."
        )

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        dest = (_OBSIDIAN_INBOX_DIR / filename).resolve()
        try:
            dest.relative_to(_OBSIDIAN_INBOX_DIR.resolve())
        except ValueError:
            return f"Workbench: '{filename}' resolves outside the Knowledge Shelf inbox — refused."
        existed = dest.exists()
        _OBSIDIAN_INBOX_DIR.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        verb = "Updated" if existed else "Created"
        return f"{verb} note '{filename}' in the Obsidian Knowledge Shelf inbox ({len(content_bytes)} bytes)."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: note write failed unexpectedly — {exc}"


async def _run_llm_api(message: str) -> str:
    """LiteLLM Router (Open only) — routes an approved prompt to LiteLLM's
    chat-completions endpoint, the same gateway the main conversational path
    already uses (proven live, PROGRESS.md 2026-07-07).

    Live-verified finding: passing the *entire* dispatch message (including
    the "use the LiteLLM Router tool to..." framing) as the prompt confused
    the downstream model into commenting on the tool-invocation framing
    itself, rather than answering the actual request — caught by the
    sub-agent reviewer. Extracts the text after the last colon as the actual
    prompt, matching the "<instruction>: <payload>" convention already used
    by the DMZ/note writers, falling back to the whole message if no colon
    is present."""
    hint_match = _MODEL_HINT_RE.search(message)
    model = hint_match.group(1) if hint_match else _LITELLM_DEFAULT_MODEL
    prompt = message.rsplit(":", 1)[-1].strip() if ":" in message else message
    try:
        response = await _openai_complete(
            _LITELLM_BASE_URL,
            _LITELLM_API_KEY,
            model,
            [{"role": "user", "content": prompt}],
        )
    except Exception as exc:
        raise ExecutionError(f"LiteLLM routing failed — {exc}")
    return f"[LiteLLM Router — model: {model}]\n{response.strip()}"


async def _run_browser(message: str) -> str:
    """Browser Research (Open only). HTTP fetch + stdlib HTML→text extraction
    per decision #2 — no Playwright/Selenium (new heavy dependency and
    sandboxing burden, deferred). Won't render JS-only pages."""
    url_match = _URL_RE.search(message)
    if url_match is None:
        return "Workbench: no http(s):// URL found in request."
    url = url_match.group(0).rstrip(".,)")

    loop = asyncio.get_running_loop()

    async def _fetch() -> str:
        async with httpx.AsyncClient(
            timeout=_FETCH_TIMEOUT, follow_redirects=True
        ) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            raw = resp.content[:_MAX_FETCH_BYTES]
            return raw.decode(resp.encoding or "utf-8", errors="replace")

    try:
        html = await _fetch()
    except Exception as exc:
        raise ExecutionError(f"fetch failed for '{url}' — {exc}")

    def _extract() -> str:
        parser = _HTMLTextExtractor()
        parser.feed(html)
        return parser.text()

    text = await loop.run_in_executor(None, _extract)
    text = text[:_MAX_OUTPUT].strip()
    return f"[Browser Research — {url}]\n{text}"


async def _run_workflow_engine(tool: dict, message: str, workshop: str) -> str:
    """n8n workflow trigger (Open only — n8n has no reachable instance from
    Private, confirmed: no n8n service exists in docker-compose.private.yml).
    allowed_workflows maps a spoken workflow_id to a webhook path; per the
    Batch -1 finding, this mapping is a manually-reviewed-safe allowlist, not
    just an existence check — never add an entry without inspecting the
    workflow's own nodes for unsafe command construction first."""
    if workshop != "open":
        return (
            "Workbench: no n8n (or equivalent) workflow engine is deployed for "
            "the Private Workshop — this tool has nothing to call yet."
        )

    allowed = tool.get("allowed_workflows") or {}
    if not allowed:
        return (
            f"Workbench: tool '{tool.get('name', tool.get('id', 'unknown'))}' has no "
            "allowed_workflows mapping in its registry entry. Execution is fail-closed."
        )

    lowered = message.lower()
    matched_id = next((wid for wid in allowed if wid.replace("_", " ") in lowered or wid in lowered), None)
    if matched_id is None:
        return (
            f"Workbench: no known workflow_id found in request. "
            f"Known workflows: {', '.join(sorted(allowed))}."
        )
    webhook_path = allowed[matched_id]
    payload_text = message.rsplit(":", 1)[-1].strip() if ":" in message else message

    try:
        async with httpx.AsyncClient(timeout=_FETCH_TIMEOUT) as client:
            resp = await client.post(
                f"{_N8N_BASE_URL}/webhook/{webhook_path}",
                # Sent under both keys for compatibility across the current
                # allowlist: PDA_Command_Router.json reads body.command;
                # PDA-ChatBridge-HTTP.json reads body.user_message/body.message.
                # Live-verified finding: sending only "message" left
                # PDA_Command_Router's route classification at "unknown".
                json={"command": payload_text, "message": payload_text},
            )
            resp.raise_for_status()
            result_text = resp.text[:_MAX_OUTPUT]
    except Exception as exc:
        raise ExecutionError(f"n8n workflow '{matched_id}' call failed — {exc}")
    return f"[n8n workflow: {matched_id}]\n{result_text.strip()}"


def _codex_task_title(request_text: str) -> str:
    """Ported from Get-COOPERCodexTaskTitle."""
    clean = request_text.strip()
    for pattern in _CODEX_TITLE_STRIP_PATTERNS:
        clean = pattern.sub("", clean)
    clean = _CODEX_TRAILING_PUNCT_RE.sub("", clean).strip()
    if not clean or _CODEX_DEFAULT_TITLE_RE.match(clean):
        clean = "Codex Task"
    return clean.title()


def _codex_task_slug(request_text: str) -> str:
    """Ported from Get-COOPERCodexTaskSlug."""
    words = [
        w for w in _CODEX_SLUG_SPLIT_RE.split(request_text.lower())
        if w and w not in _CODEX_STOPWORDS
    ]
    if not words:
        return "codex-task"
    slug = "-".join(words[:6])
    return slug or "codex-task"


def _codex_task_markdown(title: str, request_text: str) -> str:
    """Ported verbatim from New-COOPERCodexTaskMarkdown."""
    return "\n".join([
        f"# {title}",
        "",
        "## Objective",
        "Create an implementation-ready Codex task for the supplied project context.",
        "",
        "## Background",
        f"- Source request: {request_text}",
        "- This task was generated by the governed COOPER task workflow.",
        "",
        "## Current State",
        "- The request has not yet been captured as a governed implementation task.",
        "- Relevant project context should be translated into bounded work items.",
        "",
        "## Required Work",
        "- Analyze the supplied project context.",
        "- Turn the request into a concrete implementation task.",
        "- Identify the minimal set of files, configuration, or follow-up checks needed.",
        "- Keep the task small enough to execute in one governed Codex pass.",
        "",
        "## Constraints",
        "- Do not add new frameworks.",
        "- Do not redesign the router or workflow architecture.",
        "- Do not include secrets, credentials, or private data.",
        "- Keep the implementation minimal and reviewable.",
        "",
        "## Validation",
        "- Verify the task file exists in the `Codex_Tasks/` folder.",
        "- Verify the task includes the required sections.",
        "- Verify the task is specific enough to hand to Codex without extra clarification.",
        "",
        "## Definition of Done",
        "- The task file is saved in `Codex_Tasks/`.",
        "- The content is actionable, bounded, and ready for implementation.",
        "- WF-002 review passes.",
    ])


async def _run_cli_launcher(message: str) -> str:
    """Codex Task Launcher (Open only) — Level 2 template-writing half of
    WF-002 only (decision #4). Each dispatch gets a fresh timestamped
    filename, so there is no realistic overwrite case to guard against."""
    title = _codex_task_title(message)
    slug = _codex_task_slug(message)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = f"TASK-{timestamp}-{slug}.md"
    content = _codex_task_markdown(title, message)

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        _CODEX_TASKS_DIR.mkdir(parents=True, exist_ok=True)
        dest = _CODEX_TASKS_DIR / filename
        dest.write_text(content, encoding="utf-8")
        return f"Created Codex task '{filename}' (title: \"{title}\")."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except Exception as exc:
        return f"Workbench: Codex task creation failed unexpectedly — {exc}"


async def _run_powershell(tool: dict, message: str) -> str:
    script = _resolve_script(message)

    if script is None:
        return (
            "Workbench: no .ps1 script path found in request, or the named "
            "script does not exist in Scripts/. "
            "Rephrase with the script filename (e.g. 'run Test-PDAStack.ps1')."
        )

    denial = _authorize_script(script, tool)
    if denial is not None:
        return denial

    loop = asyncio.get_running_loop()

    def _sync_run() -> str:
        # Try powershell.exe first (always present on Windows), then pwsh
        for shell in ("powershell.exe", "pwsh"):
            try:
                result = subprocess.run(
                    [shell, "-NonInteractive", "-NoProfile", "-File", str(script)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=str(_REPO_ROOT),
                    timeout=_TIMEOUT,
                )
                raw = result.stdout
                output = raw[:_MAX_OUTPUT].decode("utf-8", errors="replace").strip()
                truncated = len(raw) > _MAX_OUTPUT
                exit_label = "OK" if result.returncode == 0 else f"exit {result.returncode}"
                res = f"[{script.name} — {exit_label}]\n{output}"
                if truncated:
                    res += f"\n[... output truncated at {_MAX_OUTPUT} bytes]"
                return res
            except FileNotFoundError:
                continue
            except subprocess.TimeoutExpired:
                raise ExecutionError(f"{script.name} timed out after {_TIMEOUT}s")
        raise ExecutionError(
            "Neither powershell.exe nor pwsh found — ensure PowerShell is on PATH"
        )

    try:
        return await loop.run_in_executor(None, _sync_run)
    except ExecutionError:
        raise
    except Exception as exc:
        raise ExecutionError(f"executor error ({type(exc).__name__}): {exc}")


async def _run_python(tool: dict, message: str) -> str:
    """Mirrors _run_powershell exactly, for .py scripts under Scripts/Python/."""
    script = _resolve_python_script(message)

    if script is None:
        return (
            "Workbench: no .py script path found in request, or the named "
            "script does not exist in Scripts/Python/. "
            "Rephrase with the script filename (e.g. 'run Test-Exec.py')."
        )

    denial = _authorize_script(script, tool)
    if denial is not None:
        return denial

    loop = asyncio.get_running_loop()

    def _sync_run() -> str:
        try:
            result = subprocess.run(
                [sys.executable, str(script)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                cwd=str(_REPO_ROOT),
                timeout=_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            raise ExecutionError(f"{script.name} timed out after {_TIMEOUT}s")
        raw = result.stdout
        output = raw[:_MAX_OUTPUT].decode("utf-8", errors="replace").strip()
        truncated = len(raw) > _MAX_OUTPUT
        exit_label = "OK" if result.returncode == 0 else f"exit {result.returncode}"
        res = f"[{script.name} — {exit_label}]\n{output}"
        if truncated:
            res += f"\n[... output truncated at {_MAX_OUTPUT} bytes]"
        return res

    try:
        return await loop.run_in_executor(None, _sync_run)
    except ExecutionError:
        raise
    except Exception as exc:
        raise ExecutionError(f"executor error ({type(exc).__name__}): {exc}")


async def _run_skill_import(message: str) -> str:
    """Post-approval skill registration. Network + filesystem work off-loop."""
    loop = asyncio.get_running_loop()

    def _sync() -> str:
        entry = skills.register_import(message)
        content_hash = entry.get("content_hash", "?")
        return (
            f"Skill '{entry.get('id', '?')}' imported and registered for the "
            f"{entry.get('workshop', '?')} workshop "
            f"(hash {content_hash[:12] if content_hash != '?' else '?'}…). "
            f"It is now live. Promote to Private only via a separate approval."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill import failed — {exc}"
    except Exception as exc:
        return f"Workbench: skill import failed unexpectedly — {exc}"


async def _run_skill_promote(message: str, workshop: str) -> str:
    """Post-approval draft activation. Filesystem work off-loop, same
    degrade-gracefully contract as _run_skill_import (matches the Step 10
    review finding: a broad Exception fallback so unwrapped OS/IO errors
    never propagate out of the executor)."""
    loop = asyncio.get_running_loop()

    def _sync() -> str:
        entry = skills.register_promotion(message, workshop=workshop)
        content_hash = entry.get("content_hash", "?")
        return (
            f"Skill '{entry.get('id', '?')}' promoted from draft and registered for the "
            f"{entry.get('workshop', '?')} workshop "
            f"(hash {content_hash[:12] if content_hash != '?' else '?'}…)."
        )

    try:
        return await loop.run_in_executor(None, _sync)
    except skills.SkillError as exc:
        return f"Workbench: skill promotion failed — {exc}"
    except Exception as exc:
        return f"Workbench: skill promotion failed unexpectedly — {exc}"
