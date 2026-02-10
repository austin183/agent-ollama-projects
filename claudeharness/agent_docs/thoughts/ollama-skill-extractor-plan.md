# Script: Markdown File to Skill Extractor

## Context

We need to create a Python script that extracts skill information from markdown files using Ollama, following skills-best-practice guidelines. This is similar to the `ai_decision.py` script from the DupeRemoval experiment but adapted for extracting skill data from markdown files.

## Goal

Create a script at `/Users/austin/workspace/agent-ollama-projects/claudeharness/scripts/` that:
1. Scans a user-specified folder for markdown files
2. Uses Ollama (gpt-oss:20b) to extract structured skill information from each file
3. Outputs individual markdown files with concise, relevant skill information
4. Follows skills-best-practice guidelines (concise descriptions, specific focus, practical examples)

## Implementation Approach

### Script Structure

Based on `ai_decision.py`, the script will follow this pattern:

1. **Configuration Section**:
   - Source folder path (customizable)
   - Output folder path
   - Model name (gpt-oss:20b)
   - API timeout
   - Debug flag

2. **Core Functions**:
   - `read_markdown_files(folder_path)` - Read all .md files from a directory
   - `build_prompt(file_content)` - Create a prompt for Ollama to extract skill information
   - `call_ollama(prompt)` - Call Ollama API and parse JSON response
   - `extract_skill_info(file_path, file_content, ai_result)` - Process AI response and create output
   - `write_output(output_path, skill_info)` - Write extracted skill info to markdown file
   - `group_by_skill_category(entries)` - Group files by skill category (Priority, Focus, etc.)

3. **Main Execution Flow**:
   - Read command-line arguments for folder paths
   - Scan source folder for markdown files
   - For each file, extract skill information using Ollama
   - Validate AI response structure
   - Write extracted info to output files

### Key Design Decisions

**Prompt Engineering**:
- Build a prompt that asks Ollama to extract specific skill information:
  - Skill name (from file title or header)
  - Description (concise, third-person, specific)
  - Priority level
  - Focus areas
  - Key topics
  - Use cases
  - Related plan sections
- Use JSON format for structured output (easier to parse)
- Include guidance from skills-best-practice: concise, specific, no XML tags in descriptions

**Output Format**:
- Simple markdown files with extracted skill sections
- No YAML frontmatter (as requested)
- Organized sections for easy reading
- Include rationale for why information was extracted

**Error Handling**:
- If AI fails to parse JSON, fall back to extracting from markdown structure
- If file has no identifiable skill information, skip or provide warning
- Validate extracted information has required fields

**Performance Tracking**:
- Track total API calls, tokens, and duration (similar to ai_decision.py)
- Print summary statistics at the end

### File Paths

**Source Files to Reference**:
- `/Users/austin/workspace/agent-ollama-projects/Experiments/DupeRemoval/scripts/ai_decision.py` - Main structure reference
- `/Users/austin/workspace/agent-ollama-projects/claudeharness/supportFiles/skills-best-practice.md` - Best practices guidance
- `/Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/austin183.github.io/SupportingFiles/skills-to-build.md` - Example skill structure

**Script Location**:
- `/Users/austin/workspace/agent-ollama-projects/claudeharness/scripts/extract-skill-info.py`

**Output Location**:
- `/Users/austin/workspace/agent-ollama-projects/claudeharness/skills-extracted/` (created by script)

### Implementation Details

**Command-line Arguments**:
```bash
python extract-skill-info.py --source /path/to/source --output /path/to/output
```

**Prompt Structure**:
```
Extract skill information from this markdown file:

{file_content}

Return ONLY valid JSON with this structure:
{
  "skill_name": "string",
  "description": "string",
  "priority": "string",
  "focus_areas": ["string", ...],
  "key_topics": ["string", ...],
  "use_cases": ["string", ...],
  "related_plan_sections": ["string", ...],
  "rationale": "string"
}

Rules:
- Description should be concise (under 100 characters)
- Use third-person perspective
- Include specific details, not vague statements
- List items in use_cases should be actionable contexts
```

**Output File Format**:
```markdown
# {skill_name}

## Description
{description}

## Priority
{priority}

## Focus Areas
{focus_areas_list}

## Key Topics
{key_topics_list}

## Use Cases
{use_cases_list}

## Related Plan Sections
{related_plan_sections_list}

## Rationale
{rationale}
```

### Validation

After script execution:
1. Verify output folder contains extracted files
2. Check that each output file is valid markdown
3. Verify JSON parsing succeeded for most files
4. Review a few extracted files to ensure quality

### Success Criteria

- Script successfully reads markdown files from source folder
- Ollama extracts structured skill information
- Output files are valid markdown format
- Descriptions are concise and specific
- Script handles errors gracefully (missing files, AI failures)
- Performance metrics are tracked and displayed

## Testing Strategy

1. Test with a sample markdown file containing skill information
2. Verify script creates output file with extracted content
3. Test error handling (missing source folder, non-markdown files)
4. Test with multiple files to ensure batch processing works
5. Review output quality and conciseness

## Dependencies

- Python 3.x
- ollama library (install via pip)
- Standard libraries: pathlib, csv, json, argparse, sys