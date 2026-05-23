# Session 28 — 2026-05-19

### Phase 1: Undo & Redo Foundation

**Goal:** Implement Phase 1 of the HIG Review Phased Implementation Plan — add undo/redo support for all destructive and reversible actions via Edit menu + Cmd+Z, plus export state tracking and default export folder persistence.

**Plan Reference:** `_agent_docs/plans/2026-05-19-hig-review-phased.md` (Phase 1 of 4)

**Changes Implemented:**

1. **UndoManager integration** — Added `private let undoManager = UndoManager()` to `CollageViewModel`. Uses modern `UndoManager` type (renamed from `NSUndoManager` in Swift 3+).

2. **Property-level undo (11 properties)** — Registered undo in `didSet` for all configurable properties before mutation:
   - `layoutStyle` → "Change Layout"
   - `titleAttrString` → "Edit Title"
   - `titleStyle` → "Change Title Style"
   - `gutter` → "Change Gutter"
   - `backgroundColor` → "Change Background Color"
   - `exportQuality` → "Change Export Quality"
   - `backgroundStyle` → "Change Background Style"
   - `gradientStartColor` → "Change Gradient Start Color"
   - `gradientEndColor` → "Change Gradient End Color"
   - `gradientAngle` → "Change Gradient Angle"
   - `backgroundOpacity` → "Change Background Opacity"

3. **Method-level undo (5 methods):**
   - `removeImage(at:)` — captures removed image, restores via `insert(at:)` + `regenerateLayout()`
   - `moveImages(from:to:)` — captures `customImageOrder` before move, restores on undo
   - `swapPanelImages(sourceId:targetId:)` — captures `customImageOrder` before swap
   - `resetCrop(panelId:)` — captures old `CropInfo`, restores crop map entry
   - `clearAll()` — captures `images`, `panels`, `cropMap`, `customImageOrder`; added early return guard for empty state

4. **Export state tracking:**
   - `isExporting: Bool` — tracks export-in-progress for UI progress indicators
   - `exportSuccessMessage: String?` — holds "Saved to \<filename\>" message post-export
   - `defaultExportFolder` persistence — save panel remembers last-used directory across launches via `UserDefaults`

5. **URL extension** — `folderExists` computed property for validating saved folder path

**Files Modified:**
- `ViewModel/CollageViewModel.swift` — All Phase 1 changes contained in this single file per the plan

**Build Issues Encountered and Resolved:**
- `NSUndoManager` → renamed to `UndoManager` in Swift 3+; SDK 26.5 errors on the old name
- `NSSavePanel.isEntireDirectoryVisible` → no longer a member on SDK 26.5; removed (not needed for `directoryURL` to work)
- Test target has pre-existing build failures in `CollageAssemblerTests.swift` (mock protocol uses `title: String` instead of `titleAttrString: NSAttributedString`) — unrelated to these changes

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero warnings
- Tests: **Pre-existing failures** in `CollageAssemblerTests.swift` (unrelated mock protocol mismatch)
- Undo/redo: **Implemented** for all 11 properties + 5 mutating methods
- Export folder persistence: **Implemented**
- Export state tracking: **Implemented** (`isExporting`, `exportSuccessMessage`)
