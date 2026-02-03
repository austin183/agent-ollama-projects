# CSV Processing Patterns

This reference contains common CSV handling patterns used throughout the DupeRemoval workflow.

## CSV Schema

**File**: `workspace/FocusedDuplicates.csv` and related CSV files

**Column order** (must be consistent):
- `Group ID`
- `Folder`
- `Filename`
- `Size (KB)`
- `Match %`
- `Decision` (optional)
- `Rationale` (optional)

**Example row**: `["G001", "/path/folder", "file.txt", "123", "95", "KEEP", "Original version"]`

## Fieldnames List

Always use this explicit list when writing CSV files:

```python
fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']
```

## csv.DictReader/DictWriter Pattern

Preferred for cleaner, more maintainable code:

```python
from csv import DictReader, DictWriter

# Define fieldnames explicitly
fieldnames = ['Group ID', 'Folder', 'Filename', 'Size (KB)', 'Match %', 'Decision', 'Rationale']

# Reading
with open(input_file, 'r', newline='', encoding='utf-8') as f:
    reader = DictReader(f)
    for row in reader:
        group_id = row['Group ID']
        folder = row['Folder']

# Writing
with open(output_file, 'w', newline='', encoding='utf-8') as f:
    writer = DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(data)
```

## csv.reader Pattern

Use when you need more control, such as with quoted content containing embedded commas:

```python
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

## Common Pitfalls

1. **Mismatched column indices**: Accessing `row[2]` when it's actually `row[1]` causes silent data errors
2. **Inconsistent header handling**: Forgetting to skip the header row when using `csv.reader`
3. **Fieldnames misalignment**: When using `DictWriter`, the output fieldnames must match the input data structure
4. **List vs dict access**: Mixing `row['fieldname']` with `row[index]` in the same script causes confusion

## Best Practices

- Use explicit fieldnames lists for DictReader/DictWriter
- Comment column indices when using csv.reader
- Test CSV parsing with small sample files first
- Always specify `newline=""` and `encoding='utf-8'` for proper CSV handling