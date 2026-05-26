# Session 54 — 2026-05-26

### Round 16 — Concurrency & Performance Modernization + Panel Selection Staleness Fix

**Goal:** Implement Round 16 concurrency plan (4 changes) and fix intermittent panel selection / outline not appearing after layout regeneration.

**Source:** `_agent_docs/plans/round-16-concurrency-modernization.md`

---

## Change D: Replace `DispatchWorkItem` in `applyPanLive()`

**Problem:** `DispatchWorkItem` + `DispatchQueue.main.asyncAfter` used for 150ms debounce in live pan preview.

**Fix:** Replaced with `Task.sleep(nanoseconds: 150_000_000)` + cancel-previous pattern.

**Files changed:**
- `CollageViewModel.swift` — `previewDebounce: DispatchWorkItem?` → `previewDebounceTask: Task<Void, Never>?`; `applyPanLive()` rewritten

---

## Change A: Thread-safe image loading in `addImages(from:)`

**Problem:** `NSImage(data:)` and `nsImage.cgImage(forProposedRect:)` are AppKit calls executed on background thread inside `group.addTask` — can silently fail off-main.

**Fix:**
- File I/O: `Data(contentsOf:)` → `FileManager.default.contents(atPath:)` (non-throwing, async-native)
- AppKit calls: `NSImage(data:)` + `cgImage` extraction wrapped in `MainActor.run { }`
- `CGContext` thumbnail generation remains on background thread (safe — only CoreGraphics)

**Files changed:**
- `CollageViewModel.swift` — `addImages(from:)` restructured

---

## Change C: Clean up `analyzeSaliency()` — Remove redundant `MainActor.run`

**Problem:** `await MainActor.run { }` wrapper around state updates after `analyzeAll` is redundant — `analyzeSaliency()` is a method on `@MainActor CollageViewModel`, so execution automatically resumes on MainActor after `await`.

**Fix:** Removed both `await MainActor.run { }` wrappers (success and error paths).

**Files changed:**
- `CollageViewModel.swift` — `analyzeSaliency()` simplified

---

## Change B: Debounce `persistence.save(self)` — 300ms

**Problem:** 13 `persistence.save(self)` calls fire synchronously on every slider drag, color change, etc.

**Fix:**
- Added `saveDebounceTask: Task<Void, Never>?` property
- Added `debouncedSave()` method with 300ms `Task.sleep` + cancel-previous pattern
- Replaced all 13 `persistence.save(self)` calls in `didSet` observers with `debouncedSave()`
- `undoManager.registerUndo` remains immediate (not debounced)
- `regenerateLayout()` / `updatePreview()` remain in `didSet` (not debounced)

**Files changed:**
- `CollageViewModel.swift` — new property + method, 13 `didSet` edits

---

## Panel Selection Staleness Fix

**Problem:** After `regenerateLayout()` (e.g., adding images, switching layout), tapping a panel would not select it and the panel outline would not appear. Switching layout would make it work. Root cause: `scaledPanelFrames` and `scaledTitleFrame` were cached in `@State` and updated via `.onChange`. When `regenerateLayout()` created new panels with fresh UUIDs, there was a render gap where:
- `panelAt()` looked up new UUIDs in old `scaledPanelFrames` → `nil`
- Selected panel outline lookup `scaledPanelFrames[selectedId]` → `nil`
- `PanelHitArea` views skipped rendering (`if let scaledFrame = scaledPanelFrames[panel.id]` → `nil`)

**Fix:** Replaced `@State` caching with on-the-fly computed `let` bindings inside the `GeometryReader`:
- `let panelFrames` — computed fresh from `viewModel.panels` every render
- `let titleFrame` — computed fresh from `titleCanvasFrame` every render
- All gesture handlers (tap, drag, title drag) now use fresh frames
- Removed `@State var scaledPanelFrames`, `@State var scaledTitleFrame`, `LayoutKey` struct, and `.onChange` block

**Files changed:**
- `CollageEditorView.swift` — removed 2 `@State` properties, `LayoutKey` struct, `.onChange`; added `let panelFrames` / `let titleFrame` in GeometryReader; updated all references

---

**Build and Test Status:**
- **Build:** Succeeded — zero errors
- **Tests:** All 150 unit tests passing, 0 failures

---

**Session Status:** Complete — Round 16 plan (4 changes) implemented, panel selection staleness bug fixed, all changes verified.
