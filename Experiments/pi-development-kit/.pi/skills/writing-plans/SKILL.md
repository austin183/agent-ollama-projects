---
name: writing-plans
description: Plan document formatting — templates, scenario structure, success criteria, and procedural workflows for writing implementation plans. Use when creating or updating plan documents in [docs directory]/plans/, decomposing a large plan into per-phase files, converting a code review into a plan (light planning pass), or auditing phase handoffs (ownership pinning, worked-example recompute, phase-close checks).
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

## Plan Decomposition (Large Plans)

When a plan exceeds **~200 lines, 5 phases, or ~15 KB** — or an execution agent is overthinking while working a phase (re-reading the whole plan, drifting into other phases' work) — decompose it into a directory instead of one file. Per-phase context isolation keeps working sessions small while whole-plan detail stays one hop away:

```
[docs directory]/plans/<plan-slug>/
├── index.md              # Navigation + phase map with status (progress source of truth)
├── context.md            # Stable whole-plan detail (decisions, interfaces, strategy, references)
├── behavior-specs.md     # Canonical scenario tables (BDD plans only)
└── phase-N-<slug>.md     # Self-contained: Depends on / Context to load / inlined owned scenarios / success criteria
```

Core rules: each scenario ID is inlined in exactly **one** phase file; depends-on contracts are referenced by ID only; phase files carry an explicit **"Context to load"** reading list; after splitting, archive the original with a "superseded" pointer header.

See `references/decompose-plan.md` for the full procedure, phase-file template, integrity check, and the execution-agent working convention.

## Review → Plan Conversion (Light Planning Pass)

A code review is **plan-ready** when every finding carries location + fix + named regression test. Then the planning pass is transcription + scoping, not a full planning session: verify locations against source (never skip), cluster findings into phases by file ownership (not finding ID), pin fix contracts as RD-decisions, transcribe the review's test expectations into scenario rows, and run the integrity check before marking the plan ready.

See `references/review-to-plan.md` for the plan-ready test, the amendment canonicality convention (`(rev)` / `R-*` / retirement), the scope-list backlog phase template, and the light-pass checklist.

## Phase Handoff Consistency

Decomposition isolates context per phase; these rules keep the loaded context *coherent* across phase boundaries: **pin behavior ownership** at authoring time, **recompute every worked-example constant and verify boundary Givens reach the boundary they name** before a phase is ready, keep **hook semantics in the context entry** (not scenario prose), and run a **handoff audit at phase close** — diff the next phase's context load and inlined tables against as-built code before marking the phase done.

See `references/phase-handoff.md` for the full rules and the phase-close checklist.

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
- `references/decompose-plan.md` — Splitting large plans into per-phase directories: tier layout, phase-file template, ownership rules, integrity check, archiving
- `references/review-to-plan.md` — Converting a plan-ready code review into a phased plan (light planning pass): plan-ready test, file-ownership clustering, amendment canonicality, scope-list backlog phases, checklist
- `script/plan-integrity-check.sh` — Mechanical plan integrity check (ID resolution, phase count vs map, phase-map file existence); run before a plan is marked ready
- `references/phase-handoff.md` — Keeping phase context coherent across boundaries: ownership pinning, worked-example recompute, hook semantics, handoff audit at phase close

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
- [ ] Decompose plans over ~200 lines / 5 phases / ~15 KB into a per-phase directory (`references/decompose-plan.md`)
- [ ] Plan-ready review (location + fix + named test per finding)? Use the light planning pass, not a full planning session (`references/review-to-plan.md`)
- [ ] Before a plan is marked ready: run `script/plan-integrity-check.sh <plan-dir>` — never by eye
- [ ] Before closing a phase: recompute scenario-table constants, verify boundary Givens reach the boundary they name, and run the handoff audit against the next phase (`references/phase-handoff.md`)

---

Base directory for this skill: `.pi/skills/writing-plans/`
Relative paths in this skill are relative to this base directory (e.g. `bash .pi/skills/writing-plans/script/plan-integrity-check.sh <plan-dir>`).
