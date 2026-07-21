"""
COOPER Workbench — execution gateway (Step 5).

Executes approved tools. Currently wires one real tool: powershell_private /
powershell_open (the PowerShell runner). Other executor_types return a
"not yet wired" stub so the gateway can grow incrementally.

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
  skill_import  — post-approval tap registration via skills.register_import (step 10)
  skill_promote — post-approval draft activation via skills.register_promotion (step 11)

Not yet wired (return stubs):
  informational, local_read, browser, llm_api, note_editor, python,
  workflow_engine, cli_launcher, filesystem, local_llm
"""
import asyncio
import subprocess
from pathlib import Path
from typing import Optional

import skills

_REPO_ROOT   = Path(__file__).resolve().parent.parent
_SCRIPTS_DIR = _REPO_ROOT / "Scripts"
_TIMEOUT     = 60    # seconds
_MAX_OUTPUT  = 8192  # bytes


class ExecutionError(Exception):
    pass


def _resolve_script(message: str) -> Optional[Path]:
    """
    Find a .ps1 filename mentioned in the message that actually exists in
    Scripts/. Returns the resolved Path or None if nothing matches.

    Uses a simple heuristic: any token ending in .ps1 (case-insensitive).
    The executor will not run a path that wasn't found on disk.
    """
    for token in message.split():
        clean = token.strip("\"'(),")
        if clean.lower().endswith(".ps1"):
            candidate = (_SCRIPTS_DIR / Path(clean).name).resolve()
            # Guard: must resolve inside Scripts/, no path traversal
            try:
                candidate.relative_to(_SCRIPTS_DIR.resolve())
            except ValueError:
                continue
            if candidate.exists():
                return candidate
    return None


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

    if executor_type == "skill_import":
        return await _run_skill_import(message)

    if executor_type == "skill_promote":
        return await _run_skill_promote(message, workshop)

    return _stub(executor_type, tool_name)


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
