# CollageMaker Web Port — Midpoint Gap Analysis & Next Steps

**Date:** 2026-07-02  
**Scope:** Midpoint analysis of implementation plans and sessions against the master web port concept  
**References:** [Web Port Implementation Plan](./2026-06-30-collagemaker-web-port-implementation.md), [Pre-Phase 3 Test Plan](./2026-07-01-collagemaker-test-plan.md)

---

## Current State Summary

### Plans Documented (`_agent_docs/plans/`)
1. **`2026-06-30-collagemaker-web-port-implementation.md`** — The master 4-phase implementation plan covering the complete web port concept (Foundation & Core Rendering, Panel Editing & Crop Controls, Styling/Backgrounds/Title/Export, Polish & Advanced Features).
2. **`2026-07-01-collagemaker-test-plan.md`** — Comprehensive test plan (Sections 1-14) for Phases 1 & 2 only (explicitly labeled "Pre-Phase 3 Test Plan").
3. **`2026-07-02-agent-infrastructure-review.md`** — Agent infrastructure review.
4. **`2026-07-02-p0-test-followup.md`** — P0 test follow-up and bug fixes.

### Sessions Completed (`_agent_docs/project-timeline/sessions/`)
Sessions 1-9 have been completed, with recent work covering:
- Session 8: Fixed UndoManager batch bug, added E2E tests (reached 163 total tests: 147 unit + 16 E2E).
- Session 9: Integrated UndoManager with keyboard shortcuts (Cmd+Z / Cmd+Shift+Z), panel hover border rendering, toolbar undo/redo buttons, crop preview section in sidebar, and core crop interaction modules (`CropInteraction`, `GestureHandler`, `CropInfo`, `CropManager`, `SaliencyFallback`).

### Learnings Captured (`_agent_docs/learnings/`)
- `layout-math-porting.md`, `canvas-2d-mapping.md`, `vue-options-api-pattern.md`
- `undomanager-batch-bug.md`, `app-undo-history-scope.md`, `playwright-canvas-e2e.md`
- `mocha-chai-browser-tests.md`

---

## Gaps Identified

### Gap 1: No Test Plan for Phase 3 Features
The `2026-07-01-collagemaker-test-plan.md` explicitly states it's a "Pre-Phase 3 Test Plan" covering Phases 1 & 2 only. We are missing a **Phase 3 test plan** that covers:

| Feature Category | Missing Tests |
|------------------|---------------|
| **Background Rendering** | Solid/gradient/image backgrounds, color pickers, gradient angle slider, `BackgroundRenderer` unit tests |
| **Title Rendering with Per-Character Formatting** | `TitleRun` array mutations, segmented text rendering, bold/italic/underline toggles, alignment calculations, `TitleRenderer` unit tests |
| **Overlay/Mask Compositing** | All Canvas 2D `globalCompositeOperation` modes (multiply, screen, overlay, etc.), opacity control, `OverlayRenderer` unit tests |
| **Export Functionality** | Canvas toBlob JPEG generation, quality slider, download link creation, `ExportManager` unit tests |
| **Settings Persistence** | `localStorage` save/load for layout, gutter, background style, title font/size, export quality, theme, `SettingsPersistence` unit tests |

### Gap 2: No Phase 4 Implementation Plan Details
Phase 4 (Polish & Advanced Features) is documented in the master plan as "optional for MVP and can be deferred based on priorities," but includes important features that need prioritization decisions:

- **ML-based saliency analysis** — TF.js models (`@tensorflow-models/face-detection`, `@tensorflow-models/coco-ssd`), lazy loading, Web Worker inference
- **Saliency debug overlay toggle** — Green circle indicating focal region, red center dot
- **Responsive design** — Mobile breakpoints, stack sidebars below canvas on narrow screens, touch-friendly gesture handling
- **PWA capabilities** — `manifest.json`, `service-worker.js`, install prompt for desktop/mobile
- **Keyboard shortcuts** — Cmd+O (Add images), Cmd+S (Export), Cmd+1-5 (Switch layout styles), Escape (Deselect panel), Delete/Backspace (Remove selected image)
- **Landing page integration** — Add CollageMaker project card to the existing "Tools & Educational" category section on the site's landing page

### Gap 3: Missing Phase 3 Implementation Plan Document
While the master plan (`2026-06-30-collagemaker-web-port-implementation.md`) documents Phase 3 changes required (Sections 3.1-3.10), we don't have a dedicated **Phase 3 implementation plan** document similar to how Phases 1-2 were structured or documented for testing. This would include:

