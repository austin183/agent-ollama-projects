#!/usr/bin/env python3
"""
Extract Skills Script

Uses Ollama's gpt-oss:20b model to extract structured skill information from
text-based documents and create individual skill documentation files.

Scans a user-specified folder for text-based files (filtered by UTF-8 decoding),
extracts skill information using AI with template-based prompts, and outputs
individual markdown files.
"""

import argparse
import sys
from pathlib import Path
from typing import List, Optional
import re

try:
    from ollama import chat
except ImportError:
    print("Error: ollama library not found.")
    print("Please install it with: pip install ollama")
    sys.exit(1)


# Configuration
SCRIPT_DIR = Path(__file__).parent
DEFAULT_MODEL = "gpt-oss:20b"
API_TIMEOUT = 60  # seconds
DEBUG = False

# Performance tracking
PERF_METRICS = {
    "total_calls": 0,
    "total_duration_ns": 0,
    "total_prompt_tokens": 0,
    "total_response_tokens": 0,
    "total_eval_duration_ns": 0,
}


def is_text_file(file_path: Path) -> bool:
    """
    Check if a file is a text-based file by attempting UTF-8 decoding.

    Args:
        file_path: Path to the file to check

    Returns:
        True if file is text-based, False if binary or unreadable
    """
    try:
        with open(file_path, "rb") as f:
            chunk = f.read(8192)  # Read first 8KB for checking
            if not chunk:
                return False  # Empty files are not text files
            # Check for null bytes which indicate binary files
            if b"\x00" in chunk:
                return False
            # Try to decode as UTF-8
            try:
                chunk.decode("utf-8")
                return True
            except UnicodeDecodeError:
                return False
    except Exception:
        return False


def read_text_files(folder_path: Path) -> List[tuple]:
    """
    Read all text-based files from a directory.

    Filters out binary files by attempting UTF-8 decoding and checking for null bytes.
    Skips template files and the script itself.

    Args:
        folder_path: Path to directory to scan

    Returns:
        List of (file_path, content) tuples
    """
    if not folder_path.exists():
        print(f"Error: Source folder '{folder_path}' does not exist.")
        return []

    text_files = []
    for file_path in folder_path.rglob("*"):
        # Skip directories
        if file_path.is_dir():
            continue

        # Skip template and script files
        if file_path.name in ["default-preamble.md", "default-output.md", "extract-skills.py"]:
            continue

        # Check if file is text-based
        if not is_text_file(file_path):
            print(f"  Skipping non-text file: {file_path.name}")
            continue

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
                text_files.append((file_path, content))
        except Exception as e:
            print(f"  Warning: Could not read {file_path}: {e}")
            continue

    return text_files


