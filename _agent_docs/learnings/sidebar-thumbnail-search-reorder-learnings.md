# Sidebar Thumbnail, Search & Reorder — Learnings

**Date:** 2026-05-12
**Purpose:** Document learnings from implementing sidebar thumbnails, search filtering, and native image reordering.

---

## What Worked

1. **`DispatchGroup` for synchronous thumbnail collection** — Using `DispatchQueue.global(qos: .userInitiated).async(group:)` + `dispatchGroup.wait()` collected all thumbnails on a background thread, then appended the full array at once on main. Clean, simple, no race conditions.

2. **`CGContext` with `noneSkipFirst` for thumbnails** — `CGImageAlphaInfo.noneSkipFirst` (32-bit BGRA, alpha skipped) worked reliably for 64x64 thumbnail generation. No need for `NSBitmapImageRep` in this case since we're not displaying the context directly through AppKit.

3. **`.onMove` on `Form` is native** — `Form` renders as `NSTableView` underneath, which supports `.onMove(perform:)` natively. No custom drag types, no `Transferable` API needed. Drag reorder works out of the box.

4. **`.searchable` on `Form`** — Adding `.searchable(text:prompt:)` to a `Form` gives a native search field at the top of the sidebar. No extra UI needed.

5. **Preserving original indices with filtered `ForEach`** — Using `enumerated().map { ($0.offset, $0.element) }` preserves original indices even when filtering. The `ForEach` iterates over the filtered list but uses `$0.offset` (original index) for hero selection and removal.

## What Didn't Work / Gaps

1. **`CGContext.makeImage()` before drawing returned empty image** — Calling `context.makeImage()` before `context.draw()` produced an empty image. The `makeImage()` call was unnecessary — just create the context, draw, then `makeImage()`.

2. **Stray closing brace from edit** — Multiple edits to `ContentView.swift` introduced a duplicate `}` that caused compile errors. Care needed when editing nested SwiftUI view blocks.

## What Was Confusing

1. **`CGImageAlphaInfo` choice** — `noneSkipFirst` vs `noneSkipLast` vs `premultipliedLast`. `noneSkipFirst` (BGRA) worked for thumbnail generation, but `premultipliedLast` (RGBA premultiplied) is more common for display. For thumbnails that will be displayed via `NSImage(cgImage:)`, either works.

2. **`Form` vs `List` for `.onMove`** — Both support `.onMove`, but `Form` with `.formStyle(.grouped)` gives the macOS sidebar look with section headers, while `List` with `.listStyle(.sidebar)` gives the Finder-style source list. `Form` was the right choice for this app since it has sections.

## Skill Improvements

1. **Add `.onMove` pattern to `swiftui-patterns` skill** — Document that `.onMove(perform:)` works natively on `Form` and `List` in macOS, no custom drag types needed.

2. **Add `.searchable` pattern to `swiftui-patterns` skill** — Document that `.searchable(text:prompt:)` on `Form` provides native search filtering.

3. **Add thumbnail generation pattern to `building-swiftui-macos-apps` skill** — Document `DispatchGroup` + `CGContext` approach for batch thumbnail generation on background queue.

## Next Steps

- Batch 3: Performance & pickers (debounce, hit test cache, popover picker)
- Batch 4: Gesture redesign (two-finger scroll pan)

---

**Status:** Closed
**Follow-up:** Batch 3 and Batch 4 implementation
