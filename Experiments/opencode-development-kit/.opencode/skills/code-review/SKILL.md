---
name: code-review
description: Reviews code changes for SOLID principles, separation of concerns, design quality, and code health. Use when reviewing pull requests, commit changes, or requesting architectural feedback on code.
---
# Code Review

## Overview

This skill provides a structured approach to code review focused on architectural quality, design principles, and long-term maintainability. Priority is given to SOLID principles and separation of concerns, with style compliance as a secondary concern.

## Core Principles

### SOLID Principles

Review for adherence to SOLID design principles:

| Principle | Question to Ask |
|-----------|-----------------|
| **Single Responsibility** | Does each class/module have one clear reason to change? |
| **Open/Closed** | Is the code open for extension but closed for modification? |
| **Liskov Substitution** | Can subclasses be used wherever their base class is expected? |
| **Interface Segregation** | Are interfaces focused and clients not forced to depend on unused methods? |
| **Dependency Inversion** | Do high-level modules depend on abstractions, not concretions? |

### Separation of Concerns

- **Layering**: Code should be organized into logical layers (presentation, business logic, data access)
- **Cohesion**: Related functionality should be grouped together
- **Coupling**: Dependencies between modules should be minimal and through interfaces
- **Single Source of Truth**: No duplicate logic or configuration

## Review Checklist

### Architecture & Design

- [ ] Classes have single, well-defined responsibilities
- [ ] Dependencies are injected rather than hardcoded
- [ ] Business logic is separated from infrastructure concerns
- [ ] New code follows existing architectural patterns
- [ ] No circular dependencies are introduced

### Code Quality

- [ ] Functions are small and focused (one responsibility per function)
- [ ] Naming clearly communicates intent
- [ ] Complex logic is broken into smaller, testable units
- [ ] Error handling is consistent and appropriate
- [ ] State is managed explicitly where needed

### Testing

- [ ] New code has corresponding tests
- [ ] Tests cover edge cases and error conditions
- [ ] Tests are isolated and deterministic
- [ ] Mock dependencies are appropriate

### Documentation

- [ ] Public APIs are documented
- [ ] Complex algorithms have explanatory comments
- [ ] TODOs are accompanied by issue references or explanations
- [ ] Configuration changes are documented

### Style & Consistency

- [ ] Code follows project style guide (run linters first)
- [ ] Formatting is consistent with surrounding code
- [ ] Only style issues marked with `Nit:` are optional suggestions

## Step-by-Step Review Process

### 1. Understand Context
Don't ask a subagent to read you the contents of files.  That is an inefficient way to get the contents of files you are interested in.

1. Read the commit message and PR description
2. Review any related design documents or issues
3. Understand the intended behavior and edge cases

### 2. Run a Subagent for High-Level Design Review for each Domain

Focus on architecture and SOLID principles:

1. **Check module boundaries** - Are responsibilities properly separated?
2. **Trace data flow** - How does information move through the system?
3. **Identify tight coupling** - Are classes/modules too interdependent?
4. **Evaluate extensibility** - Can new features be added without modification?

### 3. Detailed Code Review

#### Run Subagents for each aspect of the review for each file:

1. **Read the overall structure**
   - Are classes/functions organized logically?
   - Are related concerns grouped together?

2. **Review individual functions**
   - Is the function doing one thing?
   - Is it too long or complex?
   - Does it have appropriate parameters and return values?

3. **Check dependencies**
   - Are dependencies injected or created internally?
   - Are concrete classes depended on instead of interfaces?
   - Are circular dependencies present?

4. **Verify error handling**
   - Are errors caught and handled appropriately?
   - Is there proper validation of inputs?
   - Are edge cases considered?

### 4. Provide Feedback

**Critical issues** (must be fixed):
- Violations of SOLID principles
- Design flaws that will impede future changes
- Incorrect behavior or missing tests

**Nit comments** (optional polish):
- Style guide deviations that don't affect readability
- Minor naming improvements
- Formatting preferences

### 5. Approval Decision

**Approve** when:
- SOLID principles are followed
- Code is maintainable and extensible
- Tests cover important scenarios
- No blocking issues remain

**Request changes** when:
- Major design flaws exist
- SOLID principles are violated
- Tests are missing for new functionality
- Documentation is incomplete

## Common Red Flags

### SOLID Violations

| Pattern | Problem | Suggested Fix |
|---------|---------|---------------|
| God class | Violates SRP | Split into smaller, focused classes |
| Tight coupling | Violates DIP | Depend on interfaces, inject dependencies |
| Huge if-else chain | Violates OCP | Use polymorphism or strategy pattern |
| Interface with many methods | Violates ISP | Split into smaller interfaces |

### Separation of Concerns Issues

- **Business logic in UI layer** - Move to service layer
- **Database queries in controllers** - Move to repository/DAO
- **Configuration in code** - Move to config files/environment
- **Duplicate logic** - Extract to shared utility

## Tips

1. **Start with the big picture** - Fix architectural issues before nitpicking style
2. **Ask questions** - "Why was this approach chosen?" can lead to better solutions
3. **Pair on complex reviews** - Two perspectives catch more issues
4. **Document decisions** - Record architectural decisions for future maintainers
5. **Iterate** - It's okay to approve the concept and follow up on details

## Style Guide References

For detailed style guide compliance, see the [reference](reference/) folder:

| Language | Reference |
|----------|-----------|
| TypeScript | See [typescript.md](reference/typescript.md) |
| JavaScript | See [javascript.md](reference/javascript.md) |
| Python | See [python.md](reference/python.md) |
| HTML/CSS | See [html-css.md](reference/html-css.md) |
| Markdown | See [markdown.md](reference/markdown.md) |

## Code Review Checklist

See [checklist.md](reference/checklist.md) for a comprehensive review checklist covering:
- Design evaluation
- Functionality verification
- Test coverage
- Style compliance
- Documentation

## Best Practices

See [best-practices.md](reference/best-practices.md) for:
- Review process guidance
- Quality assurance techniques
- Mentoring approaches
- Resolving conflicts

## When NOT to Use This Skill

Use dedicated style guide skills when:
- Only style compliance needs verification (run linters instead)
- The codebase has specific, unique review criteria not covered here
