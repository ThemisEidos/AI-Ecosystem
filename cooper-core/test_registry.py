import asyncio
from pathlib import Path

import yaml

import registry

_REPO_ROOT = Path(__file__).resolve().parent.parent


class _DuplicateKeyLoader(yaml.SafeLoader):
    """yaml.safe_load silently lets a later key win over an earlier one in
    the same mapping — exactly how a copy-paste tool insertion once dropped
    restricted_workflow_runner's cloud-forbidden note in favor of a stray
    duplicate `notes:` line belonging to the tool pasted after it. This
    loader raises instead of silently discarding the earlier value."""

    def construct_mapping(self, node, deep=False):
        mapping = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in mapping:
                raise ValueError(f"duplicate key {key!r} in mapping at {node.start_mark}")
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


_DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _DuplicateKeyLoader.construct_mapping,
)


def test_registry_yaml_files_have_no_duplicate_keys():
    for name in ("general_tool_registry.yaml", "private_tool_registry.yaml"):
        path = _REPO_ROOT / "Config" / name
        yaml.load(path.read_text(encoding="utf-8"), Loader=_DuplicateKeyLoader)


def _run(coro):
    return asyncio.run(coro)


def test_keyword_select_finds_status_tool():
    tool = registry.select_tool("private", "run a status summary")
    assert tool is not None
    assert tool["id"] == "status_summary_private"


def test_keyword_select_returns_none_on_no_overlap():
    assert registry.select_tool("private", "zzzz qqqq") is None


def test_is_registry_query():
    assert registry.is_registry_query("what tools do you have") is True
    assert registry.is_registry_query("how are you") is False


def test_llm_select_returns_chosen_tool(monkeypatch):
    async def choose(*args, **kwargs):
        return '{"tool_id": "powershell_private"}'

    monkeypatch.setattr(registry, "_ollama_complete", choose)
    tool = _run(registry.select_tool_llm(
        "private", "run Test-Exec.ps1",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert tool is not None and tool["id"] == "powershell_private"


def test_llm_select_none_means_no_tool(monkeypatch):
    async def none_pick(*args, **kwargs):
        return '{"tool_id": "none"}'

    monkeypatch.setattr(registry, "_ollama_complete", none_pick)
    tool = _run(registry.select_tool_llm(
        "private", "write me a poem",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert tool is None


def test_llm_select_falls_back_to_keywords_on_error(monkeypatch):
    async def boom(*args, **kwargs):
        raise RuntimeError("llm down")

    monkeypatch.setattr(registry, "_ollama_complete", boom)
    tool = _run(registry.select_tool_llm(
        "private", "run a status summary",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert tool is not None and tool["id"] == "status_summary_private"


def test_llm_select_falls_back_on_unregistered_tool_id(monkeypatch):
    async def fake_complete(*args, **kwargs):
        return '{"tool_id": "not_a_real_tool"}'

    monkeypatch.setattr(registry, "_ollama_complete", fake_complete)
    tool = _run(registry.select_tool_llm(
        "private", "run a status summary",
        base_url="", api_key="", model="m", backend="ollama",
    ))
    assert tool is not None
    assert tool["id"] == "status_summary_private"
