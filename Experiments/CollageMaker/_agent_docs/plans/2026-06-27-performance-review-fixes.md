# Performance Review Fixes — Final Plan

**Source**: `_agent_docs/reviews/2026-06-27-performance-review.md`
**Date**: 2026-06-27
**Synthesis**: Gerald's phased plan (foundation) + Matthew's profiling & mask caching additions

---

## Phase 1 — Retain Cycle Fix (Critical)

**Issue**: `ImageCoordinator.target` is a strong, implicitly-unwrapped optional reference to `CollageViewModel`, which strongly owns `imageCoordinator`. This creates a retain cycle.

**Impact**: Memory leak. Bounded in current single-window app, but would be critical with multi-document support.

### Changes

1. **`ImageCoordinator.swift:34`** — Change `var target: ImageCoordinationTarget!` to `weak var target: (any ImageCoordinationTarget)?`
2. **All `target.` callsites in `ImageCoordinator.swift`** — Change from force-unsafe (`target.method()`) to optional chaining (`target?.method()`)

### Affected Call Sites in ImageCoordinator
- Line 87: `!target.isProcessing` → `target?.isProcessing != false` (or guard-let)
- Line 125: `target.resetCrop(...)` → `target?.resetCrop(...)`
- Line 126: `target.updatePanelPreview(...)` → `target?.updatePanelPreview(...)`
- Line 141: `target.selectedPanelId = ...` → `target?.selectedPanelId = ...`
- Line 169-170: `target.updatePanelPreview(...)` ×2 → optional chain
- Line 179: `target.beginProcessing()` → `target?.beginProcessing()`
- Line 180: `target.endProcessing()` → `target?.endProcessing()`
- Line 200-202: `target.cancelDebouncer(...)`, `target.updatePreview()`, `target.updateAllPanelPreviews()` → optional chain
- Line 205: `target.errorMessage = ...` → `target?.errorMessage = ...`

### Verification
- Run `bash script/run_tests.sh` — confirm all tests pass
- Run `bash script/build_and_run.sh --verify` — confirm app launches
- No behavioral change expected; the weak reference is valid for the lifetime of the VM

---

## Phase 2 — O(1) Panel Lookups (High Value)

**Issue**: Multiple `panels.first(where: { $0.id == panelId })` and `panels.firstIndex(where: { $0.id == panelId })` calls fire on every gesture frame.

**Impact**: CPU waste and potential gesture stutter. With typical panel counts (2–20), per-call cost is small, but cumulative cost across rapid gesture frames is measurable.

### Changes

1. **`LayoutManager`** — Add a `panelById: [UUID: ImagePanel]` stored property as a cached dict, rebuilt in `regenerateLayout()` and `reset()`
2. **Replace O(N) call sites:**
   - `CollageViewModel.swift:888` — `panels.first(where: { $0.id == panelId })` in `updatePanelPreview`
   - `ImageCoordinator.swift:132` — `layoutManager.panels.firstIndex(where: { $0.id == panelId })` in `getEffectiveImageIndex`
   - `ImageCoordinator.swift:138` — `layoutManager.panels.first(where: { ... })` in `selectPanelForImage`
   - `ImageCoordinator.swift:147-148` — Two `firstIndex(where:)` calls in `swapPanelImages`

### Verification
- Run `bash script/run_tests.sh`
- No behavioral change — purely a lookup optimization
- Manually verify gesture responsiveness (pan/pinch/crop overlay gestures with many panels)

---

## Phase 3 — CGImage Extraction Caching (Low Priority)

**Issue**: `backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)` and mask image CG images are called repeatedly in `updatePreview()`, `exportCollage()`, and `BackgroundManager.updateBackground()`.

**Impact**: Minor CPU waste. The extraction is fast for images already resident in memory. Caching adds invalidation complexity.

### Changes

1. **`BackgroundManager`** — Add a cached `cachedCGImage: CGImage?` property with a version tracker (e.g., `backgroundImageVersion: Int`)
2. Expose a method `getCachedCGImage() -> CGImage?` that returns the cached CGImage if the version hasn't changed, or recomputes and caches if the underlying `backgroundImage` changed
3. Increment version whenever `backgroundImage` is set
4. Replace the three call sites in `CollageViewModel.swift` (lines 925, 1071) and `BackgroundManager.swift` (line 37)
5. **`LayoutManager`** — Add similar caching for extracted mask image CG images, ensuring caches are invalidated only when the source `NSImage` or relevant properties change

### Defer If
- Benchmarking shows the extraction cost is negligible relative to the overall compositing time
- The added complexity of cache invalidation is not worth the marginal gain

### Verification
- Run `bash script/run_tests.sh`
- No behavioral change expected
- Set large background image, export collage, verify no visual artifacts

---

## Phase 4: Performance Profiling & GPU Evaluation

**Goal**: Determine if CoreGraphics is a bottleneck for complex layouts before speculating on GPU offloading.

### Steps
1. Use Instruments (Time Profiler, Metal System Trace) to measure CPU/GPU usage during layout regeneration and preview updates.
2. If CPU bottlenecks are found in `PanelRenderer` or `OverlayRenderer`, explore offloading specific masking/compositing operations to CoreImage or Metal.

### Note on GPU Offloading
- CoreGraphics is already hardware-accelerated on macOS. Vision-based saliency analysis is optimized via Metal under the hood.
- Defer GPU offloading / Metal shaders unless profiling identifies specific rendering paths as CPU-bound bottlenecks with many panels or complex layouts (e.g., hexagonal tiling, diagonal slices).

---

## Execution Order

1. Phase 1 first — it's a bug fix with clear correctness impact
2. Phase 2 after — performance optimization with measurable UX benefit
3. Phase 3 last — only if time/budget allows, given low impact and added complexity
4. Phase 4 as needed — validate bottlenecks with Instruments before any GPU offloading work
