# Skill Extraction

A workflow for extracting structured skill information from markdown documents using the `extract-skills.py` Python script and Ollama AI.

## Overview

This tool helps you convert existing documentation into structured, reusable skill templates. The process has two main steps:

1. **Write a preamble** - A template that guides the AI on how to extract skill information
2. **Run the script** - Process your markdown files and generate skill templates

## Quick Start

### 1. Prepare Your Source Files

Gather all markdown files you want to extract skills from into a single folder:

```
source-files/
  ├─ tutorial1.md
  ├─ reference-guide.md
  └─ how-to-article.md
```

### 2. Write or Customize a Preamble

Start with `scripts/default-preamble.md` and customize it for your extraction goals. The preamble tells the AI:

- What type of skills to extract
- Which sections to include in the output
- Quality standards to apply
- Specific formatting requirements

### 3. Run the Extraction Script

```bash
# Basic usage with default preamble
python3 scripts/extract-skills.py \
  --source /path/to/source/files \
  --destination /path/to/output

# Custom preamble
python3 scripts/extract-skills.py \
  --source /path/to/source/files \
  --destination /path/to/output \
  --preamble /path/to/custom-preamble.md

# With debug output
python3 scripts/extract-skills.py \
  --source /path/to/source/files \
  --destination /path/to/output \
  --debug
```

## Prerequisites

- Python 3.x
- Ollama installed and running
- `ollama` Python library (`pip install ollama`)
- The `gpt-oss:20b` model pulled in Ollama (`ollama pull gpt-oss:20b`)

## Output Format

Each extracted skill becomes a markdown file with this structure:

```markdown
# skill-name

## Description
[concise description]

## Priority
HIGH or MEDIUM or LOW

## Focus Areas
- [area 1]
- [area 2]
- [area 3]

## Key Topics
- [topic 1]
- [topic 2]
- [topic 3]

## Use Cases
- [use case 1]
- [use case 2]
- [use case 3]

## Content

### Prerequisites
[required setup]

### Step-by-step Instructions
1. [step 1]
2. [step 2]
3. [step 3]

### Code Examples
```language
[code]
```

### Configuration Details
- URL: [relevant URL]
- Path: [relevant path]
- Command: [relevant command]

### Troubleshooting
**Problem**: [issue]
**Solution**: [resolution]

### Tips
- [tip 1]
- [tip 2]
```

## Tips for Good Results

1. **Clear source documents** - Well-structured markdown with code examples and troubleshooting sections yield better results

2. **Custom preambles** - Generic preambles work, but custom ones tailored to your content produce higher quality extractions

3. **Start small** - Test with 1-2 files first, review results, then scale up

4. **Review and refine** - The script provides a good first draft; always review and refine the output

5. **Iterate on the preamble** - If results are not quality, adjust the preamble and rerun

## See Also

- `SKILL.md` - Detailed workflow documentation
- `CHECKLIST.md` - Validation checklist for extracted skills
- `scripts/default-preamble.md` - Default preamble template
- `scripts/default-output.md` - Output template structure
