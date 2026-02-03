# Generate Archive Script

Generate bash scripts to move files to archive directory. Use when creating archival scripts for duplicate file groups.

## Overview

This skill generates a bash script that:
1. Reads from a CSV file (typically `FilteredDuplicateAnalysis.csv`)
2. Filters for ARCHIVE decisions
3. Creates necessary directories
4. Moves files to the Archive directory
5. Writes the script to a file

## Key Learnings

### 1. Path Escaping

Always use the `format_path_for_shell()` function with double quotes to handle paths with spaces, quotes, parentheses, etc.

### 2. Source Path Construction

Source paths must be constructed as `folder + "/" + filename` (NOT `filename + "/" + folder`). The `folder` column contains the directory path and `filename` contains the file name.

### 3. Parentheses in Paths

Parentheses `( )` in file paths require escaping with `\(` and `\)` in bash commands.

### 4. Directory Structure Preservation

The `normalize_path_for_archive()` function maps original paths to the Archive directory by replacing the workspace root with `workspace/Archive`.

## Workflow

1. Read input CSV
2. Filter for ARCHIVE decisions
3. Group entries by parent directory
4. Create mkdir commands for each unique directory
5. Create mv commands for each file to move
6. Write script to output file

See [csv-patterns/SKILL.md](csv-patterns/SKILL.md) for CSV reading patterns and the complete example implementation.

## Complete Example

```python
#!/usr/bin/env python3
"""Generate bash script to move files to archive directory."""

import csv
from pathlib import Path

WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "FilteredDuplicateAnalysis.csv"
OUTPUT_SCRIPT = WORKSPACE_DIR / "archive_script.sh"

def format_path_for_shell(path: str) -> str:
    """Format path for bash script with proper escaping."""
    escaped = path.replace("\\", "\\\\") \
                  .replace('"', '\\"') \
                  .replace('$', '\\$') \
                  .replace('`', '\\`') \
                  .replace('\n', '\\n') \
                  .replace('(', '\\(') \
                  .replace(')', '\\)')
    return escaped

def normalize_path_for_archive(folder: str) -> str:
    """Convert folder path to Archive directory structure."""
    workspace_root = WORKSPACE_DIR
    if str(folder).startswith(str(workspace_root)):
        archive_path = str(workspace_root / "Archive") + str(folder)[len(str(workspace_root)):]
    else:
        archive_path = str(workspace_root / "Archive") + folder
    return archive_path

def main():
    """Main execution function."""
    # Read CSV
    archive_entries = []
    with open(INPUT_FILE, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, quoting=csv.QUOTE_MINIMAL)
        for row in reader:
            if row['Decision'] == 'ARCHIVE':
                archive_entries.append(row)

    print(f"Found {len(archive_entries)} ARCHIVE entries")

    # Build script content
    script_lines = ["#!/bin/bash", "# DupeRemoval Archival Script", ""]

    # Create Archive directory
    script_lines.append(f'mkdir -p {format_path_for_shell(str(WORKSPACE_DIR / "Archive"))}')

    # Group entries by parent directory
    group_info = {}
    for entry in archive_entries:
        folder = entry['Folder']
        filename = entry['Filename']

        parent_dir = str(Path(folder + "/" + filename).parent)

        if parent_dir not in group_info:
            group_info[parent_dir] = []

        group_info[parent_dir].append((folder, filename))

    # Write mkdir commands
    for parent_dir in sorted(group_info.keys()):
        mkdir_path = format_path_for_shell(parent_dir)
        script_lines.append(f"mkdir -p {mkdir_path}")

    # Write mv commands
    for parent_dir, entries_list in sorted(group_info.items()):
        for folder, filename in entries_list:
            # Build source path: folder + "/" + filename
            source_path = format_path_for_shell(folder + "/" + filename)

            # Build destination path: Archive/folder path
            archive_path = normalize_path_for_archive(folder)
            dest_path = format_path_for_shell(archive_path)

            script_lines.append(f"mv {source_path} {dest_path}")

    # Write script to file
    with open(OUTPUT_SCRIPT, "w", encoding="utf-8") as f:
        f.write("\n".join(script_lines))

    print(f"Script generated at: {OUTPUT_SCRIPT}")
    print(f"Total mkdir commands: {len(group_info)}")
    print(f"Total mv commands: {len(archive_entries)}")

if __name__ == "__main__":
    main()
```