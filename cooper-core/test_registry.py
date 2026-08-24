from pathlib import Path

import yaml

import executor as executor_mod
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
    # no_path_separators is a COOPER-internal validate_args flag, not part of
    # the OpenAI/JSON-Schema wire format — render_tool_schema strips it.
    expected_parameters = {
        "type": "object",
        "properties": {
            "text": {"type": "string"},
            "tags": {"type": "array", "items": {"type": "string"}},
            "context": {"type": "object"},
        },
        "required": ["text"],
        "additionalProperties": False,
    }
    assert schema == {
        "type": "function",
        "function": {
            "name": "echo_tool",
            "description": "Echoes back the given text.",
            "parameters": expected_parameters,
        },
    }
    # the source dict (the same object validate_args reads) must be untouched
    assert _ECHO_TOOL["parameters"]["properties"]["text"]["no_path_separators"] is True


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


def test_no_path_separators_refuses_subdirectory_targets_on_real_registry():
    """Pins the pre-approval path-separator refusal against the LIVE registry
    entries (not the synthetic _ECHO_TOOL fixture) — would fail if
    no_path_separators: true were ever accidentally dropped from the YAML."""
    cases = [
        ("open", "obsidian_note_writer", {"filename": "sub/dir.md", "content": "x"}),
        ("private", "restricted_dmz_writer", {"filename": "sub/dir.txt", "content": "x"}),
        ("open", "powershell_open", {"script": "sub/dir.ps1"}),
        ("open", "import_skill", {"skill_name": "../../etc", "tap_url": "https://example.com"}),
        ("open", "promote_skill", {"skill_name": "../../etc"}),
        ("private", "promote_skill", {"skill_name": "../../etc"}),
    ]
    for workshop, tool_id, args in cases:
        tool = registry.get_tool(workshop, tool_id)
        assert tool is not None, f"{tool_id} missing from {workshop} registry"
        violations = registry.validate_args(tool, args)
        assert violations, f"{tool_id} should refuse a subdirectory target, got no violations"


def _synthetic_args(tool: dict) -> dict:
    """Minimal args dict that satisfies a parameters schema's required keys —
    just enough to drive validate_args() through a real accept path."""
    params = tool["parameters"]
    allowed_workflows = tool.get("allowed_workflows") or {}
    out = {}
    for key in params.get("required", []):
        prop = params["properties"][key]
        t = prop.get("type")
        if t == "string":
            if key == "workflow" and allowed_workflows:
                # workflow_engine tools now validate `workflow` against
                # allowed_workflows pre-approval (fix-forward Important #2) —
                # a plain placeholder string is no longer a valid synthetic
                # value for these tools.
                out[key] = next(iter(allowed_workflows))
            else:
                out[key] = "example"
        elif t == "array":
            item_type = (prop.get("items") or {}).get("type")
            out[key] = ["https://example.com"] if item_type == "string" else []
        elif t == "object":
            out[key] = {}
    return out


def test_validate_args_rejects_empty_required_string():
    tool = {
        "id": "t", "parameters": {
            "type": "object",
            "properties": {"content": {"type": "string"}},
            "required": ["content"],
            "additionalProperties": False,
        },
    }
    violations = registry.validate_args(tool, {"content": "   "})
    assert any("must not be empty" in v for v in violations)


def test_validate_args_allows_empty_optional_string():
    tool = {
        "id": "t", "parameters": {
            "type": "object",
            "properties": {
                "content": {"type": "string"},
                "note": {"type": "string"},
            },
            "required": ["content"],
            "additionalProperties": False,
        },
    }
    assert registry.validate_args(tool, {"content": "hi", "note": ""}) == []


def test_validate_args_rejects_empty_required_array():
    tool = {
        "id": "t", "parameters": {
            "type": "object",
            "properties": {"urls": {"type": "array", "items": {"type": "string"}}},
            "required": ["urls"],
            "additionalProperties": False,
        },
    }
    violations = registry.validate_args(tool, {"urls": []})
    assert any("must not be empty" in v for v in violations)


def test_validate_args_rejects_url_only_violation():
    tool = {
        "id": "t", "parameters": {
            "type": "object",
            "properties": {"urls": {"type": "array", "items": {"type": "string", "url_only": True}}},
            "required": ["urls"],
            "additionalProperties": False,
        },
    }
    violations = registry.validate_args(tool, {"urls": ["ftp://example.com/x"]})
    assert any("http://" in v for v in violations)


