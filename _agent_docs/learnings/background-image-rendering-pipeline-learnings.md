# Background Image Rendering Pipeline — Learnings

**Date:** 2026-05-14
**Session:** 12
**Purpose:** Document learnings from debugging background image not appearing, gradient not covering canvas, and gradient controls not updating live in CollageMaker.

---

## What Worked

- **Targeted telemetry with `Logger`** — Adding a few high-signal log lines at key pipeline stages (file load, CGImage extraction, style branch, draw call) identified the root cause in one run. The `opacity=0.000000` log line immediately revealed the invisible image was a defaults initialization problem, not a rendering problem.
- **`CGImage` extraction on main thread** — Extracting `CGImage` from `NSImage` on the main actor before passing to `Task.detached` is the correct pattern. `NSImage` is an AppKit class with main-thread requirements; calling `cgImage(forProposedRect:)` on a background thread can silently return `nil`.
- **True diagonal for gradient coverage** — Using `sqrt(w*w + h*h) / 2` for the gradient line half-length ensures the gradient extends to all four corners at any angle, regardless of canvas aspect ratio.
- **`didSet` as the single source of side effects** — Adding `updatePreview()` to every property's `didSet` that affects the preview eliminates the need for `.onChange` in views. The ViewModel owns the preview trigger logic.

## What Didn't Work / Gaps

- **`UserDefaults.double(forKey:)` returns `0.0` for missing keys** — Unlike `UserDefaults.string(forKey:)` which returns `nil`, the typed getters return the type's zero value. This meant `backgroundOpacity` silently initialized to `0`, making the background image completely invisible. The fix pattern:
  ```swift
  var backgroundOpacity: Double = {
      if UserDefaults.standard.object(forKey: key) != nil {
          return UserDefaults.standard.double(forKey: key)
      }
      return 1.0  // intentional default
  }() {
      didSet { /* persist */ }
  }
  ```
  This same pattern was already used for `scrollSensitivity` and `heroIndex` in the codebase, but wasn't applied to `backgroundOpacity` when it was added.

- **`NSImage` across thread boundaries** — The `Task.detached` preview pipeline captures all state as local `let` constants before dispatching. While `NSImage` is a reference type and the reference survives the capture, calling `cgImage(forProposedRect:)` on it inside the detached task runs on a background thread. AppKit objects aren't thread-safe — the call can return `nil` without crashing. The fix is to extract `CGImage` on the main thread before the detached task.

- **Gradient line length formula was wrong** — Using `min(w, h) / 2` as the half-length from center produces a line that's only as long as the smaller dimension's radius. For 1920x1080, this gives 540 in each direction (1080 total), which doesn't reach the corners (diagonal is 2203). The gradient appeared centered and only covered the middle portion of the canvas.

- **Missing `updatePreview()` calls were subtle** — The gradient angle slider moved, colors changed in the color well, and opacity slider updated — all locally. But the preview never refreshed because these properties' `didSet` only persisted to `UserDefaults`. The preview only updated when another property that DID call `updatePreview()` changed (e.g., switching layout style or removing an image).

## Key Patterns

### UserDefaults Typed Getter Defaults

| Method | Missing Key Returns | Safe Default Pattern |
|---|---|---|
| `string(forKey:)` | `nil` | Safe — use `?? default` |
| `double(forKey:)` | `0.0` | **Unsafe** — check `object(forKey:)` first |
| `integer(forKey:)` | `0` | **Unsafe** — check `object(forKey:)` first |
| `bool(forKey:)` | `false` | **Unsafe** — check `object(forKey:)` first |
| `data(forKey:)` | `nil` | Safe — use `?? default` |

### AppKit Objects Across Thread Boundaries

| Type | Thread-Safe? | Safe to Capture in `Task.detached`? |
|---|---|---|
| `NSImage` | No (AppKit) | Reference survives, but **don't call methods** on background thread |
| `NSColor` | No (AppKit) | Reference survives, but **don't call methods** on background thread |
| `CGImage` | Yes (CoreGraphics) | Fully safe — value type, no thread affinity |
| `NSBitmapImageRep` | No (AppKit) | Don't use on background thread |

**Rule:** Extract `CGImage` from `NSImage` and `CGColor` from `NSColor` on the main thread before passing to `Task.detached`.

### Preview Update Trigger Audit

Every property that affects the rendered preview should call `updatePreview()` in its `didSet`:

| Property | Affects Preview? | Calls `updatePreview()`? |
|---|---|---|
| `backgroundColor` | Yes | Yes |
| `backgroundStyle` | Yes | Yes (fixed Session 12) |
| `backgroundImage` | Yes | No — caller triggers (correct: image is optional, caller knows when it changed) |
| `backgroundOpacity` | Yes | Yes (fixed Session 12) |
| `gradientStartColor` | Yes | Yes (fixed Session 12) |
| `gradientEndColor` | Yes | Yes (fixed Session 12) |
| `gradientAngle` | Yes | Yes (fixed Session 12) |
| `title` | Yes | Yes (fixed Session 12) |
| `gutter` | Yes | Yes (via `regenerateLayout()`) |
| `layoutStyle` | Yes | Yes (via `regenerateLayout()`) |
| `heroIndex` | Yes | Yes (via `regenerateLayout()`) |

## Diagnostic Approach

When a visual element "doesn't appear" but the code path looks correct:

1. **Add logging at pipeline boundaries** — File load, CGImage extraction, style branch selection, draw call
2. **Log the actual values** — Not just "non-nil/nil" but dimensions, opacity, colors
3. **Check defaults initialization** — Typed UserDefaults getters return zero values for missing keys
4. **Check thread affinity** — AppKit objects accessed on background threads may silently fail

## Next Steps

- Consider a linter rule or code review checklist: "Does every property that affects the preview call `updatePreview()` in its `didSet`?"
- Consider adding a `@precondition` or debug assertion in `drawImageBackground` when `opacity == 0` to catch this class of bug earlier

---
**Status:** Closed
**Follow-up:** None — all round-1 image update bugs resolved
