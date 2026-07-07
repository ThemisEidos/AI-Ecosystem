"""Open-workshop routing must default through LiteLLM, not directly to OpenAI."""
import subprocess
import sys
import textwrap

import main  # ambient import — WORKSHOP is unset in the test environment, defaults to "open"


def test_open_workshop_defaults_to_litellm_base_url():
    assert main.OPENAI_BASE_URL == "http://litellm:4000/v1"
    assert main.BACKEND_URL == "http://litellm:4000/v1"


def test_open_workshop_defaults_to_openai_alias_model():
    assert main.COOPER_MODEL == "openai"
    assert main.CLASSIFIER_MODEL == "openai"


def _run_main_import_with_env(env_overrides: dict) -> dict:
    """Import main.py in a fresh subprocess with the given env vars set, print the four
    config values as a parseable block, and return them as a dict. Subprocess isolation
    avoids reload()-ing the shared `main` module in-process, which would leak into every
    other test file that imports it later in the same pytest session."""
    script = textwrap.dedent("""
        import main
        print("OPENAI_BASE_URL=" + main.OPENAI_BASE_URL)
        print("COOPER_MODEL=" + main.COOPER_MODEL)
        print("BACKEND_URL=" + main.BACKEND_URL)
    """)
    env = {"COOPER_API_KEY": "test-key", **env_overrides}
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=".", env=env, capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return dict(line.split("=", 1) for line in result.stdout.strip().splitlines())


def test_open_workshop_base_url_still_overridable():
    values = _run_main_import_with_env(
        {"WORKSHOP": "open", "OPENAI_BASE_URL": "http://custom:9000/v1"}
    )
    assert values["OPENAI_BASE_URL"] == "http://custom:9000/v1"


def test_private_workshop_unaffected():
    values = _run_main_import_with_env({"WORKSHOP": "private"})
    assert values["COOPER_MODEL"] == "COOPER-Private"
    assert values["BACKEND_URL"] == "http://localhost:11434"
