# Testing Async ViewModels and Coordinate Math — Learnings

**Date:** 2026-05-17
**Context:** Fixing 7 failing tests from SOLID Review Testing & Quality Gap Plan (Session 24)

---

## Testing `Task.detached` in ViewModel Tests

`CollageViewModel.updatePreview()` runs `assembler.assemblePreviewWithCGImages` inside a `Task.detached` block. The detached task executes on a background thread and the test process exits its synchronous assertions before the task completes, so mock tracking fields are still at their initial zero values.

**Fix:** Add `try? await Task.sleep(nanoseconds: 50_000_000)` (50ms) before assertions. This is sufficient because the mock assembler returns immediately — the sleep only needs to yield control so the detached task can run.

**Anti-pattern:** Calling `regenerateLayout()` then immediately asserting on assembler state. `regenerateLayout()` calls `updatePreview()`, which fires off the detached task and returns. Any assertion on `trackingAssembler.*` fields must await completion.

**Better alternative (for future):** Have `updatePreview()` return a `Task<Void, Never>` and have tests `await` it, or add a `previewCompletion: CheckedContinuation?` pattern. The sleep approach works for our mock but would be unreliable with real CoreGraphics rendering.

## Mock Method Symmetry

When the `CollageAssembly` protocol has multiple methods (`assembleWithCGImages` for export, `assemblePreviewWithCGImages` for preview), the `TrackingAssembler` mock must track fields on **every method the ViewModel actually calls**. `updatePreview()` calls `assemblePreviewWithCGImages`, but the original mock only populated `lastAssemblePanels` and `lastAssembleTitle` in `assembleWithCGImages`. Tests asserting those fields were checking the wrong method's tracking data.

**Fix:** Added `lastPreviewPanels` and `lastPreviewTitle` to `assemblePreviewWithCGImages`. Rule of thumb: if a test calls ViewModel method X, and X delegates to protocol method Y, the mock must track on Y, not on sibling method Z.

## Aspect Ratio Math in Coordinate Tests

When writing tests for `sourceRectInContainer` (which implements `.aspectRatio(contentMode: .fit)` math), the expected values depend entirely on the relative aspect ratios of image and container:

- **Image wider than container** (landscape image, square container): constrains by width, letterboxes top/bottom
- **Image taller than container** (portrait image, square container): constrains by height, letterboxes left/right
- **Image square, container widescreen** (200x200 in 800x600): constrains by height (600), fitted = 600x600, offset = (100, 0)

Test #6 had a 200x200 image in an 800x600 container but expected `(0, 100, 800, 400)` — the widescreen result. The correct result is `(100, 0, 600, 600)` — letterboxed horizontally.

**Rule:** Always compute the fitted dimensions first, then the offset, then the mapped rect. Never assume which axis constrains.

## Scale Factor Verification

For `sourceRectInContainer` with matching aspect ratios (200x200 image in 800x800 container = 4x scale), crop coordinates multiply directly by the scale factor. Crop `(50, 50, 20, 20)` → `(200, 200, 80, 80)`. Test #7 expected `(400, 400)` which is the center of the container, not the scaled crop origin.

**Rule:** When image and container share the same aspect ratio, `scaleX = containerW / imageW` and `scaleY = containerH / imageH` should be equal. Use this as a sanity check in tests.

## Race Condition Checklist for ViewModel Tests

When a ViewModel method uses `Task.detached`:

1. Does the test assert on state set inside the detached task? → Add await
2. Does the test assert on state set synchronously before the task? → No await needed
3. Does the mock track the method the ViewModel actually calls? → Verify method name match

---

**Status:** Closed
**Follow-up:** Consider adding a `PreviewTracker` protocol with a completion closure for more reliable async testing
