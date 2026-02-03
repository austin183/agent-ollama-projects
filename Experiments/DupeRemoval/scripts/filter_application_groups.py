#!/usr/bin/env python3
"""
Filter Application Groups Script

Filters DuplicateAnalysis.csv to exclude groups containing:
- iMovie Library.imovielibrary in folder path (exactly 2 entries)
- DaVinci Resolve/CacheClip in folder path (any number of entries)

Output: FilteredDuplicateAnalysis.csv in workspace directory
"""

import csv
import sys
from pathlib import Path

# Configuration
WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "DuplicateAnalysis.csv"
OUTPUT_FILE = WORKSPACE_DIR / "FilteredDuplicateAnalysis.csv"
DEBUG = False


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
        Dictionary mapping Group ID to list of (group_id, folder, filename, size_kb, match_pct, decision, rationale) tuples
    """
    group_entries = {}

    for row in entries:
        # Skip header row
        if row[0].startswith("#") or row[0] == "Group ID":
            continue

        group_id = row[0]
        folder = row[1]
        filename = row[2]
        size_kb = row[3]
        match_pct = row[4]
        decision = row[5]
        rationale = row[6]

        if group_id not in group_entries:
            group_entries[group_id] = []

        group_entries[group_id].append((group_id, folder, filename, size_kb, match_pct, decision, rationale))

    return group_entries


def should_exclude_group(folder: str, entry_count: int):
    """
    Determine if a group should be excluded based on application-specific filters.

    Args:
        folder: Folder path string
        entry_count: Number of entries in the group

    Returns:
        True if the group should be excluded, False otherwise
    """
    # Exclude if iMovie Library.imovielibrary in folder path (exactly 2 entries)
    if entry_count == 2 and 'iMovie Library.imovielibrary' in folder:
        if DEBUG:
            print(f"  DEBUG: should_exclude=True for iMovie Library (folder='{folder}')", file=sys.stderr)
        return True

    # Exclude if DaVinci Resolve/CacheClip in folder path (any number of entries)
    if entry_count == 2 and 'DaVinci Resolve/CacheClip' in folder:
        if DEBUG:
            print(f"  DEBUG: should_exclude=True for DaVinci Resolve/CacheClip (folder='{folder}')", file=sys.stderr)
        return True

    if DEBUG:
        print(f"  DEBUG: should_exclude=False (folder='{folder}', entry_count={entry_count})", file=sys.stderr)
    return False


def write_output(output_path: Path, entries):
    """
    Write output CSV with filtered entries.

    Args:
        output_path: Output file path
        entries: List of tuples containing entry data
    """
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(["Group ID", "Folder", "Filename", "Size (KB)", "Match %", "Decision", "Rationale"])

        for entry in entries:
            writer.writerow(entry)


def main():
    """Main execution function."""
    # Create output directory if it doesn't exist
    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)

    # Read input CSV
    entries = read_csv(INPUT_FILE)

    # Group entries by Group ID
    group_entries = group_by_group_id(entries)

    # Filter out groups that should be excluded
    filtered_entries = []

    for group_id, entries in group_entries.items():
        # Determine if this group should be excluded
        should_exclude = False

        for _, folder, _, _, _, decision, _ in entries:
            if should_exclude_group(folder, len(entries)):
                should_exclude = True
                break

        if not should_exclude:
            filtered_entries.extend(entries)

    # Write output
    write_output(OUTPUT_FILE, filtered_entries)

    print(f"Filtered {len(group_entries)} groups down to {len(filtered_entries)} entries")
    print(f"Output written to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()