#!/usr/bin/env python3
"""
DupeRemoval Archival Script Generator

Reads DuplicateAnalysis.csv (from AI-powered analysis), filters for ARCHIVE decisions,
and generates a bash script to move files to the Archive directory.
"""

import csv
from pathlib import Path

# Configuration
WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "FilteredDuplicateAnalysis.csv"
OUTPUT_SCRIPT = WORKSPACE_DIR / "archive_script.sh"


def read_csv(input_path: Path):
    """Read CSV file handling quoted fields with embedded commas."""
    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        return list(reader)


def normalize_path_for_archive(folder: str):
    """
    Normalize folder path for archival.

    Converts macOS-style paths to the Archive directory structure:
    /Users/projectUser/.../BackupLocation -> /Users/projectUser/Archive/Users/projectUser/.../BackupLocation

    Preserves original folder structure including duplicates (no normalization as per user preference).
    """
    # Get the root workspace directory
    workspace_root = WORKSPACE_DIR

    # Archive destination root - using user's home Archive directory
    archive_root = "/Users/projectUser/Archive"

    # Replace the workspace root prefix with Archive prefix
    if str(folder).startswith(str(workspace_root)):
        archive_path = archive_root + str(folder)[len(str(workspace_root)):]
    else:
        archive_path = archive_root + folder

    return archive_path


def format_path_for_shell(path: str):
    """
    Format path for bash script with proper escaping.

    Wraps path in double quotes and escapes special characters.
    Double quotes allow spaces and apostrophes without complex escaping.
    """
    # Escape backslashes, double quotes, dollar signs, backticks, newlines, and parentheses
    escaped = path.replace("\\", "\\\\").replace('"', '\\"').replace('$', '\\$').replace('`', '\\`').replace('\n', '\\n').replace('(', '\\(').replace(')', '\\)')
    return f'"{escaped}"'


def main():
    """Main execution function."""
    # Parse CSV into list of dicts
    archive_entries = []

    with open(INPUT_FILE, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, quoting=csv.QUOTE_MINIMAL)
        for row in reader:
            if row['Decision'] == 'ARCHIVE':
                archive_entries.append(row)

    print(f"Found {len(archive_entries)} ARCHIVE entries")

    # Build script content
    script_lines = [
        "#!/bin/bash",
        "# DupeRemoval Archival Script",
        "# Generated from DuplicateAnalysis.csv",
        "",
        "# Create Archive directory",
        f"mkdir -p {format_path_for_shell('/Users/projectUser/Archive')}",
        ""
    ]

    # Process each archive entry
    group_info = {}

    for entry in archive_entries:
        group_id = entry['Group ID']
        folder = entry['Folder']
        filename = entry['Filename']
        rationale = entry['Rationale']

        # Get archive path
        archive_path = normalize_path_for_archive(folder)

        # Create directory if not already in script
        # parent_dir is the directory containing the file (includes the folder path)
        # Use parent of the ORIGINAL folder path to preserve all intermediate directories
        parent_dir = str(Path(archive_path))

        # Track directories to create
        if parent_dir not in group_info:
            group_info[parent_dir] = []

        group_info[parent_dir].append((folder, filename, rationale))

    # Write mkdir commands
    for parent_dir in sorted(group_info.keys()):
        mkdir_path = format_path_for_shell(parent_dir)
        # Create the parent directory (this will include all intermediate directories)
        script_lines.append(f"mkdir -p {mkdir_path}")
        script_lines.append("")

    # Write mv commands
    for parent_dir, entries_list in sorted(group_info.items()):
        for folder, filename, rationale in entries_list:
            # Build full source path: folder (directory) + "/" + filename (file)
            source_path = format_path_for_shell(folder + "/" + filename)

            # Extract filename with extension from source path
            source_filename = str(Path(folder + "/" + filename).name)

            # Build destination path: /Users/projectUser/Archive/folder path + filename
            archive_path = "/Users/projectUser/Archive"
            # Keep the folder path but replace workspace root with Archive root
            if str(folder).startswith(str(WORKSPACE_DIR)):
                dest_dir = archive_path + folder[len(str(WORKSPACE_DIR)):].rstrip('/')
                dest_path = format_path_for_shell(dest_dir + "/" + source_filename)
            else:
                dest_path = format_path_for_shell(archive_path + folder.rstrip('/') + "/" + source_filename)

            # Get group name from filename path if available
            try:
                # Use the path from the 'filename' field which contains the full path
                group_name = filename.split('/')[-2]
                comment = f"# Group {group_name}: {folder} -> Archive"
            except IndexError:
                # Fallback to a generic comment if path is invalid
                comment = f"# Archive entry: {folder}"
            script_lines.append(f"{comment}")
            script_lines.append(f"if [ -f {source_path} ]; then")
            script_lines.append(f"    mv {source_path} {dest_path}")
            script_lines.append(f"fi")
            script_lines.append("")

    # Write script to file
    with open(OUTPUT_SCRIPT, "w", encoding="utf-8") as f:
        f.write("\n".join(script_lines))

    print(f"Script generated at: {OUTPUT_SCRIPT}")
    print(f"Total mkdir commands: {len(group_info)}")
    print(f"Total mv commands: {len(archive_entries)}")


if __name__ == "__main__":
    main()