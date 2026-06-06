---
name: reviewing-agents-md
description: Reviews AGENTS.md files for best practices: conciseness, universal applicability, progressive disclosure, and avoiding linter duties. Use when the user asks to review or improve their AGENTS.md file.
---

# Reviewing AGENTS.md

## Core principles

Claude Code uses AGENTS.md to onboard Claude into your codebase for every session. It's the only place where project-specific context automatically goes into every conversation.

**Three key questions AGENTS.md should answer:**
1. **WHAT** - Tech stack, project structure, apps, shared packages, what everything is
2. **WHY** - Project purpose, what each part does, the "why" behind architecture
3. **HOW** - How to work on the project (tools, test commands, verification steps)

## Best practices

### Less (instructions) is more

- Keep AGENTS.md concise and universally applicable
- Avoid stuffing every command Claude might need
- Focus on high-leverage, always-relevant information
- Aim for < 300 lines if possible

### Progressive disclosure

Instead of bundling everything in AGENTS.md:
```
agent_docs/
  ├─ building_the_project.md
  ├─ running_tests.md
  ├─ code_conventions.md
  ├─ service_architecture.md
  └─ database_schema.md
```

Point to these files and let Claude decide which are relevant.

### What to include

✅ **Always include:**
- Project tech stack and key libraries
- Project structure overview
- Purpose of different directories/packages
- Key commands for common tasks (tests, builds, deployment)
- Verification methods for changes

❌ **Avoid including:**
- Code style guidelines (use linters/formatters instead)
- Task-specific instructions that only apply sometimes
- Configuration snippets that become outdated
- Project-specific quirks that don't apply broadly

### Claude is not a linter

Use deterministic tools (Biome, ESLint, Prettier, etc.) for code style. Don't make Claude do a linter's job—this adds irrelevant instructions and hurts performance.

## Review checklist

When reviewing a AGENTS.md file, verify:

1. **Conciseness**: Does it cover the essentials without being verbose?
2. **Universality**: Would these instructions apply to different tasks, or is it too task-specific?
3. **What/Why/How**: Does it explain the project's purpose, structure, and workflow?
4. **Progressive disclosure**: Are task-specific details in separate files?
5. **No linter duties**: Are there any code style guidelines that should be in a linter?
6. **Length**: Is it under 300 lines (ideally much less)?

## When NOT to use this skill

This skill is designed for reviewing AGENTS.md files. Use other skills for:

- Writing code
- Running tests
- Generating documentation
- Code review
- Project-specific tasks