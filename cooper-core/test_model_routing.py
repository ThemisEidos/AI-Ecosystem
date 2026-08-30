import pytest

import model_routing


FIXTURE = {
    "roles": {
        "brain": {"private": "COOPER-Private", "open": "openai"},
        "reviewer": {"private": "COOPER-Private", "open": "openai"},
    }
}


def test_model_for_resolves_private():
    assert model_routing.model_for("brain", "private", FIXTURE) == "COOPER-Private"


def test_model_for_resolves_open():
    assert model_routing.model_for("brain", "open", FIXTURE) == "openai"


def test_model_for_raises_on_unknown_role():
    with pytest.raises(model_routing.ModelRoutingError, match="brai"):
        model_routing.model_for("brai", "private", FIXTURE)


def test_model_for_raises_on_unknown_workshop():
    with pytest.raises(model_routing.ModelRoutingError, match="mars"):
        model_routing.model_for("brain", "mars", FIXTURE)


def test_load_routing_reads_the_real_repo_file():
    routing = model_routing.load_routing()
    assert set(routing["roles"]) == {
        "classifier", "brain", "planner", "executor", "reviewer", "drafter", "archivist",
    }
    for role, entry in routing["roles"].items():
        assert entry["private"], f"{role} missing a private alias"
        assert entry["open"], f"{role} missing an open alias"


def test_real_file_current_defaults():
    # Locks in today's values so an accidental edit to the JSON is caught here, not
    # discovered live. Update deliberately if a future slice changes a role's alias.
    routing = model_routing.load_routing()
    assert model_routing.model_for("brain", "private", routing) == "COOPER-Private"
    assert model_routing.model_for("brain", "open", routing) == "openai"
    assert model_routing.model_for("reviewer", "private", routing) == "COOPER-Private"
    assert model_routing.model_for("archivist", "open", routing) == "openai"
