# CSV Processing Patterns

Process CSV files consistently using the DupeRemoval workflow patterns. Use when working with CSV files that contain duplicate file groups, decisions, and rationales.

## Overview

The DupeRemoval workflow uses a consistent CSV schema across multiple scripts:

**Input/Output files**: `workspace/FocusedDuplicates.csv`, `workspace/AIDecisions.csv`, `workspace/FilteredDuplicateAnalysis.csv`

## Column Schema

| Index | Column Name      | Type    | Description                           |
|-------|------------------|---------|---------------------------------------|
| 0     | `Group ID`       | string  | Unique identifier for file groups     |
| 1     | `Folder`         | string  | Directory path containing the file    |
| 2     | `Filename`       | string  | File name                            |
| 3     | `Size (KB)`      | string  | File size in kilobytes               |
| 4     | `Match %`        | string  | Similarity match percentage          |
| 5     | `Decision`       | string  | KEEP or ARCHIVE (optional)           |
| 6     | `Rationale`      | string  | Reason for decision (optional)       |

## Fieldnames List

Always use this explicit list when writing CSV files:

```python
fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']
```

## Reading CSVs

### Using DictReader (preferred)

```python
from csv import DictReader

with open(input_file, 'r', newline='', encoding='utf-8') as f:
    reader = DictReader(f)
    for row in reader:
        group_id = row['Group ID']
        folder = row['Folder']
        filename = row['Filename']
        # Process...
```

### Using csv.reader (for quoted content)

```python
import csv

with open(input_file, "r", newline="", encoding="utf-8") as f:
    reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
    for row in reader:
        # Skip header row
        if row[0].startswith("#") or row[0] == "Group ID":
            continue
        group_id = row[0]
        folder = row[1]      # Column index 1
        filename = row[2]    # Column index 2
```

## Writing CSVs

### Using DictWriter (preferred)

```python
from csv import DictWriter

with open(output_file, 'w', newline='', encoding='utf-8') as f:
    writer = DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row_data in data:
        writer.writerow(row_data)
```

### Using csv.writer

```python
import csv

with open(output_file, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(["Group ID", "Folder", "Filename", "Size (KB)", "Match %", "Decision", "Rationale"])
    for row in data:
        writer.writerow(row)
```

## Complete Example

```python
#!/usr/bin/env python3
"""CSV processing example using DupeRemoval patterns."""

from csv import DictReader, DictWriter
from pathlib import Path

INPUT_FILE = Path("workspace/FocusedDuplicates.csv")
OUTPUT_FILE = Path("workspace/AIDecisions.csv")

fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']

# Read input
with open(INPUT_FILE, 'r', newline='', encoding='utf-8') as f:
    reader = DictReader(f)
    input_data = list(reader)

# Process data
output_data = []
for row in input_data:
    # Apply your logic here
    output_data.append({
        'Group ID': row['Group ID'],
        'Folder': row['Folder'],
        'Filename': row['Filename'],
        'Size (KB)': row['Size (KB)'],
        'Match %': row['Match %'],
        'Decision': row['Decision'],
        'Rationale': row['Rationale']
    })

# Write output
with open(OUTPUT_FILE, 'w', newline='', encoding='utf-8') as f:
    writer = DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(output_data)
```

## See Also

- CSV column order consistency details: See [reference/csv-patterns.md](reference/csv-patterns.md)
- CSV DictReader/DictWriter pattern: See [reference/csv-patterns.md](reference/csv-patterns.md)
- CSV reader pattern: See [reference/csv-patterns.md](reference/csv-patterns.md)