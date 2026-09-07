"""Code map generator — COOPER's structural self-knowledge (2026-09-07).

The Graphify meta, built in-repo instead of installed: parse cooper-core with
the stdlib AST and write one Obsidian note per module into
`Obsidian Vault/brain/codemap/`, wikilinked along real import edges. Obsidian's
graph view renders the architecture; `archivist.index_brain()` indexes the notes
into `brain_fts`, so `recall()` can answer "where does X live?" from a map
instead of COOPER (or Claude) re-grepping the source every session.

Deterministic and idempotent: notes are derived purely from the source tree, so
re-running after a refactor refreshes the map; stale notes for deleted modules
are removed. No third-party parser — the repo convention is stdlib-first, and
Python's own `ast` is the one honest parser for Python.

Run: `.venv/bin/python codemap.py` (from cooper-core/), or import and call
`generate()`.
"""
import ast
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent
_SRC_DIR = Path(__file__).resolve().parent
_OUT_DIR = _REPO_ROOT / "Obsidian Vault" / "brain" / "codemap"


def _first_line(doc: Optional[str]) -> str:
    return (doc or "").strip().splitlines()[0].strip() if (doc or "").strip() else ""


def scan_module(path: Path) -> dict:
    """One module's structure: docstring, local imports, classes, functions."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    # Local = siblings of the module being scanned, not of this file — the
    # difference is invisible on the real tree and total on any other tree
    # (the test caught exactly that).
    local_names = {p.stem for p in path.parent.glob("*.py")}
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(a.name for a in node.names if a.name in local_names)
        elif isinstance(node, ast.ImportFrom) and node.module in local_names:
            imports.add(node.module)
    classes = [
        {"name": n.name, "doc": _first_line(ast.get_docstring(n)),
         "methods": sum(isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))
                        for m in n.body)}
        for n in tree.body if isinstance(n, ast.ClassDef)
    ]
    functions = [
        {"name": n.name, "doc": _first_line(ast.get_docstring(n)),
         "async": isinstance(n, ast.AsyncFunctionDef)}
        for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
    ]
    return {
        "module": path.stem,
        "doc": _first_line(ast.get_docstring(tree)),
        "imports": sorted(imports - {path.stem}),
        "classes": classes,
        "functions": functions,
        "loc": len(path.read_text(encoding="utf-8").splitlines()),
    }


def render_note(info: dict) -> str:
    """One module as an Obsidian note. Wikilinks = real import edges."""
    lines = [
        "---",
        f"title: {info['module']}.py",
        "tags:",
        "  - codemap",
        f"loc: {info['loc']}",
        "---",
        "",
        f"# {info['module']}.py",
        "",
        f"{info['doc'] or '(no module docstring)'}",
        "",
        f"Part of [[Code Map]] · `cooper-core/{info['module']}.py` · {info['loc']} lines",
        "",
    ]
    if info["imports"]:
        lines += ["## Depends on", ""]
        lines += [f"- [[{m}]]" for m in info["imports"]]
        lines += [""]
    if info["classes"]:
        lines += ["## Classes", ""]
        lines += [f"- **{c['name']}** ({c['methods']} methods) — {c['doc'] or '—'}"
                  for c in info["classes"]]
        lines += [""]
    if info["functions"]:
        lines += ["## Functions", ""]
        lines += [f"- `{'async ' if f['async'] else ''}{f['name']}()` — {f['doc'] or '—'}"
                  for f in info["functions"]]
        lines += [""]
    return "\n".join(lines)


def generate(src_dir: Optional[Path] = None, out_dir: Optional[Path] = None) -> list:
    """(Re)generate the map. Returns the module names written. Test files and
    private venv/dunder paths are excluded — the map is the runtime's shape,
    not the suite's."""
    src = src_dir or _SRC_DIR
    out = out_dir or _OUT_DIR
    out.mkdir(parents=True, exist_ok=True)
    infos = []
    for path in sorted(src.glob("*.py")):
        if path.stem.startswith(("test_", "conftest", "__")):
            continue
        infos.append(scan_module(path))
    written = set()
    for info in infos:
        (out / f"{info['module']}.md").write_text(render_note(info), encoding="utf-8")
        written.add(info["module"])
    # index note: the graph's hub for the code side
    imported_by: dict = {}
    for info in infos:
        for dep in info["imports"]:
            imported_by.setdefault(dep, []).append(info["module"])
    hub = [
        "---", "title: Code Map", "tags:", "  - codemap", "---", "",
        "# Code Map", "",
        "COOPER's runtime, one note per module, wikilinked along real import",
        "edges. Regenerate after a refactor: `cd cooper-core && .venv/bin/python codemap.py`.",
        "Part of [[COOPER Brain]].", "",
        "## Modules", "",
    ]
    for info in sorted(infos, key=lambda i: -i["loc"]):
        fanin = len(imported_by.get(info["module"], []))
        hub.append(f"- [[{info['module']}]] — {info['doc'] or '—'} "
                   f"({info['loc']} loc, imported by {fanin})")
    hub.append("")
    (out / "Code Map.md").write_text("\n".join(hub), encoding="utf-8")
    written.add("Code Map")
    # prune notes for modules that no longer exist
    for stale in out.glob("*.md"):
        if stale.stem not in written:
            stale.unlink()
    return sorted(written)


if __name__ == "__main__":
    names = generate()
    print(f"codemap: {len(names)} notes -> {_OUT_DIR}")
