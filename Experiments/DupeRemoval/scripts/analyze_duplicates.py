#!/usr/bin/env python3
"""
Duplicate Folder Categorization Script

Analyzes LocalHDDuplicates.csv and produces a report of which folders
should be kept vs. archived for each duplicate group.
"""

import csv
from pathlib import Path
import re

# Configuration
WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "LocalHDDuplicates.csv"
OUTPUT_FILE = WORKSPACE_DIR / "DuplicateAnalysis.csv"

# Regex patterns
MAIN_PATTERN = re.compile(r"Pictures|Photos|Documents|Music|Videos|Movies|Home|Desktop|Downloads|DaVinci")
BACKUP_PATTERN = re.compile(r"PhoneCopy|ExternalBackup|Archive|Temp|Backups|Bacup|photoslibrary")

# Rationale mapping
RATIONALE = {
    "KEEP": "Main source folder",
    "ARCHIVE": "Backup/secondary location",
    "MANUAL": "Unknown - requires manual review"
}


def read_csv(input_path: Path):
    """
    Read CSV file handling quoted fields with embedded commas.

    The Folder column may have quoted fields with embedded commas,
    so we use csv.reader with proper quoting settings.
    """
    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        return list(reader)


def group_by_group_id(entries):
    """
    Group entries by Group ID.

    Args:
        entries: List of lists from CSV reader

    Returns:
        Dictionary mapping Group ID to list of (folder, filename, size_kb, match_pct) tuples
    """
    group_entries = {}

    for row in entries:
        # Skip header row
        if row[0].startswith("#") or row[0] == "Group ID":
            continue

        group_id = row[0]
        filename = row[1]
        folder = row[2]
        size_kb = row[3]
        match_pct = row[4]

        if group_id not in group_entries:
            group_entries[group_id] = []

        group_entries[group_id].append((folder, filename, size_kb, match_pct))

    return group_entries


def determine_decision(folder: str):
    """
    Determine decision for a folder based on pattern matching.

    Args:
        folder: Folder path string

    Returns:
        "KEEP", "ARCHIVE", or "MANUAL"
    """
    if BACKUP_PATTERN.search(folder):
        return "ARCHIVE"
    elif MAIN_PATTERN.search(folder):
        return "KEEP"
    else:
        return "MANUAL"


def write_output(output_path: Path, group_entries, headers):
    """
    Write output CSV with decision and rationale.

    Args:
        output_path: Output file path
        group_entries: Dictionary of grouped entries
        headers: List of header strings
    """
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(headers)

        for group_id, entries in group_entries.items():
            for folder, filename, size_kb, match_pct in entries:
                decision = determine_decision(folder)
                rationale = RATIONALE[decision]

                writer.writerow([group_id, folder, filename, size_kb, match_pct, decision, rationale])


def main():
    """Main execution function."""
    # Create output directory if it doesn't exist
    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)

    # Read input CSV
    entries = read_csv(INPUT_FILE)

    # Group entries by Group ID
    group_entries = group_by_group_id(entries)

    # Write output
    write_output(OUTPUT_FILE, group_entries, ["Group ID", "Folder", "Filename", "Size (KB)", "Match %", "Decision", "Rationale"])

    print(f"Analysis complete. Report generated at: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()