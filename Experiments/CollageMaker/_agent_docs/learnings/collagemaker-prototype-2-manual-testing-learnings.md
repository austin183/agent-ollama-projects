# CollageMaker Prototype 2 — Manual Testing & Telemetry Learnings

**Date:** 2026-05-10
**Purpose:** Document learnings from Phase 7 manual testing, telemetry instrumentation, and bug fixes.

## What Worked

- **OSLog telemetry pattern** — One `Logger(subsystem:category:)` per feature area gave clean filtering via `log stream --predicate 'subsystem == "austin183.indie.CollageMaker"'`. Categories (`App`, `ViewModel`, `Sidebar`, `Import`, `Editor`, `Analysis`, `Export`) made it easy to isolate events.
- **Minimal logging approach** — One log line per user action (add images, change layout, select panel, export) provided enough signal without noise.
- **`log stream` for live monitoring** — Reliable for catching live OSLog entries during manual testing.

## What Didn't Work / Gaps

- **`ImagePickerView` never wired in** — The view was built with full drag-and-drop support but `ContentView` used its own sidebar `Form`. Lesson: wire views into the hierarchy before building them, or verify integration immediately.
- **`.onDrop(of:)` UTI mismatch with Finder** — Filtering for `public.jpeg`/`public.png` doesn't match Finder drag payloads, which send `public.file-url`. Must accept `UTType.fileURL.identifier` and validate the file extension after extraction.
- **`NSItemProvider` item types vary** — File URL payloads can be `Data` (UTF-8 string) or `NSURL`. Must handle both in `loadItem(forTypeIdentifier:)`.
- **Picker binding bypasses action methods** — `$viewModel.layoutStyle` directly mutates the `@Published` property, skipping `setLayoutStyle(_)` which calls `regenerateLayout()`. Fix: keep the binding for UI, add `.onChange(of:)` to call the action method.
- **`log show` misses recent OSLog entries** — `log show --predicate 'subsystem == ...'` showed no entries even though `log stream` captured them live. `log show` has flush delay; use `log stream` for live debugging.

## What Was Confusing

- **`log stream` vs `log show` behavior** — `log stream` captures entries in real-time; `log show` queries the persistent store which may lag. For macOS app debugging, prefer `log stream` during active testing.
- **SwiftUI capture semantics with `Logger`** — `logger.info("\(images.count)")` inside an `@MainActor` class required `self.images.count` to avoid "reference to property in closure requires explicit use of self" errors.

## Skill Improvements

### `building-swiftui-macos-apps` skill
- Add a section on macOS drag-and-drop: accept `UTType.fileURL.identifier` for Finder drags, handle `Data` and `NSURL` payloads from `NSItemProvider`, validate extensions after extraction.
- Add a note about `.onDrop(of:)` UTI filtering: Finder sends `public.file-url`, not the content type of the file.

### `macos-telemetry` skill
- Document `log stream` vs `log show` behavior: prefer `log stream` for live monitoring, `log show` has flush delay.
- Add `self.` capture semantics note for `Logger` calls inside `@MainActor` classes.

### `swiftui-patterns` skill
- Add a pattern for Picker + action method: bind to `@Published` for UI, add `.onChange(of:)` to call the action method that triggers side effects.

## Next Steps

- Continue manual testing: verify pinch/pan gestures, saliency analysis, export flow, hero/mosaic layouts
- Test edge cases: single image, many images, very large images, missing crops
- Verify export produces valid JPEG with correct title and background color

---
**Status:** Closed
**Follow-up:** Continue Phase 7 manual testing with telemetry monitoring
