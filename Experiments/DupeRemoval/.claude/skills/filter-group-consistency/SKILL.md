# Filter Group Consistency

Filter duplicate file groups to keep only consistent decisions (all KEEP or all ARCHIVE). Use when processing CSV duplicate file groups and need to focus on groups with clear, consistent decisions.

## Overview

This skill filters CSV duplicate file groups to keep only entries where all decisions in a group are identical. This simplifies downstream processing by focusing on groups with clear, consistent decisions.

## Workflow

1. Read from `FilteredDuplicateAnalysis.csv` (or similar input)
2. Group entries by Group ID
3. For each group, check if all decisions are identical
4. Write output to `FocusedDuplicates.csv` (or specified output file)

## Key Learnings

### Simplify Conditional Logic

Use simple length checks instead of complex conditional logic:

```python
# Good: Simple and clear
if len(decisions) == 1:
    kept_entries.extend(entries)
```

### Single Entry Auto-Qualification

Groups with a single entry should be automatically included since there's no inconsistency to check.

### Keep Fieldnames Consistent

Ensure the output fieldnames match the input CSV structure:

```python
fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']
```

## Implementation

See [csv-patterns/SKILL.md](csv-patterns/SKILL.md) for CSV reading/writing patterns and the complete example implementation.

## Complete Example

```python
#!/usr/bin/env python3
"""
Focused Duplicates Script

Filters DuplicateAnalysis.csv for groups where ALL entries are either KEEP or ARCHIVE
(fully consistent groups).

Output: FocusedDuplicates.csv in workspace directory
"""

import csv
from pathlib import Path

def main():
    input_file = Path("workspace/FilteredDuplicateAnalysis.csv")
    output_file = Path("workspace/FocusedDuplicates.csv")

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
            kept_entries.extend(entries)
            continue

        decisions = {entry['Decision'] for entry in entries}
        if len(decisions) == 1:
            kept_entries.extend(entries)

    # Write output
    fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(kept_entries)

    print(f"Processed {len(groups)} groups")
    print(f"Kept {len(kept_entries)} entries from fully consistent groups")

if __name__ == '__main__':
    main()
```

## Reference Implementation

See `filter-group-consistency-reference.py` for a complete working implementation based on the actual `scripts/focused_duplicates.py`.