"""Embedding transport-agnostic helpers: cosine + sqlite-cached fetch."""
import asyncio
import sqlite3

import pytest

import embeddings


def test_cosine_basic_geometry():
    assert embeddings.cosine([1, 0], [1, 0]) == pytest.approx(1.0)
    assert embeddings.cosine([1, 0], [0, 1]) == pytest.approx(0.0)
    assert embeddings.cosine([1, 0], [-1, 0]) == pytest.approx(-1.0)
    assert embeddings.cosine([0, 0], [1, 0]) == 0.0  # zero vector: no signal, not NaN


def test_embed_cached_fetches_each_text_once():
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    calls = []

    async def fake_fetch(texts):
        calls.append(list(texts))
        return [[float(len(t)), 1.0] for t in texts]

    v1 = asyncio.run(embeddings.embed_cached(
        conn, "test-model", ["alpha", "beta"], fetch=fake_fetch))
    v2 = asyncio.run(embeddings.embed_cached(
        conn, "test-model", ["alpha", "gamma"], fetch=fake_fetch))

    assert v1[0] == [5.0, 1.0]
    assert v2[0] == v1[0]                      # cache hit, same vector
    assert calls == [["alpha", "beta"], ["gamma"]]  # alpha not refetched


def test_embed_cached_keys_by_model():
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    calls = []

    async def fake_fetch(texts):
        calls.append(list(texts))
        return [[1.0] for _ in texts]

    asyncio.run(embeddings.embed_cached(conn, "model-a", ["alpha"], fetch=fake_fetch))
    asyncio.run(embeddings.embed_cached(conn, "model-b", ["alpha"], fetch=fake_fetch))
    assert calls == [["alpha"], ["alpha"]]  # different model → refetch
