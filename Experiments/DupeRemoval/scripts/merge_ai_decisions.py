#!/usr/bin/env python3
"""
Merge AI Decisions into DuplicateAnalysis.csv

Removes existing Group ID entries from DuplicateAnalysis.csv and appends
AI-generated decisions from AIDecisions.csv.
"""

import csv
from pathlib import Path
from typing import Set

WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
AIDECISIONS_FILE = WORKSPACE_DIR / "AIDecisions.csv"
FILTERED_DUPLICATEANALYSIS_FILE = WORKSPACE_DIR / "FilteredDuplicateAnalysis.csv"


def main():
    # Read AIDecisions.csv to get Group IDs to keep
    ai_group_ids = read_group_ids_from_csv(AIDECISIONS_FILE)

    print(f"Found {len(ai_group_ids)} unique Group IDs in AIDecisions.csv")

    # Read and filter DuplicateAnalysis.csv
    print(f"Reading {FILTERED_DUPLICATEANALYSIS_FILE}...")
    filtered_rows = filter_duplicate_analysis(FILTERED_DUPLICATEANALYSIS_FILE, ai_group_ids)

    # Count original rows (excluding header)
    with open(FILTERED_DUPLICATEANALYSIS_FILE, "r", newline="", encoding="utf-8") as f:
        original_count = sum(1 for _ in f) - 1

    print(f"Removed {original_count - (len(filtered_rows) - 1)} entries from DuplicateAnalysis.csv")

    # Append AIDecisions.csv rows
    print(f"Reading {AIDECISIONS_FILE}...")
    ai_rows = read_csv_rows(AIDECISIONS_FILE)

    print(f"Appending {len(ai_rows) - 1} entries from AIDecisions.csv")

    # Write merged output
    print(f"Writing merged result to {FILTERED_DUPLICATEANALYSIS_FILE}...")
    write_csv_rows(FILTERED_DUPLICATEANALYSIS_FILE, filtered_rows + ai_rows)

    print(f"\nMerge complete! Final count: {len(filtered_rows + ai_rows) - 1} entries")


def read_group_ids_from_csv(csv_path: Path) -> Set[str]:
    """Extract all Group IDs from CSV file."""
    group_ids = set()
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        header = next(reader)  # Skip header
        for row in reader:
            if len(row) > 0:
                group_ids.add(row[0])
    return group_ids


def read_csv_rows(csv_path: Path) -> list[list[str]]:
    """Read all CSV rows, excluding header."""
    rows = []
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        header = next(reader)  # Skip header
        for row in reader:
            rows.append(row)
    return rows


def filter_duplicate_analysis(csv_path: Path, group_ids_to_keep: Set[str]) -> list[list[str]]:
    """Filter DuplicateAnalysis.csv to remove rows with Group IDs in group_ids_to_keep."""
    rows = []
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        header = next(reader)  # Copy header
        rows.append(header)
        for row in reader:
            if len(row) > 0:
                group_id = row[0]
                if group_id not in group_ids_to_keep:
                    rows.append(row)
    return rows


def write_csv_rows(csv_path: Path, rows: list[list[str]]):
    """Write CSV file with proper quoting."""
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        for row in rows:
            writer.writerow(row)


if __name__ == "__main__":
    main()