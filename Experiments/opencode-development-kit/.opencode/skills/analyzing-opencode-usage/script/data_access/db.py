#!/usr/bin/env python3
"""Read-only SQLite database access utilities."""

import sqlite3
from pathlib import Path
from typing import Any


def get_connection(db_path: str) -> sqlite3.Connection:
    """Create a read-only SQLite connection.

    Args:
        db_path: Path to the SQLite database file.

    Returns:
        sqlite3.Connection configured for read-only access.
    """
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.row_factory = sqlite3.Row

    # Enable WAL mode for better concurrent read performance
    conn.execute("PRAGMA journal_mode=WAL")

    # Enable read-only mode (SQLite 3.45.0+ required)
    try:
        conn.execute("PRAGMA query_only=ON")
    except sqlite3.OperationalError as e:
        if "query_only" in str(e):
            raise RuntimeError(
                "PRAGMA query_only is not supported. Please upgrade SQLite to 3.45.0+ "
                "or use a more recent Python distribution."
            ) from e
        raise

    return conn


def run_query(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> list[dict]:
    """Execute a SQL query and return results as a list of dicts.

    Args:
        conn: SQLite connection (must be read-only).
        sql: SQL query string with ? placeholders.
        params: Parameters to substitute into the query.

    Returns:
        List of dictionaries mapping column names to row values.
    """
    cursor = conn.execute(sql, params)
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]
