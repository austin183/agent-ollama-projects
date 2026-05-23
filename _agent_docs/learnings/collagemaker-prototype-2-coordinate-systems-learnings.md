# CollageMaker Prototype 2 — Coordinate Systems & Performance Learnings

**Date:** 2026-05-11
**Purpose:** Document learnings from Session 5: fixing vertical panel inversion, hit area misalignment, and main-thread performance issues.

## What Worked

- **OSLog telemetry for debugging** — The existing `Editor` category logs (`Selected panel idx=...`, `Highlight: panel ...`, `canvasToPreview: ...`) were instrumental in diagnosing the coordinate mismatch. The `scaled=(-356,206)` value immediately revealed the fitted size was wrong.
- **`@Observable` + `Task.detached` pattern** — Moving heavy CoreGraphics work off the main thread using `Task.detached` with captured values (to avoid `@MainActor` isolation errors) then dispatching results back with `Task { @MainActor in self?.previewImage = result }` gave responsive UI without blocking.
- **CGImage caching in model** — Storing `CGImage` directly in `ImageItem` at load time eliminated repeated `nsImage.cgImage(forProposedRect:)` extraction on every preview update. Simple change, measurable performance improvement.

## What Didn't Work / Gaps

- **`CGContext` Y-flip in bitmap context** — The initial fix added `ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)` to the bitmap context to "fix" the bottom-left vs top-left origin mismatch. This flipped the **rendered images** upside down because `NSImage(cgImage:)` + SwiftUI's `Image(nsImage:)` already handles the coordinate conversion correctly. The CGContext should NOT be flipped for `NSBitmapImageRep` rendering.

- **`canvasToPreviewFrame` fitted size calculation inverted** — The original code computed `fittedSize` as if scaling the canvas **up** to fill the preview (e.g., 1458x821 from 1920x1080 when preview is 746x821). The correct approach is to compute how the canvas fits **inside** the preview, matching SwiftUI's `.aspectRatio(contentMode: .fit)` behavior. The formula must be: if canvas aspect > preview aspect, constrain by preview width (`fittedWidth = previewWidth, fittedHeight = previewWidth / canvasAspect`); otherwise constrain by preview height.

- **`Task.detached` with `@MainActor` class property access** — `self.images.map { $0.cgImage }` inside a `Task.detached` closure on an `@MainActor` class requires either `await` (making the whole closure `async`) or capturing values before the detached task. The correct pattern is to capture all needed values as local `let` constants before `Task.detached`, then use those in the closure.

- **`NSImage(cgImage:size:)` size parameter** — The `assemblePreviewWithCGImages` method passes `previewSize` to `NSImage(cgImage:finalImage, size:previewSize)`, but `previewSize` (960x540) is just a display hint, not the actual canvas size (1920x1080). The `NSImage` contains the full-resolution bitmap but displays at the hint size. This means `canvasToPreviewFrame` must scale from the **actual canvas** (1920x1080) to the **SwiftUI geometry size**, not to the `previewSize` hint.

## What Was Confusing

- **Coordinate system layers in macOS imaging** — There are at least 4 coordinate systems interacting:
  1. **CoreGraphics/CGContext**: bottom-left origin, y increases upward
  2. **NSBitmapImageRep**: stores pixels with top-left origin (row 0 = top)
  3. **NSImage**: wraps the bitmap, `Image(nsImage:)` in SwiftUI displays with top-left origin
  4. **SwiftUI GeometryReader**: top-left origin, y increases downward

  The CGContext's bottom-left origin is "corrected" automatically when creating `NSBitmapImageRep` → `NSImage` → SwiftUI `Image`. The developer should NOT manually flip the CGContext. Instead, coordinate conversions between canvas frames (which use CoreGraphics-style y=0 at bottom) and SwiftUI hit areas (y=0 at top) must flip Y explicitly.

- **`NSImage(cgImage:size:)` size parameter behavior** — The `size` parameter is a "display size hint" for AppKit, not the actual pixel dimensions. The underlying bitmap retains its original resolution. SwiftUI's `Image(nsImage:)` ignores this hint and uses the bitmap's actual pixel dimensions, then scales via `.aspectRatio(contentMode: .fit)`. This means hit area calculations must use the **actual canvas resolution** (1920x1080), not the preview hint size (960x540).

## Skill Improvements

### `building-swiftui-macos-apps/SKILL.md` — Common Pitfalls

1. **Add "CGContext Y-flip with NSBitmapImageRep" pitfall** — Do NOT flip the CGContext Y-axis (`translateBy` + `scaleBy`) when rendering to `NSBitmapImageRep` that will be displayed via `NSImage` → SwiftUI `Image(nsImage:)`. The AppKit/SwiftUI bridge handles the bottom-left to top-left conversion automatically. Flipping the CGContext will render images upside down.

2. **Add "Canvas-to-UI coordinate conversion" pitfall** — When overlaying SwiftUI hit areas on top of a CoreGraphics-rendered image, the hit area coordinates must account for:
   - Y-axis inversion (CoreGraphics bottom-left vs SwiftUI top-left)
   - Aspect-ratio fitting (`.aspectRatio(contentMode: .fit)` scales down, not up)
   - The fitted size formula must match SwiftUI's `.fit` behavior: constrain by the smaller dimension ratio

3. **Add "NSImage display size hint vs actual resolution" pitfall** — `NSImage(cgImage:size:)` `size` parameter is a display hint, not the actual resolution. SwiftUI `Image(nsImage:)` uses the bitmap's actual pixel dimensions. Coordinate conversion must use the actual canvas resolution, not the hint size.

### `building-swiftui-macos-apps/SKILL.md` — Performance Patterns

4. **Add "Background preview rendering" pattern** — For apps that render images on the main thread:
   - Capture all `@MainActor`-isolated values as `let` constants before `Task.detached`
   - Pass captured values into the detached closure (not `self.property` access)
   - Use `Task { @MainActor in self?.result = computedValue }` to dispatch back
   - Cancel stale tasks before starting new ones (`previewTask?.cancel()`)

5. **Add "CGImage caching" pattern** — Extract `CGImage` from `NSImage` once at load time and store it in the model. Repeated `nsImage.cgImage(forProposedRect:)` calls are expensive and should be avoided in hot paths (preview updates, gesture callbacks).

## Next Steps

- Update `building-swiftui-macos-apps/SKILL.md` with new coordinate system pitfalls
- Continue manual testing: verify panel selection alignment, crop gestures, export quality
- Consider adding debug visualization (colored rectangles) to verify hit area alignment during development

---
**Status:** Closed
**Follow-up:** Update skill documentation, continue manual testing