- Specific file creation/modification order for Phase 3 modules
- UI integration details for background/title/overlay/export panels in the right sidebar
- Export canvas lifecycle (offscreen 1920x1080 canvas creation/destruction)
- Title per-character formatting UI integration (contenteditable text area, B/I/U toggle buttons, font family select, font size slider, color pickers)

---

## Recommended Next Steps

### Step 1: Create Phase 3 Test Plan Document
Create `_agent_docs/plans/2026-07-02-collagemaker-phase3-test-plan.md` covering:
- `BackgroundRenderer` unit tests (solid/gradient/image)
- `TitleRenderer` unit tests (per-character formatting, alignment, `TitleRun` array mutations)
- `OverlayRenderer` unit tests (blend modes, opacity)
- `ExportManager` unit tests (`toBlob`, download link creation)
- `SettingsPersistence` unit tests (`localStorage` get/set)
- E2E tests for backgrounds, titles, overlays, export workflow

### Step 2: Create Phase 3 Implementation Plan Document
Create `_agent_docs/plans/2026-07-03-collagemaker-phase3-implementation.md` with:
- File creation order for Phase 3 modules (`BackgroundStyle.js`, `BackgroundManager.js`, `BackgroundRenderer.js`, `TitleStyle.js`, `TitleRun.js`, `TitleManager.js`, `TitleRenderer.js`, `OverlayRenderer.js`, `ExportManager.js`, `SettingsPersistence.js`)
- UI integration steps (background section, title section, overlay section, export section in right sidebar)
- Export canvas lifecycle details (full-resolution offscreen canvas 1920x1080 creation/destruction)

### Step 3: Implement Phase 3 Features
Execute the Phase 3 implementation following the master plan's sections 3.1-3.10:
1. **Background rendering + UI** (Sections 3.1-3.2) — Solid/gradient/image backgrounds, color pickers, gradient angle slider
2. **Title rendering with per-character formatting + UI** (Sections 3.3-3.4) — `TitleRun` segments, segmented text rendering, B/I/U toggle buttons, font family select, alignment
3. **Overlay/mask with blend modes** (Section 3.5) — All Canvas 2D `globalCompositeOperation` modes, opacity slider, file picker for mask image
4. **Export functionality** (Sections 3.6-3.7) — Canvas toBlob JPEG generation, quality slider, download link creation, progress indicator
5. **Settings persistence + enhancements** (Sections 3.8-3.10) — `localStorage` save/load, image reordering in sidebar, collapsible right sidebar

### Step 4: Decide on Phase 4 Priority
Determine which Phase 4 features are MVP vs deferred:

| Feature Category | Priority | Notes |
|------------------|----------|-------|
| **Keyboard shortcuts** (Cmd+Z, Cmd+S, Escape, Cmd+1-5) | Must-have | Already partially implemented (Cmd+Z/Cmd+Shift+Z), need to add Cmd+S, Escape, etc. |
| **Landing page integration** (CollageMaker project card) | Must-have | Follows established pattern for "Tools & Educational" category |
| **ML-based saliency analysis** | Nice-to-have / Deferred | Adds 9+ MB and complexity; center-weighted heuristic is sufficient for MVP |
| **Responsive design (mobile breakpoints)** | Nice-to-have / Deferred | Desktop-first approach is the current MVP target |
| **PWA capabilities** (manifest.json, service-worker.js) | Nice-to-have / Deferred | Not required for initial static site deployment |

---

## Do We Have All Steps Needed for the Whole Web Port Concept?

### Conceptually: Yes
The master implementation plan (`2026-06-30-collagemaker-web-port-implementation.md`) comprehensively outlines all 4 phases with:
- Architecture decisions (Vue 3 + Canvas 2D + ES Modules)
- File structure and module organization
- Rendering pipeline details
- State management approach
- Testing strategy (Mocha/Chai unit tests + Playwright E2E)

### Documentation-wise: Missing Key Artifacts
We are missing the following documentation artifacts to fully cover the web port concept:
1. **Phase 3 test plan document** — To ensure comprehensive validation of backgrounds, titles, overlays, export, and settings persistence before Phase 3 implementation begins.
2. **Phase 3 implementation plan document** — To provide a clear, step-by-step file creation and UI integration guide for the `build-code` agent to follow during Phase 3 execution.
3. **Phase 4 implementation decisions/document** — To clarify which Phase 4 features are MVP vs deferred, ensuring alignment before starting Phase 4 work.

Once these documentation gaps are filled, the project will have complete plan coverage from Phases 1 through 4, with test plans and implementation guides for each phase.
