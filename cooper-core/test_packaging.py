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
import os
import re
from pathlib import Path

import pytest
import yaml

_REPO = Path(__file__).resolve().parent.parent
_SRC_DIR = Path(__file__).resolve().parent

# (relative path, parser) -- parser is the thing that proves the file is not
# merely present but usable. A truncated or empty file packages just as
# "successfully" as a good one.
# Which container are we in? conftest.py pins WORKSHOP=open for the rest of the
# suite, so the ambient value is stashed there before the pin. "unset" = a dev
# checkout, where the whole repo is on disk.
HOST_WORKSHOP = os.environ.get("COOPER_TEST_HOST_WORKSHOP", "unset")

# Config every workshop's runtime reads. These must be IN the image.
_REQUIRED_RUNTIME_FILES = [
    ("Scripts/PDA_RetryPolicy.json", "json"),
    ("Scripts/PDA_ModelRouting.json", "json"),
    ("Config/skills_registry.yaml", "yaml"),
    ("Config/general_tool_registry.yaml", "yaml"),
    ("Config/private_tool_registry.yaml", "yaml"),
    ("Models/cooper-personality/Modelfile", "text"),
]

# Open-only job config, supplied by bind mounts in docker-compose.yml rather
# than baked into the image. On PRIVATE these must be ABSENT: nothing mounts
# them there, and that omission is what keeps G4 (owner decision 2026-08-23:
# Private gets no web search, no data-broker job) holding at the filesystem
# layer as well as in verify_job's workshop check. A Private container that
# gained these files would be a real boundary regression, so the check asserts
# the absence rather than skipping it.
_OPEN_ONLY_JOB_FILES = [
    ("Config/jobs_registry.yaml", "yaml"),
    ("Config/pii_research_queries.json", "json"),
]

if HOST_WORKSHOP != "private":
    _REQUIRED_RUNTIME_FILES = _REQUIRED_RUNTIME_FILES + _OPEN_ONLY_JOB_FILES


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


def test_brain_directory_is_mounted_and_populated():
    # Supplied by a read-only bind mount on BOTH stacks, not baked into the
    # image. archivist.index_brain now warns when it finds nothing, but a
    # warning in a startup log is easy to miss; this fails the packaging gate
    # instead. An empty brain means recall() answers nothing, forever.
    brain = _REPO / "Obsidian Vault" / "brain"
    assert brain.is_dir(), f"{brain} is not mounted — recall() has no corpus"
    assert sorted(brain.glob("*.md")), f"{brain} has no .md notes — recall() has no corpus"


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
    covered = ({rel for rel, _ in _REQUIRED_RUNTIME_FILES}
               | {rel for rel, _ in _OPEN_ONLY_JOB_FILES})
    uncovered = {
        p for p in declared - covered
        if not p.endswith((".db", ".log", ".md", ".csv"))
    }
    assert not uncovered, (
        "these config files are read by runtime source but are not in "
        f"_REQUIRED_RUNTIME_FILES, so nothing checks they were packaged: {sorted(uncovered)}"
    )


@pytest.mark.skipif(
    HOST_WORKSHOP != "private",
    reason="G4 boundary assertion; only meaningful inside the Private container",
)
@pytest.mark.parametrize("rel,_kind", _OPEN_ONLY_JOB_FILES, ids=lambda v: v if isinstance(v, str) else "")
def test_private_workshop_has_no_job_config(rel, _kind):
    """G4 at the filesystem layer (owner decision 2026-08-23).

    Private gets no web search and no data-broker job. verify_job enforces the
    workshop boundary in code (2026-09-05), but this asserts the second, older
    line of defence: the Private container simply cannot see the job registry,
    so there is nothing for a mount change to accidentally make runnable. If
    this ever fails, someone added a mount and G4 now rests on the code check
    alone -- which is a decision to make deliberately, not to discover later.
    """
    assert not (_REPO / rel).exists(), (
        f"{rel} is present in the PRIVATE container. G4 says Private gets no "
        "job config; this file being here widens what Private can run."
    )
