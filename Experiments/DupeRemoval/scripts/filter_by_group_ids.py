#!/usr/bin/env python3
"""
Filter LocalHDDuplicates.csv by Group IDs

Takes a list of Group IDs from stdin and creates a new CSV file containing only the matching rows.
"""

import csv
import sys
from pathlib import Path


def parse_group_ids_from_stdin() -> set[str]:
    """
    Parse Group IDs from stdin and return unique set.

    Returns:
        Set of unique Group IDs
    """
    group_ids = set()

    for line in sys.stdin:
        line = line.strip()
        # Skip empty lines and comments
        if line and not line.startswith("#") and line != "Found":
            group_ids.add(line)

    return group_ids


def write_filtered_csv(output_path: Path, input_path: Path, group_ids: set[str]):
    """
    Write filtered CSV containing only rows matching the specified Group IDs.

    Args:
        output_path: Output CSV file path
        input_path: Source CSV file path
        group_ids: Set of Group IDs to filter by
    """
    with open(input_path, "r", newline="", encoding="utf-8") as infile, \
         open(output_path, "w", newline="", encoding="utf-8") as outfile:

        reader = csv.reader(infile, quoting=csv.QUOTE_MINIMAL)
        writer = csv.writer(outfile, quoting=csv.QUOTE_MINIMAL)

        # Write header
        header = next(reader)
        writer.writerow(header)

        # Filter and write matching rows
        for row in reader:
            group_id = row[0]
            if group_id in group_ids:
                writer.writerow(row)


def main():
    """Main execution function."""
    # Configuration
    WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
    INPUT_FILE = WORKSPACE_DIR / "LocalHDDuplicates.csv"
    OUTPUT_FILE = WORKSPACE_DIR / "FilteredDuplicates.csv"

    # Validate input file exists
    if not INPUT_FILE.exists():
        raise FileNotFoundError(f"Input file not found: {INPUT_FILE}")

    # Parse Group IDs from stdin
    group_ids = parse_group_ids_from_stdin()

    if not group_ids:
        print("No Group IDs provided. Exiting.")
        sys.exit(1)

    print(f"Found {len(group_ids)} unique Group IDs")

    # Write filtered CSV
    write_filtered_csv(OUTPUT_FILE, INPUT_FILE, group_ids)

    print(f"Filter complete. Filtered CSV written to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()