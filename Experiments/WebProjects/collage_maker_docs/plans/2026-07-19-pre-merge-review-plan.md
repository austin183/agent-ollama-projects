# Pre-Merge Review Plan — PR #12 (prototype/collage-maker → main)

**Date:** 2026-07-19
**Branch:** `prototype/collage-maker`
**Scope:** 195 files, 49,244 insertions, 14 commits
**Prior reviews:** 7 existing review documents in `_agent_docs/reviews/`

---

## Overview

This plan outlines the review strategy for merging PR #12, which introduces the entire CollageMaker web application to `main`. The branch has already undergone 7 rounds of review with issues tracked and resolved. The most recent commit (39d5ae2, July 19) contains ~1,209 lines of changes that have not yet been reviewed.

Given the massive scope (49k lines), the review is structured by domain using parallel subagents to maximize throughput while maintaining thoroughness.

---

## Current State Analysis

### What's Been Reviewed

Seven prior review documents exist in `_agent_docs/reviews/`:
- `2026-07-03-prior-to-phase4-review.md`
- `2026-07-04-post-phase3-state-review.md`
- `2026-07-05-pre-commit-review.md`
- `2026-07-07-pre-commit-solid-review.md`
- `2026-07-09-pre-commit-review.md`
- `2026-07-12-pre-merge-review-final.md` — identified 7 issues, blocked merge on `_onWheel` `preventDefault()`
- `2026-07-15-title-sidebar-home-review.md` — identified missing settings persistence for title fields
- `2026-07-18-title-changes-review.md` — approved multi-line title feature with 6 nits

### Unreviewed Changes

The latest commit (39d5ae2) introduced 19 files (~1,209 insertions) covering:
- Image loading progress overlay (`ImageLibrary.js`)
- Title Enter key guard + truncation toast (`TitleManager.js`, `index.html`)
- Touch-friendly edge thresholds for WCAG compliance (`Style.css`)
- Shared measure canvas optimization
- Phase 1/2 test suites
- Blog post

### Key Discoveries

- The codebase follows a factory-function architecture with `attach()`/`detach()` lifecycle patterns
- All prior blocking issues were related to interaction handlers (`MultiTouchHandler`, `HexPanelSwap`) and title system completeness
- Test suite: 237+ unit tests across 36 HTML test files, 7 Playwright E2E specs
- `_agent_docs/` is gitignored, so review documents live outside version control

---

## Desired End State

A consolidated review document at `_agent_docs/reviews/2026-07-19-pre-merge-final-review.md` containing:
- Verification that all 12 prior issues are resolved
- Architecture review findings across 8 domains
- UX review findings from world-review agent
- Test coverage assessment
- Final verdict: **APPROVE** or **REQUEST CHANGES** with actionable items

---

## What We're NOT Doing

- Not rewriting or refactoring code — this is a review-only engagement
- Not reviewing `.opencode/` agent/skill files for correctness (they are tooling, not app code)
- Not reviewing `_agent_docs/` content for quality
- Not running a security audit (static web app, no server, no auth)

---

## Implementation Approach

### Phase 0: Run Tests (blocking, sequential)

Establish baseline before any review.

**Automated Verification:**
- [ ] Run unit tests: `node scripts/run-tests.js` from `CollageMaker/`
- [ ] Run E2E tests: `npx playwright test --config=playwright.config.cjs` (requires dev server on :8080)
- [ ] Document test count and any failures

### Phase 1: Latest Commit Deep Dive

Focus on the 19 files in commit 39d5ae2 that haven't been reviewed yet.

**Subagents (parallel):**

| Subagent | Scope | Focus |
|----------|-------|-------|
| `solid-review` | `ImageLibrary.js` | Progress overlay architecture, callback injection, cleanup on image unload, memory management |
| `world-review` | Loading overlay, truncation toast, WCAG touch thresholds | UX of loading feedback, toast messaging clarity, 44x44px touch target compliance, Enter key guard behavior |
| `explore` | New Phase 1/2 test suites | Map test coverage for latest changes, identify gaps |

### Phase 2: Domain-Level Architecture Review

Launch 8 subagents in parallel, one per domain. Each reviews for SOLID principles, separation of concerns, and architectural consistency.

