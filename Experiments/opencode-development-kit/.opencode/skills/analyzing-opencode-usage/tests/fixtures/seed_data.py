#!/usr/bin/env python3
"""Test database fixture seeder for LLM usage analytics tests."""

import sqlite3
import random
from pathlib import Path
from datetime import datetime, timedelta


def seed_database(db_path: str, num_sessions: int = 100) -> None:
    """Seed a test database with realistic session and message data.

    Args:
        db_path: Path to the SQLite database file.
        num_sessions: Number of sessions to generate.
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create schema
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS session (
            id TEXT PRIMARY KEY,
            directory TEXT,
            time_created INTEGER,
            model TEXT,
            agent TEXT,
            title TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS message (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            time_created INTEGER,
            data TEXT,
            role TEXT,
            FOREIGN KEY (session_id) REFERENCES session(id)
        )
    """)

    # Clear existing data
    cursor.execute("DELETE FROM message")
    cursor.execute("DELETE FROM session")

    models = [
        '{"id": "qwen/qwen3.6-27b", "providerID": "lmstudio"}',
        '{"id": "claude-3-haiku", "providerID": "anthropic"}',
        '{"id": "gpt-4o", "providerID": "openai"}',
        '{"id": "llama-3.1-70b", "providerID": "lmstudio"}',
    ]

    agents = ["developer", "planner", "diff-review", "world-review", "explorer", "build"]

    titles = [
        "Implement feature X",
        "Debug issue in module Y",
        "Refactor legacy code",
        "Write unit tests",
        "Review pull request",
        "Plan architecture changes",
        "Optimize performance",
        "Add documentation",
        "Fix bug in production",
        "Update dependencies",
    ]

    projects = [
        "/path/to/your/project",
        "/Users/austin/workspace/other-project",
        "/Users/austin/workspace/personal-app",
    ]

    # Generate sessions
    session_ids = []
    base_time = int((datetime.now() - timedelta(days=30)).timestamp() * 1000)

    for i in range(num_sessions):
        session_id = f"sess_{i}_{random.randint(1000, 9999)}"
        directory = random.choice(projects)
        time_created = base_time + random.randint(0, 30 * 24 * 3600 * 1000)
        model = random.choice(models)
        agent = random.choice(agents)
        title = random.choice(titles)

        cursor.execute(
            "INSERT INTO session VALUES (?, ?, ?, ?, ?, ?)",
            (session_id, directory, time_created, model, agent, title),
        )
        session_ids.append(session_id)

    # Generate messages for each session
    message_id = 0
    for session_id in session_ids:
        num_messages = random.randint(1, 10)
        session_base_time = base_time + random.randint(0, 30 * 24 * 3600 * 1000)

        for j in range(num_messages):
            msg_id = f"msg_{message_id}"
            message_id += 1
            time_created = session_base_time + random.randint(0, 24 * 3600 * 1000)
            role = random.choice(["user", "assistant"])
            # Generate realistic token counts
            tokens_input = random.randint(100, 5000000)
            tokens_output = random.randint(100, 2000000)
            tokens_reasoning = random.randint(10, 500000)

            data = f'{{"tokens": {{"input": {tokens_input}, "output": {tokens_output}, "reasoning": {tokens_reasoning}}}}}'

            cursor.execute(
                "INSERT INTO message VALUES (?, ?, ?, ?, ?)",
                (msg_id, session_id, time_created, data, role),
            )

    conn.commit()
    conn.close()


if __name__ == "__main__":
    import sys

    db_path = sys.argv[1] if len(sys.argv) > 1 else "test_seed.db"
    num_sessions = int(sys.argv[2]) if len(sys.argv) > 2 else 100

    seed_database(db_path, num_sessions)
    print(f"Seeded database {db_path} with {num_sessions} sessions")
