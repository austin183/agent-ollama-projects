# Skill Extraction Preamble Guide

## Purpose

This preamble serves as a template for guiding the AI extraction process. It defines how skill information should be identified and structured from source markdown documents.

## What is a Preamble?

A preamble is a special instruction file that tells the AI:

1. **What to extract** - The types of skills and information to look for
2. **How to structure it** - The output format and sections required
3. **Quality standards** - Criteria for what constitutes a good extraction
4. **What to avoid** - Common pitfalls and incorrect output patterns

## How to Use This Preamble

1. **Copy** this file to create your custom preamble
2. **Customize** the sections below to match your extraction goals
3. **Run** the extraction script with `--preamble /path/to/your-preamble.md`

```
python3 scripts/extract-skills.py \
  --source /path/to/source \
  --destination /path/to/output \
  --preamble /path/to/your-preamble.md
```

## Customization Guide

### Focus Areas - What This Skill Covers

Define the primary domains this skill addresses:

```
### Focus Areas
Identify the primary areas this skill addresses:
- Technical implementation details
- Problem-solving approaches and methodologies
- Tool and framework usage
- Best practices and patterns
- Common workflows and processes
```

**Customize by:** Add/remove areas specific to your content domain

### Key Topics - Specific Subjects to Extract

Define concrete topics the skill should cover:

```
### Key Topics
Extract specific, actionable topics:
- API endpoints and functions
- Configuration options and settings
- Command-line arguments and usage
- File formats and data structures
- Error messages and their solutions
- Integration points and dependencies
```

**Customize by:** List the specific technologies or concepts in your source

### Use Cases - When to Apply This Skill

Define real-world scenarios:

```
### Use Cases
Determine when to apply this skill:
- Debugging specific error conditions
- Implementing new features
- Migrating from older versions
- Optimizing performance
- Setting up development environments
- Troubleshooting production issues
```

**Customize by:** Add scenarios relevant to your documentation

### Output Format Requirements

The output must follow this structure exactly:

```
# skill-name

## Description
[1 sentence, under 100 characters]

## Priority
HIGH or MEDIUM or LOW

## Focus Areas
- [3 specific areas]

## Key Topics
- [3 specific topics]

## Use Cases
- [3 specific use cases]

## Content

### Prerequisites
[what must be set up first]

### Step-by-step Instructions
1. [step with specific commands]
2. [step with specific commands]
3. [step with specific commands]

### Code Examples
```language
[code snippet]
```

### Configuration Details
- URL: [relevant URL]
- Path: [relevant path]
- Command: [relevant command]

### Troubleshooting
**Problem**: [common issue]
**Solution**: [step-by-step fix]

### Tips
- [best practice]
- [common pitfall]
- [additional note]
```

## Quality Standards

### High Priority Skills
- Solves a common, time-consuming problem
- Involves non-obvious techniques or configurations
- Required for multiple other skills to work
- Well-documented with clear examples

### Medium Priority Skills
- Addresses occasional needs
- Uses standard but not trivial approaches

### Low Priority Skills
- Simple, straightforward procedures
- Already covered extensively elsewhere

## Common Pitfalls

1. **Too vague** - "useful commands" vs "git commands for branch management"
2. **Missing code** - Every skill should have working code examples
3. **No troubleshooting** - Missing common error scenarios
4. **Project-specific** - Including context that won't apply elsewhere
5. **Incomplete** - Skipping required sections in the output format

## Verification Checklist

Before finalizing an extraction, verify:

- [ ] Description is under 100 characters
- [ ] Priority is clearly HIGH, MEDIUM, or LOW
- [ ] All focus areas are specific and actionable
- [ ] All key topics are concrete (not abstract)
- [ ] Use cases describe real scenarios
- [ ] Prerequisites are complete and testable
- [ ] Steps include exact commands
- [ ] Code has proper syntax highlighting
- [ ] Configuration has real values
- [ ] Troubleshooting includes actual error messages
- [ ] Tips provide genuine value
