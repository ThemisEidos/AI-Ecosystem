import sqlite3

import pytest

import archivist


@pytest.fixture
def conn():
    c = archivist.get_conn(db_path=":memory:")
    archivist.init_db(c)
    yield c
    c.close()


def test_init_db_creates_all_tables(conn):
    tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'table')")
    }
    assert "decisions" in tables
    assert "skills" in tables

    fts_tables = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE sql LIKE '%fts5%'"
        )
    }
    assert "decisions_fts" in fts_tables
    assert "brain_fts" in fts_tables


def test_init_db_is_idempotent(conn):
    archivist.init_db(conn)  # calling twice must not raise
    archivist.init_db(conn)
