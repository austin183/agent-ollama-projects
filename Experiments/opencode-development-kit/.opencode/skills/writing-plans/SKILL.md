---
name: writing-plans
description: Plan document formatting — templates, scenario structure, success criteria, and procedural workflows for writing implementation plans. Use when creating or updating plan documents in [docs directory]/plans/.
---

# Writing Plans

This skill provides plan document templates and formatting conventions for implementation plans and test plans.

## Plan Structure Template

Use this structure for implementation plans:

```markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing and why]

## Current State Analysis

[What exists now, what's missing, key constraints discovered]

## Desired End State

[A specification of the desired end state after this plan is complete, and how to verify it]

### Key Discoveries:
- [Important finding with file:line reference]
- [Pattern to follow]
- [Constraint to work within]

## What We're NOT Doing

[Explicitly list out-of-scope items to prevent scope creep]

## Implementation Approach

[High-level strategy and reasoning]

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Changes Required:

#### 1. [Component/File Group]
**File**: `path/to/file.ext`
**Changes**: [Summary of changes]

```[language]
// Specific code to add/modify
```

### Success Criteria:

#### Automated Verification:
- [ ] Migration applies cleanly
- [ ] Unit tests pass
- [ ] Type checking passes (if applicable)
- [ ] Linting passes

#### Manual Verification:
- [ ] Feature works as expected when tested via UI
- [ ] Performance is acceptable under load
- [ ] Edge case handling verified manually
- [ ] No regressions in related features

---

## Phase 2: [Descriptive Name]
[Similar structure...]

---

## Testing Strategy

### Unit Tests:
- [What to test]
- [Key edge cases]

### E2E Tests:
- [End-to-end scenarios]

### Manual Testing Steps:
1. [Specific step to verify feature]
2. [Another verification step]

## Performance Considerations

[Any performance implications or optimizations needed]

## Migration Notes

[If applicable, how to handle existing data/systems]

## References

- Original ticket/description
- Related research documents
- Similar implementation references
```

## Scenario Format

Behavior scenarios use Given-When-Then format in tabular structure:

### Scenario: [Descriptive name]

**Given** [initial context and state]
**When** [action or event occurs]
**Then** [observable outcome]

| # | Given | When | Then |
|---|-------|------|------|
| X.Y.Z.1 | [condition] | [action] | [outcome] |

### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| X.Y.Z.1 | Description | Input description | Expected result |

### E2E Test Scenarios

| # | Test | Steps | Expected |
|---|------|-------|----------|
| X.Y.e.1 | Description | Steps | Expected outcome |

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | [Core functionality tests] | Core functionality — if these fail, the feature doesn't work |
| **P1** | [Structural correctness tests] | Structural correctness and UX safety |
| **P2** | [Edge cases, polish] | Robustness and polish |

## Success Criteria Guidelines

Always separate success criteria into two categories:

1. **Automated Verification** (can be run by execution agents):
   - Commands that can be run: tests, linting, type checking
   - Specific files that should exist
   - Code compilation/type checking
   - Automated test suites

2. **Manual Verification** (requires human testing):
   - UI/UX functionality
   - Performance under real conditions
   - Edge cases that are hard to automate
   - User acceptance criteria

## Iterating on Existing Plans

When updating an existing implementation plan:

1. **Read the current plan completely**: Understand the structure, phases, and scope
2. **Understand the requested changes**: Parse what the user wants to add/modify/remove
3. **Research if needed**: Only spawn research tasks if the changes require new technical understanding
4. **Present understanding and approach**: Confirm your understanding before making changes
5. **Make focused, precise edits**: Use surgical changes, maintain existing structure
6. **Ensure consistency**: If adding a phase, ensure it follows the existing pattern

## Key References

Consult these reference files for detailed procedures:

- `references/create-plan.md` — Initial plan creation process, context gathering, research & discovery, plan structure development
- `references/iterate-plan.md` — Iterating on existing plans, understanding current plan, presenting approach, making precise edits

## Quick Reference Checklist

- [ ] Read all context files completely before planning
- [ ] Research actual code patterns using parallel sub-tasks or specialized agents
- [ ] Include specific file paths and line numbers
- [ ] Write measurable success criteria with clear automated vs manual distinction
- [ ] Use @world-review for perspective on coverage and UX implications
- [ ] Use @planner to plan out tests with context and perspective
- [ ] Iterate the plan section with test scenarios using iterate_plan guidance
- [ ] Include "What We're NOT Doing" section to prevent scope creep
- [ ] Maintain distinction between automated verification and manual verification

---

Base directory for this skill: `.opencode/skills/writing-plans/`
Relative paths in this skill are relative to this base directory.
