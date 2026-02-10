# Extract Skills Script Plan

## Context

We need to create a simplified Python script for the skill-extraction skill that avoids using JSON as an intermediate format. The current reference script at `scripts/extract-skill-info.py` uses a JSON schema with 9 fields, which adds complexity. The new approach should request markdown output directly following the template structure.

## Problem Statement

The current implementation requires the AI to output strict JSON with a defined schema, which is then parsed and converted back to markdown. This adds unnecessary complexity to the extraction process.

## Solution Overview

Create `.claude/skills/skill-extraction/scripts/extract-skills.py` that:
- Skips the JSON intermediate format
- Uses template-based prompts for the LLM
- Asks for direct markdown output following the template structure
- Writes markdown output to individual files

## Implementation Plan

### File to Create

1. `.claude/skills/skill-extraction/scripts/extract-skills.py` - Main extraction script

### Key Components

#### extract-skills.py Components:

1. **Imports and Configuration**
   - Import: `argparse`, `sys`, `pathlib`, `re`
   - Import `ollama.chat` from ollama library
   - Configuration: MODEL_NAME = "gpt-oss:20b", API_TIMEOUT = 60, DEBUG = False
   - Performance metrics tracking structure (reuse from reference script)

2. **File Reading**
   - Function `read_markdown_files(folder_path)` - scan for .md files
   - Handle errors gracefully for unreadable files (reuse pattern from reference)

3. **Template Loading**
   - Load `default-preamble.md` as preamble string
   - Load `default-output.md` as output template string
   - Function `combine_preamble_template()` to merge them for prompts

4. **Prompt Building**
   - Function `build_prompt(file_path, file_content)` that:
     - Reads source markdown file
     - Combines preamble and output template
     - Inserts file content into template placeholders
     - Asks model to output valid markdown following template structure

5. **Ollama API Call**
   - Function `call_ollama(prompt)` that:
     - Calls Ollama's gpt-oss:20b model
     - Uses low temperature (0.1) for consistent results
     - Extracts performance metrics from response
     - Returns markdown content (not JSON)

6. **Output Writing**
   - Function `write_output(output_path, skill_name, content)` that:
     - Creates output directory if needed
     - Writes skill_name.md file with formatted content
     - Ensures proper markdown structure

7. **Main Execution**
   - Command-line argument parsing: --source, --destination, --debug
   - Process each markdown file
   - Print success/skip statistics
   - Display performance metrics

### Key Files to Reference

- `.claude/skills/skill-extraction/scripts/default-preamble.md` - Template preamble (already exists)
- `.claude/skills/skill-extraction/scripts/default-output.md` - Template output structure (already exists)
- `.claude/skills/skill-extraction/SKILL.md` - Skill documentation (already exists)
- `scripts/extract-skill-info.py` - Reference implementation (to learn patterns from)

### Reusable Patterns from Reference Script

From `scripts/extract-skill-info.py`, we can reuse:
- Performance metrics tracking structure
- Error handling patterns
- Command-line argument parsing format
- File reading with error handling
- Ollama API call pattern with performance extraction

### Script Workflow

1. User runs: `python3 extract-skills.py --source /path/to/source --destination /path/to/output`
2. Script scans source folder for markdown files
3. For each file:
   - Loads preamble and template
   - Builds prompt with file content
   - Calls Ollama API
   - Writes markdown output to destination

### Testing Plan

1. Test extraction with a simple markdown file
2. Verify output follows template structure
3. Test error handling (missing files, API failures)
4. Verify performance metrics are tracked
5. Test with multiple markdown files

### Success Criteria

1. Script successfully extracts skills from markdown files
2. Output follows template structure exactly
3. All required sections present in output
4. Performance metrics tracked accurately
5. Error handling works correctly
6. Scripts are well-documented and runnable from command line

### Key Differences from Reference Script

| Aspect | Reference Script | New Script |
|--------|------------------|------------|
| Output format | JSON → Markdown | Direct Markdown |
| Prompt strategy | JSON schema extraction | Template-based markdown generation |
| Validation | Built into extraction | Separate validation script |
| Field count | 9 fields | Template-driven |
| Complexity | Higher (JSON parsing) | Lower (direct markdown) |