| Domain | Modules | Focus |
|--------|---------|-------|
| **A: State** | `ImageLibrary.js`, `LayoutManager.js`, `BackgroundManager.js`, `TitleManager.js`, `CropManager.js`, `UndoManager.js`, `actions.js` | SRP per manager, explicit mutations via actions, batch undo/redo correctness, cross-manager coordination |
| **B: Layout** | `LayoutGenerator.js`, `UniformLayout.js`, `HeroLayout.js`, `HexagonalLayout.js`, `MosaicLayout.js`, `DiagonalSlicesLayout.js`, `FitMath.js`, `PolygonClipper.js`, `SeededPRNG.js`, `CropOverlayShape.js`, `PanelGeometry.js` | Pure functions, extensibility (new layouts without modifying generator), hexagonal comment accuracy (prior issue #4) |
| **C: Rendering** | `CanvasRenderer.js`, `PanelRenderer.js`, `BackgroundRenderer.js`, `TitleRenderer.js`, `OverlayRenderer.js`, `CollageAssembler.js`, `SaliencyDebugOverlay.js` | Render order (prior issue #2), DPR scaling consistency, export canvas clearing, shared measure canvas optimization |
| **D: Interaction** | `MultiTouchHandler.js`, `GestureHandler.js`, `PanelSwap.js`, `TitleInteraction.js`, `CropInteraction.js`, `FileDropHandler.js`, `KeyboardHandler.js` | Cross-handler coordination, pointer capture issues (prior #1, #3, #5, #6), cleanup on detach |
| **E: App Assembly** | All `create*Handlers.js`, `createCollageApp.js`, `createCollageData.js`, `createCollageLifecycle.js`, `createCollageMethods.js`, `createCollageServices.js`, `createRenderMethods.js`, `createUndoMethods.js`, `createCropPreviewRenderer.js`, `CollageBase.js` | Factory pattern consistency, dependency injection, undo callback staleness (prior #7), initialization order |
| **F: Export/Persistence** | `ExportManager.js`, `jpegExporter.js`, `pngExporter.js`, `SettingsPersistence.js` | Format extensibility, export canvas clearing, all title fields persisted (prior issue from 07-15 review) |
| **G: Saliency/Utils** | `SaliencyAnalyzer.js`, `SaliencyFallback.js`, `BrowserUtils.js`, `PWACacheUtils.js`, `ResponsiveUtils.js`, `loadImageFromFile.js` | Web worker usage, CORS handling, PWA cache correctness, responsive breakpoints |
| **H: Models** | `ImageItem.js`, `ImagePanel.js`, `LayoutStyle.js`, `BackgroundStyle.js`, `TitleStyle.js`, `TitleRun.js`, `CropInfo.js`, `SizeConstants.js` | Plain objects vs classes, centralized constants, no duplication |

### Phase 3: World-Review UX Analysis

**Subagent:** `world-review`
**Scope:** Entire application from end-user perspective
**Can run in parallel with Phase 2**

**Focus areas:**
1. Onboarding: Landing page, first-time user flow, file loading
2. Accessibility: ARIA labels, keyboard navigation, screen reader support, reduced motion, touch target sizes (WCAG 44x44px)
3. Responsive design: Mobile, tablet, desktop breakpoints
4. Error handling: Image load failures, export failures, storage full
5. Performance perception: Loading overlays, progress indicators, toast notifications
6. PWA capabilities: Install prompt, offline behavior, cache strategy
7. Title editing: Multi-line editing, formatting toolbar, drag/resize
8. Crop interaction: Preview overlay, undo support, edge cases
9. Export UX: Format selection, quality control, download feedback

### Phase 4: Test Coverage Review

**Subagent:** `explore` (thoroughness: very thorough)
**Can run in parallel with Phase 5**

**Focus:**
1. Unit tests (36 HTML test files): Each source module has corresponding tests; edge cases, error conditions, deterministic behavior
2. E2E tests (7 Playwright specs): Critical user workflows (load → arrange → export); flaky test patterns
3. Phase test suites (Phase 1-5): Behavior characterization and regression catching
4. Test infrastructure: `run-tests.js`, `run-page-tests.cjs`, `test-es-modules.html`
5. Coverage gaps: Source modules without test coverage

### Phase 5: HTML/CSS/Entry Point Review

**Subagent:** `world-review`
**Can run in parallel with Phase 4**

**Files:** `index.html`, `Style.css`, `BlogPosts/*`

**Focus:**
1. `index.html`: Vue template structure, sidebar organization, ARIA attributes, keyboard shortcuts
2. `Style.css`: Responsive breakpoints, CSS custom properties, print styles
3. Blog posts: Content accuracy, links, images

### Phase 6: Configuration & Infrastructure (lightweight, manual)

**Files:** `playwright.config.cjs`, `package.json`, `.gitignore`, `scripts/*`

**Focus:**
1. Playwright config: Browser targets, timeout, retry settings
2. `package.json`: Dependencies, scripts
3. `.gitignore`: Correct exclusions
4. Scripts: Test runners, interactive test helper

### Phase 7: Prior Issues Verification (manual cross-reference)

Verify resolution of all issues from prior reviews:

| # | Source | Issue | Severity |
|---|--------|-------|----------|
| 1 | 07-12 final | `_onWheel` unconditional `preventDefault()` blocks page scroll | Medium (was blocking) |
| 2 | 07-12 final | Hex drag target drawn after selection border (render order) | Minor |
| 3 | 07-12 final | HexPanelSwap / MultiTouchHandler pointer conflict | Low-Medium |
| 4 | 07-12 final | `HexagonalLayout` comment accuracy for `R_grid` scaling | Low |
| 5 | 07-12 final | Incomplete pointer capture in `_onPointerDown` | Low-Medium |
| 6 | 07-12 final | Missing `releasePointerCapture` | Low |
| 7 | 07-12 final | Potential stale undo callbacks | Low |
| 8 | 07-15 review | Missing settings persistence for new title fields | Medium (was blocking) |
| 9 | 07-18 review | Duplicate MARGIN constant in `TitleInteraction.js` | Nit |
| 10 | 07-18 review | Offscreen canvas in interaction hot path | Nit |
| 11 | 07-18 review | Enter key flicker on 3-line title | Nit |
| 12 | 07-18 review | Silent truncation feedback for pasted text | Nit |

---

## Execution Order

```
Phase 0: Run tests (sequential, blocking)
  ↓
Phase 1: Latest commit deep dive (3 parallel subagents)
  ↓
Phase 2: Domain architecture reviews (8 parallel subagents)
  ┃
  └─ Phase 3: World-review UX (parallel with Phase 2)
        ↓
Phase 4: Test coverage review (parallel with Phase 5)
  ┃
  └─ Phase 5: HTML/CSS review (parallel with Phase 4)
        ↓
Phase 6: Config review (manual, lightweight)
  ↓
Phase 7: Prior issues verification (manual cross-reference)
  ↓
Consolidate findings → write final review → APPROVE or REQUEST CHANGES
```

**Wall-clock optimization:** Phases 2+3 run simultaneously. Phases 4+5 run simultaneously.

---

## Success Criteria

### Automated Verification:
- [ ] All 237+ unit tests pass
- [ ] All 7 Playwright E2E specs pass
- [ ] No new blocking issues discovered

### Manual Verification:
- [ ] All 12 prior issues verified as resolved
- [ ] Architecture review yields no new SOLID violations
- [ ] World-review identifies no critical UX regressions
- [ ] Test coverage gaps are documented and assessed for risk
- [ ] Final consolidated review document written to `_agent_docs/reviews/2026-07-19-pre-merge-final-review.md`

---

## Decision Criteria

**APPROVE if:**
- All blocking issues from prior reviews are resolved
- No new blocking issues found
- Tests pass (237+ unit, 7 E2E)
- SOLID principles followed across all 8 domains
- UX is functional and accessible

**REQUEST CHANGES if:**
- Any blocking issue remains unresolved
- New blocking issues discovered
- Major SOLID violations found
- Critical test gaps identified
- User-facing regressions detected

---

## Subagent Output Format

Each subagent should return findings structured as:

```
## [Domain Name] Review

### Blocking Issues
- [description, file:line, severity, fix suggestion]

### Concerns (should fix before merge)
- [description]

### Nits (optional)
- [description]

### Prior Issues Status
- [verified fixed / still present / N/A]
```

---

## References

- Prior reviews: `_agent_docs/reviews/` (7 documents)
- Code review skill: `.opencode/skills/code-review/`
- Building web apps skill: `.opencode/skills/building-web-apps/`
- AGENTS.md: `CollageMaker/AGENTS.md`
