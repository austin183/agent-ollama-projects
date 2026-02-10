---
name: skill-extraction
description: Extract actionable skills from reference markdown documents. Call with a markdown document to extract skills from.
---

Extract structured skills from reference markdown documents.

1. Parse the markdown and identify skill sections with metadata
2. Extract skill-specific content (prerequisites, steps, code examples, configuration, troubleshooting)
3. Build rationale from context
4. Format as valid markdown following the template structure

Return markdown following the template structure with all required fields. Ignore project context and general documentation.

## Key requirements

- Description should be concise (under 100 characters)
- Use third-person perspective
- Include specific details, not vague statements
- List items should be actionable
- Use gerund form for skill_name (verb + -ing)
- Use lowercase letters, numbers, and hyphens only
- Content should include all subsections (prerequisites, steps, examples, configuration, troubleshooting, tips)
- URLs, paths, and commands must be preserved exactly
- Code blocks must have proper syntax highlighting
- Use consistent terminology throughout

See README.md for usage examples and CHECKLIST.md for validation criteria.