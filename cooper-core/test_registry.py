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


def test_is_registry_query():
    assert registry.is_registry_query("what tools do you have") is True
    assert registry.is_registry_query("how are you") is False


_ECHO_TOOL = {
    "id": "echo_tool",
    "name": "Echo Tool",
    "description": "Echoes back the given text.",
    "parameters": {
        "type": "object",
        "properties": {
            "text": {"type": "string", "no_path_separators": True},
            "tags": {"type": "array", "items": {"type": "string"}},
            "context": {"type": "object"},
        },
        "required": ["text"],
        "additionalProperties": False,
    },
}


def test_render_tool_schema_shape():
    schema = registry.render_tool_schema(_ECHO_TOOL)
    assert schema == {
        "type": "function",
        "function": {
            "name": "echo_tool",
            "description": "Echoes back the given text.",
            "parameters": _ECHO_TOOL["parameters"],
        },
    }


def test_render_tool_schema_defaults_to_empty_object_parameters():
    schema = registry.render_tool_schema({"id": "no_args", "description": "d"})
    assert schema["function"]["parameters"] == {
        "type": "object", "properties": {}, "additionalProperties": False,
    }


def test_render_workshop_tools_covers_every_enabled_tool():
    rendered = registry.render_workshop_tools("private")
    ids = {r["function"]["name"] for r in rendered}
    assert ids == {t["id"] for t in registry.list_tools("private")}


def test_validate_args_accepts_valid_call():
    assert registry.validate_args(_ECHO_TOOL, {"text": "hi"}) == []


def test_validate_args_rejects_missing_required():
    violations = registry.validate_args(_ECHO_TOOL, {})
    assert any("missing required argument 'text'" in v for v in violations)


def test_validate_args_rejects_unknown_key():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "hi", "bogus": 1})
    assert any("unknown argument 'bogus'" in v for v in violations)


def test_validate_args_rejects_wrong_type():
    violations = registry.validate_args(_ECHO_TOOL, {"text": 5})
    assert any("must be a string" in v for v in violations)


def test_validate_args_rejects_non_string_array_items():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "hi", "tags": [1, 2]})
    assert any("must be an array of strings" in v for v in violations)


def test_validate_args_rejects_path_separators_when_flagged():
    violations = registry.validate_args(_ECHO_TOOL, {"text": "sub/dir.md"})
    assert any("no directory separators" in v for v in violations)


def test_validate_args_rejects_non_dict_args():
    assert registry.validate_args(_ECHO_TOOL, ["not", "a", "dict"]) != []
