# Bash Path Escaping

## Description
Path escaping for bash scripts. Use when generating bash scripts involving file paths with spaces, quotes, parentheses, or other special characters.

## Core Strategy

Use **double quotes** around paths instead of single quotes. Double quotes allow spaces and apostrophes without complex escaping.

### Single Quote vs Double Quote

```bash
# Single quotes: Everything is literal (except escaped single quotes)
source_path='/path with spaces/file.txt'
# Error if path contains spaces!

# Double quotes: Interpreted except for $, `, \, and escaped characters
source_path="/path with spaces/file.txt"
# Works correctly!
```

## Escaping Pattern

```python
def format_path_for_shell(path: str) -> str:
    """
    Format path for bash script with proper escaping.

    Uses double quotes around paths and escapes only necessary characters.
    Double quotes allow spaces and apostrophes without complex escaping.
    """
    # Escape backslashes, double quotes, dollar signs, backticks, newlines, and parentheses
    escaped = path.replace("\\", "\\\\") \
                  .replace('"', '\\"') \
                  .replace('$', '\\$') \
                  .replace('`', '\\`') \
                  .replace('\n', '\\n') \
                  .replace('(', '\\(') \
                  .replace(')', '\\)')
    return escaped
```

### Character Reference Table

| Character | Double Quote Escape | Single Quote Behavior |
|-----------|---------------------|----------------------|
| Space     | No escape needed    | Invalid in single quotes |
| Apostrophe (') | No escape needed | Invalid in single quotes |
| Backslash (\)  | `\\`              | Escaped as `\\` |
| Double quote (") | `\"`          | Invalid in single quotes |
| Dollar sign ($) | `\$`            | Literal in single quotes |
| Backtick (`)   | `\``            | Literal in single quotes |
| Parenthesis (( )) | `\(`, `\)` | Literal in single quotes |

## When to Use Single Quotes

Use single quotes when the path contains **no special characters**:
```bash
source_path='/simple/path/file.txt'
```

This is more efficient but requires clean paths.

## Source Path Construction

When building mv commands, the source path must be constructed as:

```python
# Correct: folder (directory) + "/" + filename (file)
source_path = folder + "/" + filename

# NOT: filename + "/" + folder (this would try to move a directory)
```

## Directory Structure Preservation

The path normalization function should map original paths to the archive directory:

```python
def normalize_path_for_archive(folder: str) -> str:
    """
    Converts workspace paths to Archive directory structure.
    /Users/projectUser/.../BackupLocation -> /Users/projectUser/workspace/_scratch/DupeRemoval/workspace/Archive/Users/projectUser/.../BackupLocation
    """
    workspace_root = Path(__file__).parent.parent / "workspace"
    if str(folder).startswith(str(workspace_root)):
        archive_path = str(workspace_root / "Archive") + str(folder)[len(str(workspace_root)):]
    else:
        archive_path = str(workspace_root / "Archive") + folder
    return archive_path
```

## Bash Syntax Validation

Use `bash -n` to validate syntax without running:

```bash
bash -n archive_script.sh
```

Note: `bash -n` has issues with complex `'\''` escaping patterns. Double quotes avoid this problem.

## Complete Example

See [csv-patterns/SKILL.md](csv-patterns/SKILL.md) for the CSV reading/writing patterns used in this example.

```python
#!/usr/bin/env python3
"""Generate bash script to move files to archive directory."""

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

def main():
    # Read CSV entries
    archive_entries = []
    with open(INPUT_FILE, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['Decision'] == 'ARCHIVE':
                archive_entries.append(row)

    # Build script
    script_lines = ["#!/bin/bash", "# DupeRemoval Archival Script", ""]

    # Create Archive directory
    script_lines.append(f'mkdir -p {format_path_for_shell(str(WORKSPACE_DIR / "Archive"))}')

    # Process each entry
    for entry in archive_entries:
        folder = entry['Folder']
        filename = entry['Filename']

        # Build source path: folder + "/" + filename
        source_path = format_path_for_shell(folder + "/" + filename)

        # Build destination path
        if str(folder).startswith(str(WORKSPACE_DIR)):
            dest_path = format_path_for_shell(
                str(WORKSPACE_DIR / "Archive") + folder[len(str(WORKSPACE_DIR)):]
            )
        else:
            dest_path = format_path_for_shell(str(WORKSPACE_DIR / "Archive") + folder)

        script_lines.append(f"mv {source_path} {dest_path}")

    # Write script file
    with open(OUTPUT_SCRIPT, "w", encoding="utf-8") as f:
        f.write("\n".join(script_lines))

if __name__ == "__main__":
    main()
```

## Verification Methods

1. **Syntax check**: `bash -n script.sh`
2. **Execution with trace**: `bash -x script.sh`
3. **Dry-run with -n flag**: `bash -n script.sh && echo "Valid"`