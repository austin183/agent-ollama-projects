# Round 16 — Concurrency & Performance Modernization

## Source: `_agent_docs/change-requests/round-16.md`

### Change A: Fix `addImages(from:)` — Thread-safe image loading

**Problem:** `NSImage(data:)` and `nsImage.cgImage(forProposedRect:)` are AppKit calls
executed on a background thread inside `group.addTask`. The skill warns these can silently
fail off-main.

**Fix:**
- Use `FileManager.default.contents(at:)` for async-native file I/O
- Hop to `MainActor.run` for `NSImage` construction + `cgImage` extraction
- Offload `CGContext` thumbnail generation to `Task.detached`
- Make `group.addTask` an async closure

**File:** `CollageViewModel.swift:289-347`

### Change B: Debounce `persistence.save(self)` — 300ms

**Problem:** 13 `persistence.save(self)` calls fire synchronously on every slider drag,
color change, etc.

**Fix:**
- Add `private var saveDebounceTask: Task<Void, Never>?`
- Add `private func debouncedSave()` with 300ms `Task.sleep` + cancel-previous
- Replace all 13 `persistence.save(self)` calls with `debouncedSave()`
- Keep `undoManager.registerUndo` immediate (not debounced)
- Keep `regenerateLayout()`/`updatePreview()` in `didSet`

**Files:** `CollageViewModel.swift` — new property + method, 13 `didSet` edits

### Change C: Clean up `analyzeSaliency()` — Remove redundant `MainActor.run`

**Problem:** `SaliencyAnalyzer` is already an `actor`, so `await saliencyAnalyzer.analyzeAll(...)`
runs off MainActor. The `await MainActor.run { }` is redundant because `analyzeSaliency()`
is called from `Task { }` that inherits MainActor.

**Fix:** Remove the `await MainActor.run { }` wrapper — state updates after `analyzeAll`
already execute on MainActor.

**File:** `CollageViewModel.swift:537-566`

### Change D: Replace `DispatchWorkItem` in `applyPanLive()`

**Problem:** `DispatchWorkItem` + `DispatchQueue.main.asyncAfter` for debounce.

**Fix:**
- Replace `private var previewDebounce: DispatchWorkItem?` with
  `private var previewDebounceTask: Task<Void, Never>?`
- Replace debounce logic with `Task.sleep(nanoseconds: 150_000_000)` + cancel-previous

**File:** `CollageViewModel.swift:584-593, 709`

---

## Implementation Order

1. **D** (DispatchWorkItem) — simplest, establishes the `Task.sleep` pattern
2. **A** (addImages) — standalone, no interaction with other changes
3. **C** (analyzeSaliency) — small cleanup
4. **B** (debounced persistence) — touches most `didSet` blocks, do last

## Risks

- **Debounced persistence:** If app crashes within 300ms of last change, that change is lost.
  Acceptable tradeoff for slider interactions.
- **`addImages` restructuring:** Need to verify `group.addTask` with async closure compiles
  on the project's Swift toolchain.
- **`analyzeSaliency`:** Need to confirm the `Task { }` caller inherits MainActor.
