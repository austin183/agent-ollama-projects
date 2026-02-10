# Skill Extraction

Extracts actionable skills from reference markdown documents and returns structured markdown following a template.

## Usage

Invoke this skill with a markdown document to extract skills from.

The skill parses the document, identifies skill sections, and generates structured markdown following a template with all required sections including skill_name, description, priority, focus_areas, key_topics, use_cases, related_plan_sections, rationale, and content.

See SKILL.md for detailed extraction instructions and template structure.

### Examples:
```
python3 .claude/skills/skill-extraction/scripts/extract-skills.py --source tests/SkillExtraction/testMdFiles/ --destination tests/SkillExtraction/skills-extracted/ --preamble /Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/austin183.github.io/SupportingFiles/threejs-piano-skill-extraction-preamble.md --debug
```

```
python3 .claude/skills/skill-extraction/scripts/extract-skills.py --source /Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/austin183.github.io/SupportingFiles/skillReferences/mdManual/ --destination /Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/austin183.github.io/SupportingFiles/skillReferences/ExtractedManualSkills/ --preamble /Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/austin183.github.io/SupportingFiles/threejs-piano-skill-extraction-preamble.md --debug
```