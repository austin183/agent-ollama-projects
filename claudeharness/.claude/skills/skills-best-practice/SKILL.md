---
name: skills-best-practice
description: Authoring guide for creating effective Skills that Claude can discover and use. Use when writing new Skills, refining existing Skills, or learning about Skill authoring best practices.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Skills Best Practices

Author effective Skills for Claude to discover and use successfully. This skill provides comprehensive guidance on Skill authoring, structured by domain for progressive disclosure.

## Quick Navigation

| Topic | Reference |
|-------|-----------|
| **Core principles** | See [CORE.md](CORE.md) - Conciseness, degrees of freedom, model testing |
| **Skill structure** | See [STRUCTURE.md](STRUCTURE.md) - YAML, naming, descriptions, progressive disclosure |
| **Workflows** | See [WORKFLOWS.md](WORKFLOWS.md) - Checklists, feedback loops |
| **Content guidelines** | See [CONTENT.md](CONTENT.md) - Time sensitivity, terminology |
| **Common patterns** | See [PATTERNS.md](PATTERNS.md) - Templates, examples, conditional workflows |
| **Evaluation** | See [EVALUATION.md](EVALUATION.md) - Build evaluations, iterative development |
| **Advanced topics** | See [ADVANCED.md](ADVANCED.md) - Executable code, runtime, MCP tools |
| **Checklist** | See [CHECKLIST.md](CHECKLIST.md) - Verify before sharing a Skill |

## What is a Skill?

A Skill is a reusable set of instructions, code, and resources that Claude can invoke to perform specific tasks. Skills are discovered through their name and description, loaded on-demand, and help Claude work more effectively.

## When to use this Skill

- Creating a new Skill from scratch
- Refining an existing Skill
- Understanding Skill architecture and limitations
- Debugging Skill discovery issues
- Evaluating Skill effectiveness