"""Code map generator (2026-09-07): the map must reflect the real tree."""
from pathlib import Path

import codemap


def test_scan_module_reads_real_structure():
    info = codemap.scan_module(Path(codemap.__file__).parent / "jobs.py")
    assert info["module"] == "jobs"
    assert "executor" in info["imports"], "jobs imports executor — a real edge"
    assert any(f["name"] == "run_job" for f in info["functions"])
    assert info["loc"] > 100


def test_generate_writes_linked_notes_and_hub(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "alpha.py").write_text('"""Alpha does things."""\nimport beta\n')
    (src / "beta.py").write_text('"""Beta helps."""\ndef help_out():\n    """Assist."""\n')
    (src / "test_alpha.py").write_text("x = 1\n")  # excluded
    out = tmp_path / "map"
    names = codemap.generate(src_dir=src, out_dir=out)
    assert set(names) == {"alpha", "beta", "Code Map"}
    alpha = (out / "alpha.md").read_text()
    assert "[[beta]]" in alpha, "import edges become wikilinks"
    assert "[[Code Map]]" in alpha
    hub = (out / "Code Map.md").read_text()
    assert "[[alpha]]" in hub and "[[beta]]" in hub
    assert not (out / "test_alpha.md").exists()


def test_generate_prunes_stale_notes(tmp_path):
    src = tmp_path / "src"; src.mkdir()
    (src / "keep.py").write_text('"""Keeper."""\n')
    out = tmp_path / "map"; out.mkdir()
    (out / "deleted_module.md").write_text("stale")
    codemap.generate(src_dir=src, out_dir=out)
    assert not (out / "deleted_module.md").exists(), "map must not outlive the code"
    assert (out / "keep.md").exists()


def test_real_generation_targets_the_brain(tmp_path):
    # The default output dir is inside the brain, where index_brain finds it.
    assert codemap._OUT_DIR.parts[-3:] == ("Obsidian Vault", "brain", "codemap")
