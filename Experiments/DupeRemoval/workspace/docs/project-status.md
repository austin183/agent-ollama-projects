# Project Status

## Project Goal

Move duplicates to a separate archive folder with an approved bash script containing `mkdir` and `mv` commands.

## Current Status (2026-01-26)

**Completed:**
- `scripts/analyze_duplicates.py` - Categorizes files (KEEP/ARCHIVE/MANUAL)
- `scripts/filter_application_groups.py` - Filters DuplicateAnalysis.csv to exclude iMovie Library and DaVinci Resolve/CacheClip groups, outputs to FilteredDuplicateAnalysis.csv
- `scripts/focused_duplicates.py` - Filters for fully consistent groups out of FilteredDuplicateAnalysis.csv into FocusedDuplicates.csv
- `scripts/extract_group_ids.py` - Returns GroupIds from FocusedDuplicates.csv for testing
- `scripts/filter_by_group_ids.py` - Filters the LocalHDDuplicats.csv file by group Ids into FilteredDuplicates.csv for testing
- `scripts/ai_decision.py` - A tiebreaker to use on the FocusedDuplicates.csv file
- `scripts/merge_ai_decisions.py` - Merges changes from AIDecisions.csv into FilteredDuplicateAnalysis.csv
- `scripts/archive_files.py` - Reads from FilteredDuplicateAnalysis.csv and generates archive_script.sh

**Next Steps:**
- Test `scripts/archive_files.py` to verify it reads from FilteredDuplicateAnalysis.csv
- Run `archive_script.sh` with `bash -n` to validate syntax
- Review and approve the generated `archive_script.sh`