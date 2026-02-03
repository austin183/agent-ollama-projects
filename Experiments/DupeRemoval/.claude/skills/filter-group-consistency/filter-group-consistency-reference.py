#!/usr/bin/env python3
"""
Focused Duplicates Script

Filters DuplicateAnalysis.csv for groups where ALL entries are either KEEP or ARCHIVE
(fully consistent groups).

Output: FocusedDuplicates.csv in workspace directory

This is a reference implementation based on scripts/focused_duplicates.py
"""

import csv
from pathlib import Path

def main():
    # Define paths
    input_file = Path("/Users/projectUser/workspace/_scratch/DupeRemoval/workspace/FilteredDuplicateAnalysis.csv")
    output_file = Path("/Users/projectUser/workspace/_scratch/DupeRemoval/workspace/FocusedDuplicates.csv")

    # Read input and group entries by Group ID
    groups = {}

    with open(input_file, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            group_id = row['Group ID']
            if group_id not in groups:
                groups[group_id] = []
            groups[group_id].append(row)

    # Filter groups where ALL entries have the same decision
    kept_entries = []

    for group_id, entries in groups.items():

        if len(entries) == 1:
            # Single entry - automatically qualifies
            kept_entries.extend(entries)
            continue

        # Get all decisions in the group
        decisions = {entry['Decision'] for entry in entries}

        # Keep only if all decisions are the same
        if len(decisions) == 1:
            kept_entries.extend(entries)

    # Write output
    fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(kept_entries)

    # Print summary
    print(f"Processed {len(groups)} groups")
    print(f"Kept {len(kept_entries)} entries from fully consistent groups")
    print(f"Output written to: {output_file}")

if __name__ == '__main__':
    main()