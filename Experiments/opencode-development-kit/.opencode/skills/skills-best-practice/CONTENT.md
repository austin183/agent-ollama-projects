# Content Guidelines

## Avoid time-sensitive information

Don't include information that will become outdated.

### Bad example: Time-sensitive (will become wrong)
```markdown
If you're doing this before August 2025, use the old API.
After August 2025, use the new API.
```

### Good example (use "old patterns" section)
```markdown
## Current method

Use the v2 API endpoint: `api.example.com/v2/messages`

## Old patterns

<details>
<summary>Legacy v1 API (deprecated 2025-08)</summary>

The v1 API used: `api.example.com/v1/messages`

This endpoint is no longer supported.
</details>
```

The old patterns section provides historical context without cluttering the main content.

## Use consistent terminology

Choose one term and use it throughout the Skill:

### Good - Consistent
- Always "API endpoint"
- Always "field"
- Always "extract"

### Bad - Inconsistent
- Mix "API endpoint", "URL", "API route", "path"
- Mix "field", "box", "element", "control"
- Mix "extract", "pull", "get", "retrieve"

Consistency helps Claude understand and follow instructions.