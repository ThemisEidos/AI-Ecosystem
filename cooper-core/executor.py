"""
COOPER Workbench — execution gateway (Step 5).

Executes approved tools. All 14 registry-referenced executor_types are wired
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
  fabric_pattern — applies a PDA-Fabric prompt pattern to model-supplied content on
                  the workshop's own backend (both workshops; Private stays local)
  file_edit     — bounded write to a caller-supplied write_scope allowlist (Step 14b).
                  NOT registered in any tool registry and never LLM-selectable — the
                  job runner (jobs.py's run_job, not yet built as of this handler's
                  addition) calls _run_file_edit directly, post-approval, passing its
                  own write_scope. Containment is checked against that dynamic list,
                  not a fixed module-level directory constant like every other handler.
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
_FABRIC_DIR = _REPO_ROOT / "PDA-Fabric"
_TIMEOUT     = 60    # seconds
_MAX_OUTPUT  = 8192  # bytes
_MAX_DMZ_CONTENT_BYTES  = 65_536  # 64 KB — generous for a drafted note, not a data dump
_MAX_NOTE_CONTENT_BYTES = 65_536
_MAX_FETCH_BYTES = 262_144  # 256 KB of raw HTML before extraction
_FETCH_TIMEOUT   = 20  # seconds — a research fetch should fail fast, not hang a turn

_MAX_FABRIC_INPUT_BYTES = 65_536  # same cap as the note/DMZ writers
_MAX_FILE_EDIT_CONTENT_BYTES = 262_144  # 256 KB — a job artifact, not a chat draft

# The shipped patterns' optional knobs. Anything a pattern asks for that the
# caller didn't supply resolves to "unspecified" rather than leaving a raw
# {{placeholder}} in the prompt sent to the model.
_FABRIC_DEFAULTS = {
    "audience": "the owner",
    "focus": "the main point of the input",
    "tone": "direct and neutral",
    "priority": "normal",
}
_FABRIC_PLACEHOLDER_RE = re.compile(r"\{\{([a-z_]+)\}\}")
_FABRIC_SYSTEM_PROMPT = (
    "You are COOPER's Fabric pattern processor. Follow the pattern's Instructions "
    "section exactly and produce only the finished artifact — no preamble, no "
    "commentary about the pattern itself."
)

# WIRED_EXECUTOR_TYPES (read by the registry-walk test — M1 — to assert every
# registry tool maps to a real handler, not a stub) is defined near the
# bottom of this file, derived from the _HANDLERS dispatch table.

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


def _resolve_named_script(name: str, scripts_dir: Path) -> Optional[Path]:
    """Resolve a script filename named directly in validated args against
    scripts_dir. Any path traversal is neutralized before the existence
    check (Path(...).name strips directories; relative_to confirms
    containment)."""
    clean = Path(name).name
    if not clean:
        return None
    candidate = (scripts_dir / clean).resolve()
    try:
        candidate.relative_to(scripts_dir.resolve())
    except ValueError:
        return None
    return candidate if candidate.exists() else None


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


async def run(tool: dict, message: str, workshop: str, args: Optional[dict] = None) -> str:
    """
    Execute an approved tool and return the result string.

    Raises ExecutionError on hard failures (script not found, timeout, etc.).
    Non-fatal output (non-zero exit code with stderr) is returned as text,
    not raised, so COOPER can relay it conversationally.
    """
    executor_type = tool.get("executor_type", "")
    tool_name     = tool.get("name", tool.get("id", "unknown"))
    args = args or {}

    handler = _HANDLERS.get(executor_type)
    if handler is None:
        return _stub(executor_type, tool_name)

    result = handler(tool, message, workshop, args)
    if asyncio.iscoroutine(result):
        return await result
    return result


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


def _normalize(text: str) -> str:
    """Lowercase, punctuation-to-space — so 'Report Summary', 'report-summary'
    and 'report_summary' all compare equal. Deliberately lenient: naming a
    pattern must never require exact syntax (Gotchas 2026-08-04)."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def _fabric_catalog() -> dict:
    """Map pattern key (file stem, lowercased) -> pattern file path. Layout is
    PDA-Fabric/<Category>/<pattern-name>.md."""
    catalog = {}
    if not _FABRIC_DIR.is_dir():
        return catalog
    for path in sorted(_FABRIC_DIR.glob("*/*.md")):
        catalog[path.stem.lower()] = path
    return catalog


