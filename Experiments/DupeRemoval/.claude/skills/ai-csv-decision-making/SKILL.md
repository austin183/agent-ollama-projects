# AI CSV Decision Making

## Description
AI-powered CSV decision making for duplicate file groups. Use when processing CSV duplicate file groups with LLM for intelligent decisions.

## Overview

This skill orchestrates the workflow for making AI-powered decisions about duplicate files:

1. Read from `FocusedDuplicates.csv` (CSV with duplicate file groups)
2. Group entries by Group ID
3. Call LLM for each group to decide which files to keep vs. archive
4. Parse LLM responses
5. Write output to `AIDecisions.csv`

**See also**: [csv-patterns/SKILL.md](csv-patterns/SKILL.md) for CSV reading/writing patterns

## Key Learnings

### CSV Column Order Consistency
Always verify that both input reading and output writing use the same column order.

- Input CSV columns: `Group ID, Folder, Filename, Size (KB), Match %`
- Parser must read: `row[1]` into `folder` and `row[2]` into `filename`
- Output CSV columns: `Group ID, Folder, Filename, Size (KB), Match %, Decision, Rationale`
- Output rows: `[group_id, folder, filename, size_kb, match_pct, decision, rationale]`

See [csv-patterns/SKILL.md](csv-patterns/SKILL.md) for CSV reading/writing patterns and the complete example implementation.

### Input Parsing Alignment
When using `csv.reader`:
```python
for row in reader:
    # Skip header row
    if row[0].startswith("#") or row[0] == "Group ID":
        continue
    group_id = row[0]
    folder = row[1]      # Correct: Folder is at index 1
    filename = row[2]    # Correct: Filename is at index 2
```

### Index Normalization
LLMs typically use 1-based indexing. Normalize to 0-based:

```python
def normalize_index(idx, group_size):
    """Normalize index to 0-based, handling 1-based input from AI."""
    if isinstance(idx, int):
        if idx < 1:
            # Negative or zero, assume 0-based
            return idx
        if idx <= group_size:
            # AI is using 1-based indexing
            return idx - 1
        # Out of bounds, clamp to valid range
        return min(idx, group_size - 1)
    return idx
```

## Prompt Template

The AI prompt should include:
1. List of files in the group with their properties
2. Rules for making decisions (keep certain types, avoid UUIDs, prefer higher match %)
3. Expected JSON output format
4. Rationale requirements

```python
def build_prompt(group_id: str, entries: List[Tuple[str, str, str, str]]) -> str:
    """Build a prompt for the AI model."""
    entries_text = []
    for idx, (folder, filename, size_kb, match_pct) in enumerate(entries):
        entries_text.append(f'{idx}: `{folder}/{filename}` - Size: {size_kb}KB, Match: {match_pct}%')

    entries_str = "\n".join(entries_text)

    prompt = f"""Analyze these duplicate file groups. For each group, choose ONE file to KEEP and the REST to ARCHIVE.

Duplicate Group {group_id}:
{entries_str}

Return ONLY valid JSON with this structure:
{{
  "group_id": "{group_id}",
  "keep": {{index: int, folder: str, filename: str, rationale: str}},
  "archive": {{index: int, folder: str, filename: str, rationale: str}}
}}

Rules:
1. For groups with >2 files, specify ONE to keep, ALL others to archive
2. For groups with 2 files, specify one to keep and one to archive
3. If AI cannot determine a clear preference, return {{"keep": null, "archive": null}} for that group

Guidance:
* Keep all DaVinci Resolve CachedClips
* Try to avoid files with UUIDs where Possible
* Prefer files with higher match percentage
* Consider file size - if there's a significant size difference, the larger file might be the original or more complete version

Rationale should explain WHY this file should be kept."""
    return prompt
```

## Output Writing Order

Output rows must follow this exact column order:
```python
output_rows.append([
    group_id,
    folder,
    filename,
    size_kb,
    match_pct,
    "KEEP",
    ai_result["keep"]["rationale"]
])

output_rows.append([
    group_id,
    folder,
    filename,
    size_kb,
    match_pct,
    "ARCHIVE",
    ai_result["archive"]["rationale"]
])

# For groups with more than 2 files, add ARCHIVE decisions for all others
for idx, (folder, filename, size_kb, match_pct) in enumerate(group_files):
    if idx == keep_idx or idx == archive_idx:
        continue
    output_rows.append([
        group_id,
        folder,
        filename,
        size_kb,
        match_pct,
        "ARCHIVE",
        ai_result["archive"]["rationale"]
    ])
```

## Complete Workflow Example

```python
#!/usr/bin/env python3
"""AI-Powered Duplicate Decision Script"""

import csv
from pathlib import Path

WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "FocusedDuplicates.csv"
OUTPUT_FILE = WORKSPACE_DIR / "AIDecisions.csv"

def read_csv(input_path: Path):
    """Read CSV file handling quoted fields with embedded commas."""
    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        return list(reader)

def group_by_group_id(entries):
    """Group entries by Group ID."""
    group_entries = {}
    for row in entries:
        if row[0].startswith("#") or row[0] == "Group ID":
            continue
        group_id = row[0]
        folder = row[1]
        filename = row[2]
        size_kb = row[3]
        match_pct = row[4]

        if group_id not in group_entries:
            group_entries[group_id] = []

        group_entries[group_id].append((folder, filename, size_kb, match_pct))
    return group_entries

def write_output(output_path, entries):
    """Write output CSV with AI decisions and rationales."""
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(["Group ID", "Folder", "Filename", "Size (KB)", "Match %", "Decision", "Rationale"])

        for row in entries:
            writer.writerow(row)

def main():
    # Read input
    entries = read_csv(INPUT_FILE)

    # Group by Group ID
    group_entries = group_by_group_id(entries)

    # Process each group
    output_rows = []
    for group_id, group_files in sorted(group_entries.items()):
        # Call LLM and process response
        # ...
        pass

    # Write output
    write_output(OUTPUT_FILE, output_rows)

if __name__ == "__main__":
    main()
```

## Validation Patterns

- Validate AI response is a dictionary
- Check for required keys ('group_id', 'keep', 'archive')
- Validate keep/archive are dictionaries
- Normalize indices from 1-based to 0-based
- Handle out-of-bounds indices by defaulting to keeping all files

## Reference Implementation

See `ai-csv-decision-making-reference.py` for a complete working implementation based on the actual `scripts/ai_decision.py`.