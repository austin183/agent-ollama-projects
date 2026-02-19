---
name: skill-extraction
description: Guide to extracting skills from markdown documents using the extract-skills.py script. Helps you write effective preambles and run the extraction tool.
---

# Skill Extraction Workflow

This skill guides you through extracting structured skill information from markdown documents using the `extract-skills.py` Python script.

## The Extraction Process

### Step 1: Write a Preamble

A preamble is a template that tells the AI how to extract skill information. Start by writing or customizing a preamble that matches your extraction goals.

**Good preambles should:**
- Describe the type of skills to extract
- Specify the output format and sections needed
- Define quality standards and examples
- Include examples of good/bad output

**Location:** `scripts/default-preamble.md` - copy and customize this for your needs.

### Step 2: Run the Extraction Script

```bash
python3 scripts/extract-skills.py \
  --source /path/to/source/markdown/files \
  --destination /path/to/output/directory \
  --preamble /path/to/custom/preamble.md
```

**Options:**
- `--source` (required): Folder containing markdown files to process
- `--destination` (required): Output folder for extracted skills
- `--preamble` (optional): Custom preamble file (uses `default-preamble.md` if not specified)
- `--debug`: Enable debug output for troubleshooting

### Step 3: Review the Results

The script creates individual markdown files for each extracted skill in the output directory. Review the results and refine your preamble if needed.

## Key Requirements for Quality Extractions

- **Description:** Concise (under 100 characters), third-person perspective
- **Focus Areas:** 3 specific areas the skill addresses
- **Key Topics:** 3 concrete topics (APIs, commands, config options)
- **Use Cases:** 3 specific scenarios where the skill is useful
- **Content:** All subsections must be filled (prerequisites, steps, examples, configuration, troubleshooting, tips)
- **Code:** Use proper syntax highlighting
- **Paths/URLs:** Preserve exact values from source
- **Terminology:** Be consistent throughout

See `CHECKLIST.md` for validation criteria.

## Examples

See `README.md` for example commands and usage patterns.