def _resolve_pattern(name: str, catalog: dict):
    """Match a single name/phrase (the model's pattern_name arg) against the
    catalog: exact/loose key match first (longest key first, so a two-word
    name beats a one-word category), then category-name fallback."""
    norm = f" {_normalize(name)} "
    if norm.strip():
        for key in sorted(catalog, key=len, reverse=True):
            if f" {_normalize(key)} " in norm:
                return key, catalog[key]
        for key in sorted(catalog):
            path = catalog[key]
            if f" {_normalize(path.parent.name)} " in norm:
                return key, path
    return None, None


def _fill_pattern(template: str, values: dict) -> str:
    def _sub(match):
        key = match.group(1)
        if key in values:
            return str(values[key])
        return _FABRIC_DEFAULTS.get(key, "unspecified")
    return _FABRIC_PLACEHOLDER_RE.sub(_sub, template)


async def _run_filesystem(args: dict) -> str:
    """Restricted DMZ Writer (Private only). New files only — governance
    classifies overwrites as Level 5 (blocked by default), so an existing
    path is refused rather than silently replaced."""
    filename = Path(str(args.get("filename", ""))).name
    content = str(args.get("content", "")).strip()
    if not filename or not content:
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


async def _run_local_llm(args: dict) -> str:
    """Qwen Local Assistant (Private only) — specialist analysis/drafting route."""
    prompt = str(args.get("prompt", "")).strip()
    if not prompt:
        return "Workbench: no prompt supplied for local analysis."
    try:
        draft = await _ollama_complete(
            _OLLAMA_HOST, _QWEN_MODEL,
            [
                {"role": "system", "content": _QWEN_ANALYSIS_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        )
    except Exception as exc:
        raise ExecutionError(f"local analysis backend unavailable — {exc}")
    return f"[Qwen Local Assistant — draft]\n{draft.strip()}"


async def _run_note_editor(args: dict) -> str:
    """Obsidian Note Writer (Open only). Create-or-update, same Level 2
    reasoning as _run_filesystem. Writes into 00_Inbox/ per 08_Obsidian
    Vault Structure.md's recommended layout."""
    filename = Path(str(args.get("filename", "")).strip()).name
    content = str(args.get("content", "")).strip()
    if not filename or not content:
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


async def _run_fabric_pattern(args: dict, workshop: str) -> str:
    """Fabric Pattern Writer (both workshops). Applies a PDA-Fabric prompt
    pattern to the model-supplied content and returns the filled artifact.
    The Fabric layer was specified in the governance corpus and never wired
    until Step 14a.

    Runs on the workshop's OWN backend — Private's content never leaves the
    machine, matching _run_local_llm's boundary."""
    catalog = _fabric_catalog()
    if not catalog:
        return "Workbench: no Fabric patterns are installed under PDA-Fabric/."

    pattern_name = str(args.get("pattern_name", ""))
    key, path = _resolve_pattern(pattern_name, catalog)
    if key is None:
        listing = ", ".join(f"{k} ({catalog[k].parent.name})" for k in sorted(catalog))
        return (
            "Workbench: no matching Fabric pattern found for "
            f"'{pattern_name}'. Available patterns: {listing}."
        )

    content = str(args.get("content_input", "")).strip()
    if not content:
        return f"Workbench: Fabric pattern '{key}' has no input content to work from."
    size = len(content.encode("utf-8"))
    if size > _MAX_FABRIC_INPUT_BYTES:
        return (
            f"Workbench: input is {size} bytes, over the "
            f"{_MAX_FABRIC_INPUT_BYTES}-byte cap for a Fabric pattern."
        )

    values = dict(_FABRIC_DEFAULTS)
    for knob in ("audience", "focus", "tone", "priority"):
        if args.get(knob):
            values[knob] = str(args[knob])
    values.update({
        "content_input":    content,
        "pattern_name":     key,
        "pattern_category": path.parent.name,
    })
    prompt = _fill_pattern(path.read_text(encoding="utf-8"), values)
    messages = [
        {"role": "system", "content": _FABRIC_SYSTEM_PROMPT},
        {"role": "user",   "content": prompt},
    ]
    try:
        if workshop == "open":
            filled = await _openai_complete(
                _LITELLM_BASE_URL, _LITELLM_API_KEY, _LITELLM_DEFAULT_MODEL, messages
            )
        else:
            filled = await _ollama_complete(_OLLAMA_HOST, _QWEN_MODEL, messages)
    except Exception as exc:
        raise ExecutionError(f"Fabric pattern '{key}' failed — {exc}")
    return f"[Fabric — {key} ({path.parent.name})]\n{filled.strip()[:_MAX_OUTPUT]}"


async def _run_llm_api(args: dict) -> str:
    """LiteLLM Router (Open only) — routes an approved prompt to LiteLLM's
    chat-completions endpoint. args.prompt is the clean instruction text
    with no tool-invocation framing (the 2026-07-21 'framing text sent as
    prompt' bug class dies with the regex it required)."""
    model = args.get("model") or _LITELLM_DEFAULT_MODEL
    prompt = str(args.get("prompt", "")).strip()
    if not prompt:
        return "Workbench: LiteLLM Router request has no prompt to route."
    try:
        response = await _openai_complete(
            _LITELLM_BASE_URL, _LITELLM_API_KEY, model,
            [{"role": "user", "content": prompt}],
        )
    except Exception as exc:
        raise ExecutionError(f"LiteLLM routing failed — {exc}")
    return f"[LiteLLM Router — model: {model}]\n{response.strip()}"


async def _run_browser(args: dict) -> str:
    """Browser Research (Open only). HTTP fetch + stdlib HTML→text extraction
    per decision #2 — no Playwright/Selenium. Won't render JS-only pages."""
    urls = args.get("urls") or []
    url = str(urls[0]).strip().rstrip(".,)") if urls else ""
    if not url.startswith(("http://", "https://")):
        return "Workbench: no http(s):// URL found in request."

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


async def _run_workflow_engine(tool: dict, args: dict, workshop: str) -> str:
    """n8n workflow trigger (Open only — no reachable instance from
    Private). allowed_workflows maps a workflow id to a webhook path; per
    the Batch -1 finding, this mapping is a manually-reviewed-safe
    allowlist, not just an existence check."""
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

    workflow_id = str(args.get("workflow", ""))
    if workflow_id not in allowed:
        return (
            f"Workbench: no known workflow_id found in request. "
            f"Known workflows: {', '.join(sorted(allowed))}."
        )
    webhook_path = allowed[workflow_id]
    payload_text = str(args.get("payload") or "")

    try:
        async with httpx.AsyncClient(timeout=_FETCH_TIMEOUT) as client:
            resp = await client.post(
                f"{_N8N_BASE_URL}/webhook/{webhook_path}",
                json={"command": payload_text, "message": payload_text},
            )
            resp.raise_for_status()
            result_text = resp.text[:_MAX_OUTPUT]
    except Exception as exc:
        raise ExecutionError(f"n8n workflow '{workflow_id}' call failed — {exc}")
    return f"[n8n workflow: {workflow_id}]\n{result_text.strip()}"


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


async def _run_cli_launcher(args: dict) -> str:
    """Codex Task Launcher (Open only) — Level 2 template-writing half of
    WF-002 only. Each dispatch gets a fresh timestamped filename."""
    request_text = str(args.get("request", ""))
    title = _codex_task_title(request_text)
    slug = _codex_task_slug(request_text)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = f"TASK-{timestamp}-{slug}.md"
    content = _codex_task_markdown(title, request_text)

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


async def _run_powershell(tool: dict, args: dict) -> str:
    script_name = str(args.get("script", ""))
    script = _resolve_named_script(script_name, _SCRIPTS_DIR)

    if script is None:
        return (
            f"Workbench: script '{script_name}' does not exist in Scripts/. "
            "Rephrase with the script filename (e.g. 'Test-PDAStack.ps1')."
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


async def _run_python(tool: dict, args: dict) -> str:
    """Mirrors _run_powershell exactly, for .py scripts under Scripts/Python/."""
    script_name = str(args.get("script", ""))
    script = _resolve_named_script(script_name, _SCRIPTS_PY_DIR)

    if script is None:
        return (
            f"Workbench: script '{script_name}' does not exist in Scripts/Python/. "
            "Rephrase with the script filename (e.g. 'Test-Exec.py')."
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


async def _run_skill_import(args: dict) -> str:
    """Post-approval skill registration. Network + filesystem work off-loop."""
    loop = asyncio.get_running_loop()
    skill_name = str(args.get("skill_name", ""))
    tap_url = str(args.get("tap_url", ""))

    def _sync() -> str:
        entry = skills.register_import(skill_name, tap_url)
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


async def _run_skill_promote(args: dict, workshop: str) -> str:
    """Post-approval draft activation. Filesystem work off-loop, same
    degrade-gracefully contract as _run_skill_import."""
    loop = asyncio.get_running_loop()
    skill_name = str(args.get("skill_name", ""))

    def _sync() -> str:
        entry = skills.register_promotion(skill_name, workshop=workshop)
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


async def _run_file_edit(tool: dict, message: str, workshop: str, args: dict) -> str:
    """Job-runner file writer (Step 14b). Not registered in any tool registry
    and never chat-reachable — this is a capability the job runner (jobs.py's
    run_job) invokes directly, post-approval, with its own caller-supplied
    write_scope. It takes the full (tool, message, workshop, args) signature
    directly, unlike the other handlers' inner _run_xxx(args) helpers, because
    the caller invokes it as a plain function rather than only through
    _HANDLERS/run().

    Unlike every other handler in this file, the allowed write location is
    NOT a fixed module-level constant — it is args["write_scope"], a
    List[str] of exact relative paths from repo root, supplied by the
    trusted CALLER (never by an LLM: the model never sees or sets
    write_scope). A write is permitted only if `filename` exactly string-
    matches one entry in write_scope — no glob, no prefix match, no
    directory-traversal resolution is ever treated as a match.

    Containment is enforced twice, deliberately:
      1. Cheap string equality: filename must literally be a member of
         write_scope. This alone already defeats a traversal string like
         '../../PDA-Runtime/.env' when write_scope only names
         'State/LinkAudit/links.csv' — the strings simply don't match.
      2. A resolve()-based re-check against _REPO_ROOT (the same
         .resolve() + relative_to() containment technique _run_filesystem
         and _run_note_editor use against their own fixed directories),
         confirming the resolved destination is still inside the repo root.
         This is defense in depth for the case write_scope itself is ever
         malformed or absolute-path-like — Path's `/` operator silently
         replaces the whole path when the right-hand side is absolute, so
         an absolute filename that happens to string-match an equally
         absolute write_scope entry would otherwise slip past check 1 only
         to land wherever the absolute path says, not under the repo.
    """
    filename = str(args.get("filename", "")).strip()
    write_scope = args.get("write_scope")
    content = args.get("content")

    if not isinstance(write_scope, list) or not write_scope:
        raise ExecutionError(
            "file_edit: write_scope is missing, empty, or not a list — refusing "
            f"to write '{filename}' with no caller-supplied allowlist."
        )
    if not filename:
        raise ExecutionError("file_edit: no filename supplied.")
    if content is None:
        raise ExecutionError(f"file_edit: no content supplied for '{filename}'.")
    content = str(content)
    content_bytes = content.encode("utf-8")
    if len(content_bytes) > _MAX_FILE_EDIT_CONTENT_BYTES:
        raise ExecutionError(
            f"file_edit: content for '{filename}' is {len(content_bytes)} bytes, "
            f"over the {_MAX_FILE_EDIT_CONTENT_BYTES}-byte cap."
        )

    # Check 1 — cheap string-equality match against the caller's allowlist,
    # before any filesystem resolution happens at all.
    if filename not in write_scope:
        raise ExecutionError(
            f"file_edit: '{filename}' is not in the caller-supplied write_scope "
            f"({', '.join(sorted(str(s) for s in write_scope))}) — refused."
        )

    # Check 2 — resolve()-based containment re-check against the repo root,
    # defense in depth against a malformed/absolute write_scope entry (see
    # docstring above). Path.resolve() also collapses any '..' segments and
    # follows symlinks, so a traversal or symlink trick that somehow still
    # produced a string match at check 1 is caught here too.
    repo_root = _REPO_ROOT.resolve()
    dest = (repo_root / filename).resolve()
    try:
        dest.relative_to(repo_root)
    except ValueError:
        raise ExecutionError(
            f"file_edit: '{filename}' resolves outside the repo root — refused."
        )

    loop = asyncio.get_running_loop()

    def _sync_write() -> str:
        existed = dest.exists()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        verb = "Updated" if existed else "Wrote"
        return f"{verb} '{filename}' ({len(content_bytes)} bytes)."

    try:
        return await loop.run_in_executor(None, _sync_write)
    except ExecutionError:
        raise
    except Exception as exc:
        raise ExecutionError(f"file_edit: write failed unexpectedly for '{filename}' — {exc}")


# ── Dispatch table ────────────────────────────────────────────────────────
# Adapter closures give every handler a uniform (tool, message, workshop, args)
# call signature despite their differing native signatures. Some handlers are
# `async def` (return a coroutine); `_run_informational` and `_run_local_read`
# are plain `def` (return a str directly) — run() handles both via
# asyncio.iscoroutine.
_HANDLERS = {
    "powershell":     lambda tool, message, workshop, args: _run_powershell(tool, args),
    "python":         lambda tool, message, workshop, args: _run_python(tool, args),
    "skill_import":   lambda tool, message, workshop, args: _run_skill_import(args),
    "skill_promote":  lambda tool, message, workshop, args: _run_skill_promote(args, workshop),
    "informational":  lambda tool, message, workshop, args: _run_informational(tool, message, workshop),
    "local_read":     lambda tool, message, workshop, args: _run_local_read(tool, workshop),
    "filesystem":     lambda tool, message, workshop, args: _run_filesystem(args),
    "local_llm":      lambda tool, message, workshop, args: _run_local_llm(args),
    "note_editor":    lambda tool, message, workshop, args: _run_note_editor(args),
    "llm_api":        lambda tool, message, workshop, args: _run_llm_api(args),
    "browser":        lambda tool, message, workshop, args: _run_browser(args),
    "workflow_engine": lambda tool, message, workshop, args: _run_workflow_engine(tool, args, workshop),
    "cli_launcher":   lambda tool, message, workshop, args: _run_cli_launcher(args),
    "fabric_pattern": lambda tool, message, workshop, args: _run_fabric_pattern(args, workshop),
    # file_edit is intentionally NOT referenced by any tool registry YAML —
    # it is a job-runner-only capability (Step 14b Task 6's jobs.py calls
    # _run_file_edit directly), never chat-reachable, never LLM-selectable.
    # It still gets a _HANDLERS entry (and so WIRED_EXECUTOR_TYPES) so the
    # dispatch table stays the single source of truth for "what executor.run()
    # can execute," matching every other handler's registration shape.
    "file_edit":      lambda tool, message, workshop, args: _run_file_edit(tool, message, workshop, args),
}

# Every executor_type run() actually dispatches to — derived from _HANDLERS so
# the M1 registry-walk test (test_registry.py) cannot drift from what's
# really wired (fix-forward Task 4; previously a hand-maintained frozenset
# that could silently fall out of sync with the if-chain).
WIRED_EXECUTOR_TYPES = frozenset(_HANDLERS.keys())
