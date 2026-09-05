"""Packaging check: every config the runtime reads must be IN the built image.

This exists because the same defect has now shipped three times:

  2026-09-04  Config/pii_research_queries.json missing from the image (14c)
  2026-09-05  Scripts/PDA_RetryPolicy.json missing from the image (15f-ii) --
              every declared budget silently reverted to a built-in fallback:
              no error, no warning, a working system, and a fully green suite
              on the dev machine. 15f-ii would have shipped as a complete no-op.

Both readers fail OPEN by design, which is the right runtime behaviour and
exactly what hides the gap: the file's absence has no symptom. Local tests never
catch it because the file is present on the dev machine; only the built image is
missing it, and the image had no test of its own.

These tests run everywhere, so the in-image suite
(`docker exec <c> sh -c 'cd /app/cooper-core && python -m pytest -q'`) becomes a
real packaging gate rather than a suite that merely happens to also run there.

Adding a config file the runtime reads? Add it to _REQUIRED_RUNTIME_FILES. The
drift guard at the bottom fails if you forget.
"""
import json
import re
from pathlib import Path

import pytest
import yaml

_REPO = Path(__file__).resolve().parent.parent
_SRC_DIR = Path(__file__).resolve().parent

# (relative path, parser) -- parser is the thing that proves the file is not
# merely present but usable. A truncated or empty file packages just as
# "successfully" as a good one.
_REQUIRED_RUNTIME_FILES = [
    ("Scripts/PDA_RetryPolicy.json", "json"),
    ("Scripts/PDA_ModelRouting.json", "json"),
    ("Config/pii_research_queries.json", "json"),
    ("Config/jobs_registry.yaml", "yaml"),
    ("Config/skills_registry.yaml", "yaml"),
    ("Config/general_tool_registry.yaml", "yaml"),
    ("Config/private_tool_registry.yaml", "yaml"),
    ("Config/cooper_workshop_identities.yaml", "yaml"),
    ("Models/cooper-personality/Modelfile", "text"),
]


@pytest.mark.parametrize("rel,_kind", _REQUIRED_RUNTIME_FILES, ids=lambda v: v if isinstance(v, str) else "")
def test_required_runtime_file_is_present(rel, _kind):
    assert (_REPO / rel).is_file(), (
        f"{rel} is missing from this tree. In a container this means the "
        "Dockerfile COPY and/or the .dockerignore allowlist dropped it -- both "
        "layers were wrong the last two times. The reader fails open, so "
        "nothing else will tell you."
    )


@pytest.mark.parametrize("rel,kind", _REQUIRED_RUNTIME_FILES, ids=lambda v: v if isinstance(v, str) else "")
def test_required_runtime_file_is_usable(rel, kind):
    path = _REPO / rel
    if not path.is_file():
        pytest.skip("presence is asserted by the sibling test; not duplicating the failure")
    raw = path.read_text(encoding="utf-8")
    assert raw.strip(), f"{rel} is present but empty"
    if kind == "json":
        json.loads(raw)
    elif kind == "yaml":
        assert yaml.safe_load(raw) is not None, f"{rel} parses to nothing"


def test_fabric_pattern_tree_is_populated():
    # executor._run_fabric_pattern globs PDA-Fabric/*/*.md and fails open to an
    # empty pattern list -- the same silent shape. PDA-Fabric/ was itself
    # gitignored and never committed once before (14a, found by review).
    patterns = sorted((_REPO / "PDA-Fabric").glob("*/*.md"))
    assert patterns, "PDA-Fabric/ has no pattern files -- fabric_pattern is inert"


def test_retry_policy_roles_are_actually_loaded_not_fallbacks():
    # The concrete 15f-ii regression: the container reported the built-in
    # fallback (brain 60s x2) while the policy on disk said 90s x1. Assert
    # against the FILE's values, so this fails if the file is absent whatever
    # the fallbacks happen to be.
    import retry_policy
    policy_file = _REPO / "Scripts/PDA_RetryPolicy.json"
    if not policy_file.is_file():
        pytest.skip("absence is asserted by test_required_runtime_file_is_present")
    declared = json.loads(policy_file.read_text(encoding="utf-8"))
    for role, spec in declared.get("roles", {}).items():
        budget = retry_policy.budget_for(role)
        assert budget.timeout == float(spec["timeout_seconds"]), (
            f"role '{role}': loaded timeout {budget.timeout}s does not match the "
            f"policy file's {spec['timeout_seconds']}s -- the policy is not being read"
        )
        assert budget.max_retries == int(spec["max_retries"]), role


# --- drift guard --------------------------------------------------------------

_PATH_EXPR = re.compile(r'_REPO_ROOT\s*/\s*"([^"]+)"((?:\s*/\s*"[^"]+")*)')


def _declared_paths():
    """Every `_REPO_ROOT / "..."` file path built in non-test runtime source."""
    found = set()
    for py in sorted(_SRC_DIR.glob("*.py")):
        if py.name.startswith("test_") or py.name == "conftest.py":
            continue
        for m in _PATH_EXPR.finditer(py.read_text(encoding="utf-8")):
            parts = [m.group(1)] + re.findall(r'"([^"]+)"', m.group(2) or "")
            rel = "/".join(parts)
            if Path(rel).suffix:            # a file, not a directory
                found.add(rel)
    return found


def test_no_runtime_config_file_escapes_the_packaging_check():
    """Fail if runtime source reads a config file this module does not cover.

    Without this the manifest above rots: the next config file gets added, the
    reader fails open, and we are back to a silent no-op in production with a
    green suite. Extensions that are code or data-at-rest rather than shipped
    config are excluded explicitly, with a reason.
    """
    excluded = {
        # written at runtime, never packaged
        "State/Workflow_Evidence/completion",
    }
    declared = {p for p in _declared_paths() if p not in excluded}
    covered = {rel for rel, _ in _REQUIRED_RUNTIME_FILES}
    uncovered = {
        p for p in declared - covered
        if not p.endswith((".db", ".log", ".md", ".csv"))
    }
    assert not uncovered, (
        "these config files are read by runtime source but are not in "
        f"_REQUIRED_RUNTIME_FILES, so nothing checks they were packaged: {sorted(uncovered)}"
    )
