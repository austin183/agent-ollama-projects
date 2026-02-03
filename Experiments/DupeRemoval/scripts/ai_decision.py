#!/usr/bin/env python3
"""
AI-Powered Duplicate Decision Script

Uses Ollama's gpt-oss:20b model to analyze duplicate file groups and make
intelligent decisions about which files to keep vs. archive.

Reads FocusedDuplicates.csv, groups entries by Group ID, calls Ollama for each group,
and writes AIDecisions.csv with AI-generated decisions and rationales.
"""

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import List, Dict, Optional, Tuple

try:
    from ollama import chat
except ImportError:
    print("Error: ollama library not found.")
    print("Please install it with: pip install ollama")
    sys.exit(1)


# Configuration
WORKSPACE_DIR = Path(__file__).parent.parent / "workspace"
INPUT_FILE = WORKSPACE_DIR / "FocusedDuplicates.csv"
OUTPUT_FILE = WORKSPACE_DIR / "AIDecisions.csv"
MODEL_NAME = "gpt-oss:20b"
API_TIMEOUT = 60  # seconds
DEBUG = False

# Performance tracking
PERF_METRICS = {
    "total_calls": 0,
    "total_duration_ns": 0,  # Total time in nanoseconds
    "total_prompt_tokens": 0,
    "total_response_tokens": 0,
    "total_eval_duration_ns": 0,  # Total evaluation time in nanoseconds
}


def read_csv(input_path: Path) -> List[List[str]]:
    """
    Read CSV file handling quoted fields with embedded commas.

    The Folder column may have quoted fields with embedded commas,
    so we use csv.reader with proper quoting settings.
    """
    with open(input_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f, quoting=csv.QUOTE_MINIMAL)
        return list(reader)


def group_by_group_id(entries: List[List[str]]) -> Dict[str, List[Tuple[str, str, str, str]]]:
    """
    Group entries by Group ID.

    Args:
        entries: List of lists from CSV reader

    Returns:
        Dictionary mapping Group ID to list of (folder, filename, size_kb, match_pct) tuples
    """
    group_entries = {}

    for row in entries:
        # Skip header row
        if row[0].startswith("#") or row[0] == "Group ID":
            continue

        group_id = row[0]
        folder = row[1]      # Correct: Folder is at index 1
        filename = row[2]    # Correct: Filename is at index 2
        size_kb = row[3]
        match_pct = row[4]

        if group_id not in group_entries:
            group_entries[group_id] = []

        group_entries[group_id].append((folder, filename, size_kb, match_pct))

    return group_entries


def escape_json_string(s: str) -> str:
    """
    Escape a string for use in JSON.

    Escapes backslashes and double quotes in the input string.
    """
    return s.replace("\\", "\\\\").replace('"', '\\"')


def build_prompt(group_id: str, entries: List[Tuple[str, str, str, str]]) -> str:
    """
    Build a prompt for the AI model.

    Args:
        group_id: Group identifier
        entries: List of (folder, filename, size_kb, match_pct) tuples in this group

    Returns:
        Formatted prompt string
    """
    # Format entries for the prompt
    entries_text = []
    for idx, (folder, filename, size_kb, match_pct) in enumerate(entries):
        # Escape path components for JSON safety
        escaped_folder = escape_json_string(folder)
        escaped_filename = escape_json_string(filename)
        entries_text.append(f'{idx}: `{escaped_folder}/{escaped_filename}` - Size: {size_kb}KB, Match: {match_pct}%')

    entries_str = "\n".join(entries_text)

    # Build the prompt
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
* Try to avoid files with UUIDs where Possible, like archive something with `2448E946-8B54-46FF-A46D-8F5CEEAA917A` over something without.
* Try to avoid files that are Uncategorized if there is one that looks like it has been categorized
* Avoid files named as numbers if there is one with a real file name
* Prefer files with higher match percentage (e.g., 100% match is better than 95%)
* Consider file size - if there's a significant size difference, the larger file might be the original or more complete version

