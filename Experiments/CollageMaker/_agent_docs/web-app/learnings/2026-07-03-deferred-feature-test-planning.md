# Deferred Feature Test Planning

**Date:** 2026-07-03
**Session:** 23 (Section 3.3 — ML-Based Saliency test plan)

## Summary

When a feature is deferred (not yet implemented), writing a comprehensive test plan first serves as both a requirements document and a risk assessment. The pattern emerged during planning for Section 3.3 ML-Based Saliency, where 138 test scenarios were designed before any production code existed.

## Pattern: Test-Plan-First for Deferred Features

### Why It Works

1. **Surfaces hidden requirements** — Writing "what should happen" forces concrete thinking about edge cases that a feature spec might gloss over.
2. **Defines acceptance criteria upfront** — The test plan becomes the contract between "feature designed" and "feature done."
3. **Identifies infrastructure gaps** — Planning tests reveals what infrastructure is needed (worker threads, mock data, performance budgets) before implementation starts.
4. **Enables parallel work** — Test fixtures and helper infrastructure can be built while the feature is still being designed.

### Structure Used

```
Section 3.3 ML-Based Saliency
├── Pure Function Unit Tests (72 scenarios)
│   ├── Saliency map computation
│   ├── Crop recommendation algorithms
│   └── Scoring functions
├── Worker Protocol Tests (20 scenarios)
│   ├── Message passing
│   ├── Error propagation
│   └── Lifecycle (terminate/restart)
├── Integration Tests (26 scenarios)
│   ├── Manager ↔ Worker coordination
│   ├── State updates
│   └── Fallback behavior
└── E2E Tests (20 scenarios)
    ├── User-visible behavior
    ├── Performance budgets
    └── Accessibility
```

### Non-Functional Requirements from World-Review

Pairing a **world-review** subagent (UX/experience focus) with a **planner** subagent (technical design) during test planning surfaces requirements that pure technical planning misses:

| Category | Requirement | Test Implication |
|----------|-------------|-----------------|
| Graceful degradation | Feature works without ML model | Test fallback to uniform crop |
| Non-blocking | UI remains responsive | Test with artificial worker delays |
| Privacy | No image data leaves the device | Test worker runs in-browser only |
| Accessibility | Screen reader compatible | Test aria-live regions for status |
| Memory management | No leaks on repeated use | Test multiple analyze cycles |

## Key Decision: 138 Scenarios, Zero Implementation

The test plan was written as a **specification document** (Markdown in `_agent_docs/plans/`), not as executable test files. This is appropriate when:

- The feature is deferred (no production code to test against)
- The test scenarios are complex and need human review before coding
- The plan serves as a shared reference for multiple future sessions

**When to write executable tests vs. a plan:**
- If the feature is being implemented **now**, write executable tests (TDD)
- If the feature is **deferred**, write a test plan document
- If the feature is **partially implemented**, write tests for what exists and a plan for what's missing

## Integration with Project Plans

The test plan was embedded into the existing priority plan (`2026-07-02-midpoint-gap-phase4-priority-plan.md`) as an expanded Section 3.3, with:
- Success criteria updated with deferred saliency verification items
- Deferred critical files list identifying which modules need new test coverage

This keeps the test plan discoverable as part of the broader project plan rather than as a standalone document.

## File Reference

- Plan: `_agent_docs/plans/2026-07-02-midpoint-gap-phase4-priority-plan.md` (Section 3.3)
- Session: `session-023-summary.json`

---

**Status:** Closed
**Follow-up:** When Section 3.3 implementation begins, convert this plan into executable test files.
