# Script Learnings

## Focused Duplicates Script (2026-01-26)

**Script:** `scripts/focused_duplicates.py`

**Learning:**
- Keep conditional logic simple to avoid bugs like nested ternaries causing KeyErrors
- Use `len(decisions) == 1` for checking if all decisions are identical
- Python's `csv.DictReader` + `csv.DictWriter` provides clean, readable CSV handling

## Archival Script Generator (2026-01-27)

**Script:** `scripts/archive_files.py`

**Key Learnings:**

1. **Path escaping for bash scripts:** Use double quotes for paths instead of single quotes. Double quotes allow spaces and apostrophes without complex escaping.

2. **Bash syntax validation:** `bash -n script.sh` validates syntax but has issues with complex `'\''` escaping patterns. Double quotes avoid this problem.

3. **Robust path escaping pattern:**
   ```python
   def format_path_for_shell(path: str):
       # Double quotes allow spaces and apostrophes
       escaped = path.replace("\\", "\\\\").replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
       return escaped
   ```

4. **Parentheses require escaping:** Paths containing `( )` need `\(` and `\)` escaped for bash, otherwise they cause syntax errors.

5. **Source path construction:** When building mv commands, the source path must be `folder + "/" + filename`, NOT `filename + "/" + folder`. The `folder` column contains the directory path and `filename` contains the file name.

6. **Directory structure preservation:** The `normalize_path_for_archive` function correctly maps original paths to the Archive directory by replacing the workspace root with `workspace/Archive`.

## AI Decision Script (2026-01-29)

**Script:** `scripts/ai_decision.py`

**Key Learnings:**

1. **CSV column order consistency:** Always verify that both input reading and output writing use the same column order. A bug can occur when input parsing assigns variables in a different order than expected.

2. **Input parsing alignment:** The `FocusedDuplicates.csv` has columns `Group ID, Folder, Filename, Size (KB), Match %`. The parser must read `row[1]` into `folder` and `row[2]` into `filename`, NOT the reverse.

3. **Output writing:** Output rows must follow the same column order: `[group_id, folder, filename, size_kb, match_pct, decision, rationale]`