Rationale should explain WHY this file should be kept (e.g., "Original source folder", "Better quality", "Original timestamp", "Most complete version", "Highest match %")."""

    return prompt


def call_ollama(prompt: str) -> Optional[Dict]:
    """
    Call Ollama's gpt-oss:20b model.

    Args:
        prompt: The prompt to send to the model

    Returns:
        Parsed JSON response or None if failed
    """
    try:
        response = chat(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": prompt}],
            stream=False,
            options={"temperature": 0.1}  # Low temperature for consistent results
        )

        # Extract performance metrics from response
        perf = response.get("eval_count")
        if perf:
            PERF_METRICS["total_calls"] += 1
            PERF_METRICS["total_duration_ns"] += response.get("total_duration", 0)
            PERF_METRICS["total_prompt_tokens"] += response.get("prompt_eval_count", 0)
            PERF_METRICS["total_response_tokens"] += perf
            PERF_METRICS["total_eval_duration_ns"] += response.get("eval_duration", 0)

        # Extract response content
        content = response['message']['content']

        if DEBUG:
            print(f"  DEBUG: AI response: {content[:500]}...", file=sys.stderr)

        # Try to parse JSON
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            # Try to extract JSON from response if model added extra text
            # Look for JSON object pattern
            start_idx = content.find('{')
            if start_idx != -1:
                end_idx = content.rfind('}') + 1
                json_str = content[start_idx:end_idx]
                try:
                    return json.loads(json_str)
                except json.JSONDecodeError:
                    pass

            if DEBUG:
                print(f"  DEBUG: Could not parse JSON from response: {content[:200]}...", file=sys.stderr)
            return None

    except Exception as e:
        print(f"  Error calling Ollama: {e}")
        if DEBUG:
            import traceback
            print(f"  DEBUG: Traceback: {traceback.format_exc()}", file=sys.stderr)
        return None


def write_output(output_path: Path, entries: List[List[str]]):
    """
    Write output CSV with AI decisions and rationales.

    Args:
        output_path: Output file path
        entries: List of [group_id, folder, filename, size_kb, match_pct, decision, rationale]
    """
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(["Group ID", "Folder", "Filename", "Size (KB)", "Match %", "Decision", "Rationale"])

        for row in entries:
            writer.writerow(row)

    print(f"  Wrote {len(entries)} entries to {output_path}")


def main():
    """Main execution function."""
    print(f"AI Duplicate Decision Script")
    print(f"Model: {MODEL_NAME}")
    print(f"Input: {INPUT_FILE}")
    print(f"Output: {OUTPUT_FILE}")
    print()

    # Create output directory if it doesn't exist
    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)

    # Read input CSV
    print("Reading FocusedDuplicates.csv...")
    entries = read_csv(INPUT_FILE)

    if len(entries) < 2:
        print("Error: Input file is empty or has no data rows.")
        sys.exit(1)

    print(f"Read {len(entries) - 1} entries (excluding header)")
    print()

    # Group entries by Group ID
    print("Grouping entries by Group ID...")
    group_entries = group_by_group_id(entries)

    print(f"Found {len(group_entries)} unique groups")
    print()

    # Process each group
    output_rows = []
    success_count = 0
    skip_count = 0

    print("Processing groups with AI...")
    print("-" * 60)

    for group_id, group_files in sorted(group_entries.items()):
        print(f"\nGroup {group_id}: {len(group_files)} file(s)")

        # Build prompt
        prompt = build_prompt(group_id, group_files)

        # Call Ollama
        # ai_result = None
        ai_result = call_ollama(prompt)

        if ai_result is None:
            print(f"  AI failed - keeping all files")
            if DEBUG:
                import sys
                print(f"  DEBUG: AI call failed with error", file=sys.stderr)
            # AI failed, keep all files with KEEP decision
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        if DEBUG:
            import sys
            print(f"  DEBUG: Parsed AI result type: {type(ai_result)}", file=sys.stderr)
            print(f"  DEBUG: Parsed AI result keys: {list(ai_result.keys()) if isinstance(ai_result, dict) else 'not a dict'}", file=sys.stderr)
            if "keep" in ai_result:
                print(f"  DEBUG: ai_result['keep'] type: {type(ai_result['keep'])}, value: {ai_result['keep']}", file=sys.stderr)
            if "archive" in ai_result:
                print(f"  DEBUG: ai_result['archive'] type: {type(ai_result['archive'])}, value: {ai_result['archive']}", file=sys.stderr)

        # Validate AI response structure
        if not isinstance(ai_result, dict):
            print(f"  Invalid response type - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        if "group_id" not in ai_result:
            print(f"  Invalid response - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        if ai_result["keep"] is None or ai_result["archive"] is None:
            print(f"  AI couldn't decide - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        # Validate that keep and archive are dictionaries
        if not isinstance(ai_result["keep"], dict) or not isinstance(ai_result["archive"], dict):
            print(f"  Invalid structure: keep/archive should be dicts - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        # Validate indices - AI may use 1-based indexing (common LLM behavior)
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

        keep_idx = normalize_index(ai_result["keep"]["index"], len(group_files))
        archive_idx = normalize_index(ai_result["archive"]["index"], len(group_files))

        if keep_idx < 0 or keep_idx >= len(group_files):
            print(f"  Invalid keep index {ai_result['keep']['index']} (normalized to {keep_idx}) - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        if archive_idx < 0 or archive_idx >= len(group_files):
            print(f"  Invalid archive index {ai_result['archive']['index']} (normalized to {archive_idx}) - keeping all files")
            for folder, filename, size_kb, match_pct in group_files:
                output_rows.append([group_id, folder, filename, size_kb, match_pct, "KEEP", "AI could not determine - keeping all"])
            skip_count += 1
            continue

        # Add KEEP decision for keep_idx file
        folder, filename, size_kb, match_pct = group_files[keep_idx]
        output_rows.append([
            group_id,
            folder,
            filename,
            size_kb,
            match_pct,
            "KEEP",
            ai_result["keep"]["rationale"]
        ])

        # Add ARCHIVE decision for archive_idx file
        folder, filename, size_kb, match_pct = group_files[archive_idx]
        output_rows.append([
            group_id,
            folder,
            filename,
            size_kb,
            match_pct,
            "ARCHIVE",
            ai_result["archive"]["rationale"]
        ])

        # If group has more than 2 files, add ARCHIVE decisions for all others
        if len(group_files) > 2:
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

        success_count += 1
        print(f"  KEEP: {group_files[keep_idx][1]} ({ai_result['keep']['rationale'][:50]}...)")
        print(f"  ARCHIVE: {group_files[archive_idx][1]} ({ai_result['archive']['rationale'][:50]}...)")

    print()
    print("-" * 60)
    print(f"Processing complete!")
    print(f"  Successful decisions: {success_count}")
    print(f"  Skipped/kept all: {skip_count}")
    print(f"  Total output entries: {len(output_rows)}")
    print()

    # Write output
    print("Writing AIDecisions.csv...")
    write_output(OUTPUT_FILE, output_rows)

    print(f"\nDone! AI decisions saved to: {OUTPUT_FILE}")

    # Print summary
    print("\nSummary:")
    keep_count = sum(1 for row in output_rows if row[5] == "KEEP")
    archive_count = sum(1 for row in output_rows if row[5] == "ARCHIVE")
    print(f"  Files to KEEP: {keep_count}")
    print(f"  Files to ARCHIVE: {archive_count}")

    # Print performance metrics if calls were made
    if PERF_METRICS["total_calls"] > 0:
        total_time_sec = PERF_METRICS["total_duration_ns"] / 1e9
        total_eval_time_sec = PERF_METRICS["total_eval_duration_ns"] / 1e9
        avg_tokens_per_sec = (
            PERF_METRICS["total_response_tokens"] / total_eval_time_sec
            if total_eval_time_sec > 0 else 0
        )

        print("\nPerformance Metrics:")
        print(f"  Total API Calls: {PERF_METRICS['total_calls']}")
        print(f"  Total Time: {total_time_sec:.2f}s")
        print(f"  Total Tokens: {PERF_METRICS['total_prompt_tokens'] + PERF_METRICS['total_response_tokens']:,}")
        print(f"  Avg Tokens Per Second: {avg_tokens_per_sec:.2f}")


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="AI-Powered Duplicate Decision Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python ai_decision.py
  python ai_decision.py --debug
        """
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output (for troubleshooting)"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    DEBUG = args.debug
    main()