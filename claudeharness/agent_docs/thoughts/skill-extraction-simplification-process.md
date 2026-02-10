# Skill Extraction Simplification Process

## Status: In Progress

Date: 2026-02-08

## Background

We were discussing simplifying the skill-extraction skill to avoid using JSON as an intermediate format. The current approach requires the AI to output strict JSON, which is then parsed and converted back to markdown. This adds unnecessary complexity.

## Current Implementation

The current skill-extraction skill (`.claude/skills/skill-extraction/`) uses a Python script that:
1. Scans markdown files for skill content
2. Calls Ollama's gpt-oss:20b model via the `chat` function
3. Requires the model to return strict JSON with a defined schema (9 fields)
4. The script parses the JSON and writes individual markdown files

## Proposed Simplification

Use a simpler approach:
1. Skip the JSON intermediate format
2. Ask the model to write markdown directly following a template structure
3. Use a template to guide structure while allowing flexibility
4. Create a validation script to check if extracted skills files contain expected content

## Completed Updates

- [x] Updated SKILL.md to reflect markdown output approach instead of JSON
- [x] Updated README.md to describe the simpler workflow
- [x] Updated CHECKLIST.md to include template structure validation
- [x] Updated WORKFLOWS.md to reflect markdown formatting instead of JSON

## Files Updated

1. `.claude/skills/skill-extraction/SKILL.md`
2. `.claude/skills/skill-extraction/README.md`
3. `.claude/skills/skill-extraction/CHECKLIST.md`
4. `.claude/skills/skill-extraction/WORKFLOWS.md`

## Next Steps (Pending)

1. Create simplified extraction script (`extract-skill-simple.py`) that:
   - Reads markdown files
   - Uses a template-based prompt for the LLM
   - Asks for direct markdown output following the template structure
   - Writes the markdown output to individual files

2. Create validation script (`validate-skill-extraction.py`) that:
   - Scans extracted skill files
   - Validates required sections are present
   - Checks template structure adherence
   - Reports missing or incomplete content

3. Update template file (`scripts/skill-extraction-template.md`) with the new structure if needed

## Decision Points

- The template should be detailed enough to guide the LLM but flexible enough to accommodate different skill content
- Validation should check for presence of required sections but allow some flexibility in structure
- The validation script should be runnable from the command line and report findings clearly

## Key Principles

- Description should be concise (under 100 characters)
- Use third-person perspective
- Include specific details, not vague statements
- List items should be actionable
- Use gerund form for skill_name (verb + -ing)
- Use lowercase letters, numbers, and hyphens only
- Content should include all subsections: Prerequisites, Step-by-step Instructions, Code Examples, Configuration Details, Troubleshooting, Tips
- URLs, paths, and commands must be preserved exactly
- Code blocks must have proper syntax highlighting
- Use consistent terminology throughout

## References

- Core principles: `.claude/skills/skill-extraction/CORE.md`
- Content structure: `.claude/skills/skill-extraction/STRUCTURE.md`