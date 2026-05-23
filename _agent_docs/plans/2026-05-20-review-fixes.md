# Review Fix Plan: 2026-05-19 Full Code Review

**Source:** `_agent_docs/reviews/2026-05-19-full-review.md`
**Date:** 2026-05-20
**Scope:** All issues — Critical, High, Medium, Low, Nits

---

## Decisions

| Decision | Choice |
|----------|--------|
| `backgroundImage` persistence | Persist path to `UserDefaults` |
| Mosaic layout randomness | Seed-based RNG — optional `seed: UInt64?` param |
| `exportCollage` NSSavePanel blocking | Document as unavoidable; no structural change |

---

## Phase 1 — Critical Issues

### Issue #1: CGImage extraction off-main-thread in SaliencyAnalyzer

`SaliencyAnalyzer` is an `actor`. Its `analyze` method calls `image.cgImage(forProposedRect:...)` on an actor-isolation thread. `NSImage` methods are AppKit and must run on the main actor.

**Fix:** Change the `SaliencyAnalysis` protocol to accept `CGImage` instead of `NSImage`. The caller (`CollageViewModel`) already has `cgImage` on each `ImageItem`, so extract on the main thread before passing to the analyzer.

**Files:**
- `Services/SaliencyAnalyzer.swift` — change protocol + implementation signatures to `CGImage`
- `ViewModel/CollageViewModel.swift` — pass `images.map { $0.cgImage }` to `analyzeSaliency`
- `CollageViewModelTests.swift` — update `MockSaliencyAnalyzer` signatures
- `SaliencyAnalyzerTests.swift` — update test calls

### Issue #2: `addImages` blocks main actor

`dispatchGroup.wait()` at `CollageViewModel.swift:313` blocks the calling thread. Since `addImages` is called from the main actor context, this freezes the UI during image loading.

**Fix:** Make `addImages(from:)` async. Replace `DispatchGroup` + `DispatchQueue.global` + `wait()` with `Task.detached` + `await`.

**Files:**
- `ViewModel/CollageViewModel.swift` — convert `addImages` to async
- `ViewModel/CollageViewModel.swift` — update `browseImages` callback to wrap in `Task { await addImages(...) }`

### Issue #10 (grouped with #2): `ContentView.handleDrop` uses legacy DispatchGroup

**Fix:** Modernize with `withThrowingTaskGroup` or `async let`. Convert `handleDrop` to async.

**Files:**
- `ContentView.swift` — replace `DispatchGroup` + `NSLock` with `withThrowingTaskGroup`

---

## Phase 2 — High Priority

### Issue #3: Extract scroll pan state from ViewModel

Scroll pan state (`scrollPanPanelId`, `scrollPanAccumulator`, `scrollCommitTimer`, `beginScrollPan`, `scrollPanDelta`, `endScrollPan`, `scheduleScrollCommit`, `commitScrollPan`) belongs in its own manager.

**Fix:** Create `ScrollPanManager`. Delegate all scroll pan calls from `CollageViewModel`.

**New file:**
- `Services/ScrollPanManager.swift` — encapsulates scroll pan state and logic

**Modified files:**
- `ViewModel/CollageViewModel.swift` — add `scrollPanManager` property, delegate all scroll pan methods (~45 lines removed)

### Issue #4: Parameter explosion in CollageAssembly protocol

Both `assemble` and `assemblePreview` accept 14-15 parameters. This is error-prone and hard to maintain.

**Fix:** Introduce `AssemblyConfig` struct to group all assembly parameters. Update protocol, implementation, and all callers.

**New file:**
- `Models/AssemblyConfig.swift`

**Modified files:**
- `Services/CollageAssembler.swift` — update protocol + implementation to use `AssemblyConfig`
- `ViewModel/CollageViewModel.swift` — construct `AssemblyConfig` in `updatePreview` and `exportCollage`
- `CollageViewModelTests.swift` — update `MockAssembler` signatures

---

## Phase 3 — Medium Priority

### Issue #5: Duplicated font measurement logic

The font construction pattern (default font + trait merging via `enumerateAttribute(.font)`, `withSymbolicTraits`, `NSFont(descriptor:size:)`) is duplicated across 4 locations:
- `CollageAssembler.drawTitle` (lines 391-420)
- `CollageEditorView.titleCanvasFrame` (lines 43-75)
- `CollageEditorView.titleMinWidth` (lines 97-128)
- `AttributedStringEditor.normalizeForEditor` (lines 5-37)

**Fix:** Extract to two shared utilities:
- `FontMerger` — merges symbolic traits from an existing font onto a base font at a target size
- `TitleMetrics` — measures title bounding rect and minimum natural width

**New files:**
- `Services/FontMerger.swift`
- `Services/TitleMetrics.swift`

