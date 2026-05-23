# Session 14 — 2026-05-14

### Round 3, Phase 2: Title Drag-to-Position on Canvas

**Goal:** Implement Phase 2 of the round-3 plan: free-form title positioning via canvas drag gesture.

**Files Modified:**
- `Models/TitleStyle.swift` — Added `positionX`, `positionY: CGFloat` (normalized 0–1, top-left origin). Default `(0.5, 0.88)` — center, near bottom. Updated `CodingKeys`, `encode()`, and `init(from:)` with backward-compatible `decodeIfPresent`.
- `ViewModel/CollageViewModel.swift` — Added `isDraggingTitle: Bool = false` property for canvas state tracking.
- `Services/CollageAssembler.swift` — `drawTitle()` now uses `positionX/Y` to compute the anchor point instead of hardcoded bottom-center. Alignment offsets apply relative to the anchor (left = anchor is left edge, center = anchor is center, right = anchor is right edge).
- `Views/CollageEditorView.swift` — Added `titleCanvasFrame` computed property that estimates the title's bounding box from font/title/position. Added orange stroke overlay on the title region as a visual drag handle. Added `DragGesture(minimumDistance: 5)` at the ZStack level that locks to the title on `startLocation` hit-test, then updates `positionX/Y` live during `onChanged`. `LayoutKey` now includes title frame dimensions so `onChange` fires when position changes. Added `import AppKit` for `NSFont`.

**Build Issues Encountered and Resolved:**
1. **Title overlay appeared above text** — Initial `titleCanvasFrame` computed the rect's origin at the text top in CG coordinates, but `canvasToPreviewFrame`'s Y-flip placed the overlay above the actual rendered text. Fixed by computing the origin at the text baseline (`anchorYcg - boundingBox.height`), matching `drawTitle()`'s `y` coordinate.
2. **`DragGesture` coordinate conversion** — Converting preview coords to normalized canvas position required computing fitted canvas size, subtracting centering offset, scaling to canvas dimensions, and flipping Y. The formula reuses the same `.aspectRatio(contentMode: .fit)` math as `canvasToPreviewFrame`.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **68 tests pass** (unchanged)
- Title position model: **Working** (normalized 0–1, persisted to UserDefaults)
- Title rendering: **Working** (position-aware, alignment-relative anchor)
- Title drag gesture: **Working** (live preview, hit-test locking, `minimumDistance` threshold)
- Title overlay: **Working** (orange stroke, tracks position changes)

**Learnings Documented:**
- `_agent_docs/learnings/title-drag-position-learnings.md`
