"""
Embedding helpers for semantic selection (skills, and anything after them).

Transport-agnostic: callers hand `embed_cached` an async `fetch(texts) -> vecs`
built by `make_fetcher` (Ollama `/api/embed` or OpenAI-style `/embeddings` via
LiteLLM). Vectors are cached in the shared cooper_memory.db keyed by
(model, sha256(text)) so catalog texts are embedded once, not per turn.
All failures are the caller's to handle — selection code falls back to
keyword matching, never surfaces an error to the user.
"""
import hashlib
import json
import math
import sqlite3
import threading
from typing import Awaitable, Callable, List, Optional

import httpx

_EMBED_TIMEOUT = 30.0
_CACHE_LOCK = threading.Lock()  # default guard; callers sharing a conn pass their own

_SCHEMA = """
CREATE TABLE IF NOT EXISTS embed_cache (
    model     TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    vec       TEXT NOT NULL,
    PRIMARY KEY (model, text_hash)
)
"""


def cosine(a: List[float], b: List[float]) -> float:
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na == 0.0 or nb == 0.0:
        return 0.0
    return sum(x * y for x, y in zip(a, b)) / (na * nb)


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


async def embed_cached(
    conn: sqlite3.Connection,
    model: str,
    texts: List[str],
    *,
    fetch: Callable[[List[str]], Awaitable[List[List[float]]]],
    lock: Optional[threading.Lock] = None,
) -> List[List[float]]:
    """Return one vector per text, fetching only cache misses (in input order)."""
    lk = lock or _CACHE_LOCK
    with lk:
        conn.execute(_SCHEMA)
        rows = {}
        for t in texts:
            got = conn.execute(
                "SELECT vec FROM embed_cache WHERE model=? AND text_hash=?",
                (model, _hash(t)),
            ).fetchone()
            if got is not None:
                rows[t] = json.loads(got[0])
    missing = [t for t in dict.fromkeys(texts) if t not in rows]
    if missing:
        fetched = await fetch(missing)
        if len(fetched) != len(missing):
            raise ValueError(
                f"embedding backend returned {len(fetched)} vectors for {len(missing)} texts"
            )
        with lk:
            for t, vec in zip(missing, fetched):
                rows[t] = vec
                conn.execute(
                    "INSERT OR REPLACE INTO embed_cache (model, text_hash, vec) VALUES (?,?,?)",
                    (model, _hash(t), json.dumps(vec)),
                )
            conn.commit()
    return [rows[t] for t in texts]


def make_fetcher(
    backend: str, base_url: str, api_key: str, model: str
) -> Callable[[List[str]], Awaitable[List[List[float]]]]:
    """Async embed transport for the workshop's backend. 'openai' covers LiteLLM."""

    async def fetch(texts: List[str]) -> List[List[float]]:
        async with httpx.AsyncClient(timeout=_EMBED_TIMEOUT) as client:
            if backend == "openai":
                resp = await client.post(
                    f"{base_url}/embeddings",
                    headers={"Authorization": f"Bearer {api_key}"},
                    json={"model": model, "input": texts},
                )
                resp.raise_for_status()
                data = sorted(resp.json()["data"], key=lambda d: d["index"])
                return [d["embedding"] for d in data]
            resp = await client.post(
                f"{base_url}/api/embed", json={"model": model, "input": texts}
            )
            resp.raise_for_status()
            return resp.json()["embeddings"]

    return fetch