**Modified files:**
- `Services/CollageAssembler.swift` — use `FontMerger` + `TitleMetrics`
- `Views/CollageEditorView.swift` — use `TitleMetrics` (~60 fewer lines)
- `Views/AttributedStringEditor.swift` — use `FontMerger`

### Issue #6: CropManager dual static/instance methods

Lines 232-251 are instance wrappers that simply delegate to `Self.method()`. These add no value.

**Fix:** Remove instance wrappers. Callers already use `CropManager.staticMethod()` or `CoordinateConverter` directly.

**Modified files:**
- `ViewModel/CropManager.swift` — remove lines 232-251 (~50 lines removed)

### Issue #7: `backgroundImage` not persisted

The `backgroundImage: NSImage?` property is never saved to `UserDefaults`. It will be lost on app restart.

**Fix:** Persist the background image file path to `UserDefaults`. Restore on init. Clear on `clearAll`.

**Modified files:**
- `ViewModel/CollageViewModel.swift` — add `UserDefaults` key, persist/restore path

### Issue #8: `buildMoveMapping` edge case tests

**Fix:** Add dedicated unit tests for:
- Move to start
- Move to end
- Single element
- Empty `customImageOrder`

**Modified files:**
- `CollageViewModelTests.swift`

---

## Phase 4 — Low Priority

### Issue #9: Mosaic layout non-deterministic

`LayoutGenerator.generateMosaic` uses `Float.random(in: 0..<1)` for split ratios. Layouts are non-reproducible.

**Fix:** Add optional `seed: UInt64?` parameter. When provided, use a seeded `RandomNumberGenerator`. When `nil`, fall back to default randomness.

**Modified files:**
- `Services/LayoutGenerator.swift`

### Issue #10 (already handled in Phase 1): `handleDrop` legacy DispatchGroup

### Issue #3 (review): `exportCollage` NSSavePanel blocking

`NSApplication.shared.runModal(for:)` blocks the main thread. This is unavoidable for `NSSavePanel`.

**Fix:** Add documentation comment explaining the blocking behavior is intentional and unavoidable.

**Modified files:**
- `ViewModel/CollageViewModel.swift`

### Issue #11 (review): SettingsView key mismatch + defaults not wired in

`SettingsView` stores `defaultTitle`, `defaultFontFamily`, `defaultFontSize` to `UserDefaults`, but `CollageViewModel` never reads them.

**Fix:** Wire defaults into `CollageViewModel` initialization as fallback values.

**Modified files:**
- `ViewModel/CollageViewModel.swift` — read `defaultTitle`, `defaultFontFamily`, `defaultFontSize` during init

---

## Phase 5 — Nits

### Issue #12: Redundant accessibility on menu items

`.accessibilityLabel` and `.accessibilityHint` on `Button` inside `Commands` are redundant — menu buttons derive accessibility from their labels.

**Modified files:**
- `Views/CollageCommands.swift` — remove redundant modifiers

### Issue #13: Global logging helper functions

`rectStr`, `pointStr`, `sizeStr` are global free functions. Namespace pollution.

**Fix:** Create `struct DebugHelpers` with static methods. Update callers.

**Modified files:**
- `Services/LoggingExtensions.swift` — wrap in `DebugHelpers` struct
- All callers (search for `rectStr(`, `pointStr(`, `sizeStr(`)

---

## Summary of New Files

| File | Purpose |
|------|---------|
| `Services/ScrollPanManager.swift` | Extracted scroll pan state/logic |
| `Models/AssemblyConfig.swift` | Grouped assembly parameters |
| `Services/FontMerger.swift` | Shared font trait merging utility |
| `Services/TitleMetrics.swift` | Shared title measurement logic |

## Expected Impact

| File | Before | After | Delta |
|------|--------|-------|-------|
| `CollageViewModel.swift` | 778 | ~450 | -328 |
| `CollageAssembler.swift` | 457 | ~430 | -27 |
| `CollageEditorView.swift` | 475 | ~410 | -65 |
| `CropManager.swift` | 343 | ~290 | -53 |
| `ContentView.swift` | 322 | ~300 | -22 |
| `LayoutGenerator.swift` | 177 | ~190 | +13 |
| `AttributedStringEditor.swift` | 356 | ~330 | -26 |
| `CollageCommands.swift` | 49 | ~43 | -6 |
| `LoggingExtensions.swift` | 14 | ~18 | +4 |

**Total net reduction: ~510 lines** (offset by ~170 lines in new files)

---

## Execution Order

1. **Phase 1** — Critical issues first (thread safety, main thread blocking)
2. **Phase 2** — High priority (SRP extraction, parameter grouping)
3. **Phase 3** — Medium (deduplication, cleanup, persistence, tests)
4. **Phase 4** — Low (determinism, documentation, defaults wiring)
5. **Phase 5** — Nits (accessibility, namespace cleanup)

After each phase, build and run existing tests to verify no regressions.
