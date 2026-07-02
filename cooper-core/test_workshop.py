import pytest

import workshop


def test_check_tool_passes_matching_workshop():
    workshop.check_tool(
        {"name": "T", "workshop": "Private Workshop", "executor_type": "powershell"},
        "private",
    )  # must not raise


def test_check_tool_rejects_mismatched_workshop():
    with pytest.raises(workshop.WorkshopViolation):
        workshop.check_tool(
            {"name": "T", "workshop": "Open Workshop", "executor_type": "powershell"},
            "private",
        )


def test_check_tool_fails_closed_for_untagged_tool():
    with pytest.raises(workshop.WorkshopViolation, match="fail-closed"):
        workshop.check_tool({"name": "T", "executor_type": "powershell"}, "private")


def test_check_tool_blocks_cloud_executor_in_private():
    with pytest.raises(workshop.WorkshopViolation):
        workshop.check_tool(
            {"name": "T", "workshop": "Private Workshop", "executor_type": "llm_api"},
            "private",
        )


def test_check_backend_blocks_openai_in_private():
    with pytest.raises(workshop.WorkshopViolation):
        workshop.check_backend("openai", "private")


def test_check_backend_allows_ollama_in_private():
    workshop.check_backend("ollama", "private")  # must not raise