def load_template(template_path: Path) -> Optional[str]:
    """
    Load a template file content.

    Args:
        template_path: Path to template file

    Returns:
        Template content or None if failed
    """
    try:
        with open(template_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        if DEBUG:
            print(f"  DEBUG: Could not load template {template_path}: {e}", file=sys.stderr)
        return None


def combine_preamble_template(preamble_path: Optional[Path] = None) -> str:
    """
    Combine preamble and output template into a single prompt template.

    Args:
        preamble_path: Optional path to custom preamble file. If not provided, uses default.

    Returns:
        Combined template string
    """
    if preamble_path is None:
        preamble_path = SCRIPT_DIR / "default-preamble.md"

    output_path = SCRIPT_DIR / "default-output.md"

    preamble = load_template(preamble_path)
    output_template = load_template(output_path)

    if preamble is None or output_template is None:
        if DEBUG:
            print(f"  DEBUG: Could not load one or both templates", file=sys.stderr)
        return ""

    return preamble + "\n" + output_template


def build_prompt(file_path: Path, file_content: str, preamble_path: Optional[Path] = None) -> str:
    """
    Build a prompt for the AI model to extract skill information.

    Args:
        file_path: Path to the source file
        file_content: Content of the text-based source file
        preamble_path: Optional path to custom preamble file

    Returns:
        Formatted prompt string
    """
    template = combine_preamble_template(preamble_path)

    if not template:
        return f"""Extract skill information from this markdown file:

File: {file_path}

```
{file_content}
```

Return valid markdown following this structure:
# {file_path.stem}

## Description
description placeholder

## Priority
HIGH or MEDIUM or LOW

## Focus Areas
- focus area 1
- focus area 2
- focus area 3

## Key Topics
- key topic 1
- key topic 2
- key topic 3

## Use Cases
- use case 1
- use case 2
- use case 3

## Content

### Prerequisites
prerequisites placeholder

### Step-by-step Instructions
1. first step
2. second step
3. third step

### Code Examples
```language
code example
```

### Configuration Details
- URL: URL placeholder
- Path: path placeholder
- Command: command placeholder

### Troubleshooting
**Problem**: problem placeholder
**Solution**: solution placeholder

### Tips
- tip 1
- tip 2
"""

    prompt = f"""Extract skill information from this markdown file and output valid markdown following the template structure:

File: {file_path}

```
{file_content}
```

Use the template structure below to format your output:

{template}

Ensure your output is valid markdown with all placeholders filled with relevant, actionable information extracted from the source document."""

    return prompt


def call_ollama(prompt: str) -> Optional[str]:
    """
    Call Ollama's gpt-oss:20b model.

    Args:
        prompt: The prompt to send to the model

    Returns:
        Markdown content or None if failed
    """
    try:
        response = chat(
            model=DEFAULT_MODEL,
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
            print(f"  DEBUG: AI response length: {len(content)} chars", file=sys.stderr)

        return content

    except Exception as e:
        print(f"  Error calling Ollama: {e}")
        if DEBUG:
            import traceback
            print(f"  DEBUG: Traceback: {traceback.format_exc()}", file=sys.stderr)
        return None


def write_output(output_path: Path, skill_name: str, content: str):
    """
    Write extracted skill info to markdown file.

    Args:
        output_path: Output file path
        skill_name: Name of the skill
        content: Markdown content to write
    """
    try:
        # Create output directory if it doesn't exist
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(content)

        print(f"  Wrote {output_path}")
    except Exception as e:
        print(f"  Error writing {output_path}: {e}")


def clean_skill_name(name: str) -> str:
    """
    Clean skill name to ensure it's valid markdown filename.

    Args:
        name: Raw skill name

    Returns:
        Cleaned skill name
    """
    # Remove special characters, replace spaces with hyphens
    cleaned = re.sub(r'[^\w\s-]', '', name)
    cleaned = re.sub(r'[-\s]+', '-', cleaned)
    return cleaned.lower()


def main():
    """Main execution function."""
    print("Extract Skills Script")
    print(f"Model: {DEFAULT_MODEL}")

    # Parse command line arguments
    args = parse_args()

    # Set output directory
    output_dir = args.destination

    print(f"Output: {output_dir}")
    print()

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    source_path = args.source

    if not source_path.exists():
        print(f"Error: Source path '{source_path}' does not exist.")
        sys.exit(1)

    print(f"Scanning source folder: {source_path}")
    print()

    # Read text-based files
    print("Reading text-based files...")
    text_files = read_text_files(source_path)

    if not text_files:
        print("No text-based files found.")
        sys.exit(1)

    print(f"Found {len(text_files)} text-based file(s)")
    print()

    # Process each file
    success_count = 0
    skip_count = 0

    print("Processing files with AI...")
    print("-" * 60)

    for file_path, file_content in text_files:
        print(f"\n{file_path.relative_to(source_path)}")

        # Build prompt
        prompt = build_prompt(file_path, file_content)
        if DEBUG:
            print(f"  DEBUG: AI prompt length: {len(prompt)} chars", file=sys.stderr)

        # Call Ollama
        ai_result = call_ollama(prompt)

        if ai_result is None:
            print(f"  AI failed - skipping")
            skip_count += 1
            continue

        # Extract skill name from content (first line should be # Skill Name)
        lines = ai_result.strip().split('\n')
        if lines and lines[0].startswith('# '):
            skill_name = lines[0][2:].strip()
            skill_name = clean_skill_name(skill_name)
        else:
            skill_name = file_path.stem
            skill_name = clean_skill_name(skill_name)

        # Write output file
        output_filename = f"{skill_name}.md"
        output_path = output_dir / output_filename
        write_output(output_path, skill_name, ai_result)

        success_count += 1

    print()
    print("-" * 60)
    print(f"Processing complete!")
    print(f"  Successful extractions: {success_count}")
    print(f"  Skipped: {skip_count}")
    print(f"  Output directory: {output_dir}")
    print()

    # Print performance metrics if calls were made
    if PERF_METRICS["total_calls"] > 0:
        total_time_sec = PERF_METRICS["total_duration_ns"] / 1e9
        total_eval_time_sec = PERF_METRICS["total_eval_duration_ns"] / 1e9
        avg_tokens_per_sec = (
            PERF_METRICS["total_response_tokens"] / total_eval_time_sec
            if total_eval_time_sec > 0 else 0
        )

        print("Performance Metrics:")
        print(f"  Total API Calls: {PERF_METRICS['total_calls']}")
        print(f"  Total Time: {total_time_sec:.2f}s")
        print(f"  Total Tokens: {PERF_METRICS['total_prompt_tokens'] + PERF_METRICS['total_response_tokens']:,}")
        print(f"  Avg Tokens Per Second: {avg_tokens_per_sec:.2f}")


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Extract Skills Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 extract-skills.py --source /path/to/source
  python3 extract-skills.py --source /path/to/source --destination /path/to/output
  python3 extract-skills.py --source /path/to/source --debug
        """
    )
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="Path to folder containing text-based files to extract"
    )
    parser.add_argument(
        "--destination",
        type=Path,
        help="Path to output directory (overrides default)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output (for troubleshooting)"
    )
    parser.add_argument(
        "--preamble",
        type=Path,
        help="Path to custom preamble file (overrides default-preamble.md)"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    DEBUG = args.debug
    main()