def test_validate_args_accepts_valid_urls():
    tool = {
        "id": "t", "parameters": {
            "type": "object",
            "properties": {"urls": {"type": "array", "items": {"type": "string", "url_only": True}}},
            "required": ["urls"],
            "additionalProperties": False,
        },
    }
    assert registry.validate_args(tool, {"urls": ["https://example.com/x"]}) == []


def test_validate_args_rejects_unknown_workflow_value():
    tool = {
        "id": "t", "executor_type": "workflow_engine",
        "allowed_workflows": {"pda_command_router": "pda-command-router"},
        "parameters": {
            "type": "object",
            "properties": {"workflow": {"type": "string"}, "payload": {"type": "string"}},
            "required": ["workflow"],
            "additionalProperties": False,
        },
    }
    violations = registry.validate_args(tool, {"workflow": "not_a_real_workflow"})
    assert any("allowed_workflows" in v for v in violations)


def test_validate_args_accepts_known_workflow_value():
    tool = {
        "id": "t", "executor_type": "workflow_engine",
        "allowed_workflows": {"pda_command_router": "pda-command-router"},
        "parameters": {
            "type": "object",
            "properties": {"workflow": {"type": "string"}, "payload": {"type": "string"}},
            "required": ["workflow"],
            "additionalProperties": False,
        },
    }
    assert registry.validate_args(tool, {"workflow": "pda_command_router"}) == []


def test_validate_args_skips_workflow_check_when_allowlist_empty():
    # restricted_workflow_runner-shaped: no allowed_workflows configured yet —
    # this stays the executor's fail-closed job (spec §4: "stays exactly as-is"),
    # not validate_args's.
    tool = {
        "id": "t", "executor_type": "workflow_engine",
        "parameters": {
            "type": "object",
            "properties": {"workflow": {"type": "string"}},
            "required": ["workflow"],
            "additionalProperties": False,
        },
    }
    assert registry.validate_args(tool, {"workflow": "anything"}) == []


def test_validate_args_rejects_unknown_workflow_on_real_registry():
    tool = registry.get_tool("open", "n8n_general_workflows")
    assert tool is not None
    violations = registry.validate_args(tool, {"workflow": "not_a_real_workflow", "payload": "hi"})
    assert violations, "an unknown workflow key must be refused pre-approval"


def test_validate_args_rejects_non_http_url_on_real_browser_research_registry():
    tool = registry.get_tool("open", "browser_research")
    assert tool is not None
    violations = registry.validate_args(tool, {"urls": ["ftp://example.com/x"]})
    assert violations, "a non-http(s) URL must be refused pre-approval"


def test_every_enabled_tool_has_a_valid_wired_parameters_block():
    """Registry-walk test — this IS metric M1, permanently (spec §6.1). For
    every enabled tool in both registries: a parameters block exists and is
    well-formed, render_tool_schema emits a valid OpenAI shape, a synthetic
    schema-conforming call passes validate_args, and the tool's
    executor_type maps to a real executor.py handler (no live LLM)."""
    for workshop_name in ("open", "private"):
        for tool in registry.list_tools(workshop_name):
            params = tool.get("parameters")
            assert params is not None, f"{tool['id']} is missing a parameters block"
            assert params.get("type") == "object", tool["id"]
            assert "properties" in params, tool["id"]

            schema = registry.render_tool_schema(tool)
            assert schema["type"] == "function"
            assert schema["function"]["name"] == tool["id"]
            # rendered parameters match the source block except for the
            # COOPER-internal no_path_separators flag, which is stripped
            # before the schema goes out over the wire (finding: Important #3)
            for prop_name, prop in params.get("properties", {}).items():
                rendered_prop = schema["function"]["parameters"]["properties"][prop_name]
                assert "no_path_separators" not in rendered_prop
                expected_prop = {k: v for k, v in prop.items() if k != "no_path_separators"}
                assert rendered_prop == expected_prop, tool["id"]

            synthetic = _synthetic_args(tool)
            violations = registry.validate_args(tool, synthetic)
            assert violations == [], f"{tool['id']}: {violations}"

            executor_type = tool.get("executor_type")
            assert executor_type in executor_mod.WIRED_EXECUTOR_TYPES, (
                f"{tool['id']}'s executor_type {executor_type!r} is not wired"
            )
