#!/usr/bin/env python3
"""
Extract all unique Group IDs from FocusedDuplicates.csv
"""
import csv
from pathlib import Path

# Configuration
WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "FocusedDuplicates.csv"


def extract_group_ids(input_file: Path) -> list[str]:
    """Read FocusedDuplicates.csv and return unique Group IDs sorted numerically."""
    group_ids = set()

    input_path = input_file
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            group_id = row.get("Group ID", "").strip()
            if group_id:
                group_ids.add(group_id)

    # Sort numerically (handles both numeric and non-numeric IDs)
    sorted_ids = sorted(group_ids, key=lambda x: int(x) if x.isdigit() else x)

    return sorted_ids

if __name__ == "__main__":
    group_ids = extract_group_ids(INPUT_FILE)
    print(f"Found {len(group_ids)} unique group IDs:")
    for gid in group_ids:
        print(gid)