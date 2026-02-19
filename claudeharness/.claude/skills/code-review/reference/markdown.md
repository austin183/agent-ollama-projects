# Markdown Style Guide

## Contents
- Document structure
- Headings and titles
- Code blocks
- Links and references
- Common pitfalls

## Document Structure

### File Header
```markdown
# Document Title

Short introduction.

[TOC]
```

### Single H1 Rule
- Use only one H1 (the document title)
- Avoid underlined headings (`===` or `---`)

## Headings

### ATX Style (Recommended)
```markdown
## Topic
### Subtopic
#### Sub-subtopic
```

### Heading Depth
- Limit to 3-4 levels deep
- Don't skip levels (H2 → H4 is bad)

## Code Blocks

### Fenced Blocks
```markdown
```python
def example_function():
    print("Hello, World!")
```
```

### Requirements
- Use language identifier: ````python`, ````javascript`
- No indented code blocks

## Links

### Inline Links (Simple)
```markdown
[See the guide](markdown.md)
```

### Reference Links (Complex/Long)
```markdown
[See the guide][1]

[1]: markdown.md
```

### Best Practices
- Keep line lengths manageable
- Use reference links for repeated URLs

## Content Style

### Bullet Lists
```markdown
- Item one
- Item two
  - Nested item
- Item three
```

### Numbered Lists
- Use for sequential steps
- Don't worry about numbering (Markdown handles it)

## Validation

### markdownlint
```bash
npm install -g markdownlint
markdownlint -c .markdownlint.json file.md
```

### Configuration
```json
{
  "default": true,
  "MD001": false,
  "MD013": { "line_length": 120 }
}
```

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| Multiple H1 headings | Keep only the document title as H1 |
| Indented code blocks | Use fenced blocks with language |
| Broken references | Verify all reference links exist |
| Inconsistent list markers | Use `-` or `*` consistently |

## Configuration

- **URL**: https://example.com/docs/markdown-style-guide
- **Command**: `markdownlint -c .markdownlint.json file.md`
