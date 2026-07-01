"""
COOPER Workshop enforcer — Step 6.

Enforces the Open/Private boundary at the routing layer, not just at startup.
Three enforcement points:

  1. Tool compatibility  — is this tool registered for the active workshop?
  2. Executor safety     — does this executor_type make cloud calls?
                          If so, block it in Private Workshop.
  3. Backend integrity   — if WORKSHOP=private and backend resolved to openai,
                          hard-fail rather than silently leaking data to the cloud.

This module is stateless and has no side effects. It only raises or returns.
It is called by main.py before any tool runs and before any LLM call is made.

Cloud-calling executor types (blocked in Private Workshop):
  browser, llm_api — these reach external services by definition.
  All others (powershell, python, filesystem, local_llm, workflow_engine,
  cli_launcher, local_read, informational, note_editor) are local-only.
"""

_CLOUD_EXECUTORS = frozenset({"browser", "llm_api"})

_LOCAL_EXECUTORS = frozenset({
    "powershell", "python", "filesystem", "local_llm",
    "workflow_engine", "cli_launcher", "local_read",
    "informational", "note_editor",
})


class WorkshopViolation(Exception):
    """Raised when a request violates the active workshop boundary."""
    pass


def check_tool(tool: dict, active_workshop: str) -> None:
    """
    Raise WorkshopViolation if this tool is not allowed in active_workshop.

    Rules:
      - The tool's `workshop` field must match active_workshop (case-insensitive,
        ignoring ' Workshop' suffix).
      - In Private Workshop, cloud executor types are always blocked.
    """
    tool_workshop = tool.get("workshop", "").lower().replace(" workshop", "").strip()
    active = active_workshop.lower().strip()

    if tool_workshop and tool_workshop != active:
        raise WorkshopViolation(
            f"Tool '{tool.get('name', tool.get('id'))}' is registered for the "
            f"{tool.get('workshop')} but the active workshop is {active_workshop}. "
            f"Switch workshops or choose a different tool."
        )

    if active == "private":
        executor_type = tool.get("executor_type", "")
        if executor_type in _CLOUD_EXECUTORS:
            raise WorkshopViolation(
                f"Tool '{tool.get('name', tool.get('id'))}' uses executor_type "
                f"'{executor_type}', which makes outbound cloud calls. "
                f"This is blocked in Private Workshop. Use a local alternative."
            )


def check_backend(backend: str, active_workshop: str) -> None:
    """
    Raise WorkshopViolation if the resolved backend would send data to the cloud
    while operating in Private Workshop.

    Called at request time (not just startup) so a runtime override can't bypass
    the boundary silently.
    """
    if active_workshop.lower().strip() == "private" and backend == "openai":
        raise WorkshopViolation(
            "Private Workshop is active but the backend resolved to OpenAI. "
            "This would send data to the cloud. Request blocked. "
            "Check the WORKSHOP env var and restart the server."
        )
