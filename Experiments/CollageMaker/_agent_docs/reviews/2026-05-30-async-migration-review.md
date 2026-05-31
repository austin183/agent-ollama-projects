# Diff Review — 2026-05-30 (Async Migration & Layered Mode)

**Changeset**: Uncommitted work on `main` branch
**Scope**: 12 modified files — CollageAssembler async migration, PreviewManager simplification, layered mode preview tracking
**Session**: [Session 067](../project-timeline/sessions/session-067.md)

## Files Changed

| File | Change |
|------|--------|
| `Services/CollageAssembler.swift` | **MAJOR** — All rendering methods converted from `renderQueue.sync` (blocking) to `await withCheckedContinuation` + `renderQueue.async` (non-blocking). Protocols updated to return `async`. `CollageAssembler` + `NSAttributedString` given `@unchecked Sendable`. |
| `Services/PreviewManager.swift` | Removed `Task.detached` wrappers — assembler methods are now async directly. Work still runs off-main-thread via the render queue inside each method. |
| `ViewModel/CollageViewModel.swift` | New `isLayeredMode` flag — controls whether `updatePreview()` calls `updateBackground()`/`updateTitleImage()`. `updateAllPanelPreviews()` sets `isLayeredMode = true` before updating panels, then updates background/title. |
| `ViewModel/ExportManager.swift` | Added `await` to `assembler.assembleWithCGImages()` call inside `Task.detached`. |
| `Views/CollageEditorView.swift` | Changed ZStack inner condition from `viewModel.panelRenderedImages.isEmpty` to `!viewModel.isLayeredMode`. |
| `Models/AssemblyConfig.swift` | Added `@unchecked Sendable` extensions to `LayoutConfig`, `TitleConfig`, `BackgroundConfig`, `AssemblyConfig`. |
| `Models/TitleStyle.swift` | Added `@unchecked Sendable` conformance. |
| `CollageAssemblerTests.swift` | All test methods marked `async`, added `await` to assembler calls. |
| `CollageViewModelTests.swift` | `MockAssembler` protocol methods updated to `async`. |
| `ExportFlowTests.swift` | `TrackingAssembler` protocol methods updated to `async`. |
| `PreviewManagerTests.swift` | `TestPreviewAssembler` protocol methods updated to `async`. |
| `_agent_docs/common-prompts.md` | Phase reference updated from "Phase 1" to "Phase 2". |

---

## Issue 1: `renderTitle` deadlock — early return bypasses continuation

**Severity: Critical**

**File**: `Services/CollageAssembler.swift:471`

```swift
func renderTitle(
    titleAttrString: NSAttributedString,
    titleStyle: TitleStyle,
    canvasSize: CGSize
) async -> NSImage? {
    guard !titleAttrString.string.isEmpty else { return nil }  // ← BUG

    return await withCheckedContinuation { cont in
        renderQueue.async {
            // ... all paths call cont.resume(...)
        }
    }
}
```

The early return guard is **outside** the `withCheckedContinuation` block. When `titleAttrString.string` is empty, the function returns `nil` directly without ever calling `cont.resume(...)`. The caller `await`ing this method will hang indefinitely — a deadlock.

This path is reachable whenever the user has no title text set, which is the default state.

**Fix**: Move the guard inside the continuation block:

```swift
return await withCheckedContinuation { cont in
    renderQueue.async {
        guard !titleAttrString.string.isEmpty else {
            cont.resume(returning: nil)
            return
        }
        // ... rest of the method
    }
}
```

---

## Issue 2: Outer `if let previewImage` guard prevents layered mode rendering

**Severity: Critical**

**File**: `Views/CollageEditorView.swift:55`

The entire ZStack is wrapped in an outer guard that the diff does **not** remove:

```swift
if let previewImage = viewModel.previewImage {   // ← outer guard (NOT in diff)
    GeometryReader { geometry in
        ZStack {
            if !viewModel.isLayeredMode {        // ← new condition (from diff)
                Image(nsImage: previewImage)
                // ...
            } else {
                // layered mode: background + panels + title
            }
        }
    }
}
```

In layered mode, `previewImage` can be `nil` (e.g., when `updatePreview()` returns early or the async task hasn't completed yet). When `previewImage` is `nil`, the outer `if let` fails and the **entire ZStack is skipped** — no background, no panels, no title. The `isLayeredMode` logic is rendered useless because the view never renders.

The diff changes the inner condition but leaves the outer guard intact. The outer guard should also be restructured so the ZStack renders independently of `previewImage` in layered mode.

**Fix**: Restructure the view so the ZStack is always rendered, with `previewImage` used only as a fallback in non-layered mode:

```swift
GeometryReader { geometry in
    ZStack {
        if viewModel.isLayeredMode {
            // layered: background + panels + title (each independently rendered)
        } else if let previewImage = viewModel.previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
```

---

## Issue 3: Dead code — `if isLayeredMode` in `updatePreview()` always false

**Severity: Moderate**

**File**: `ViewModel/CollageViewModel.swift:784`

```swift
func updatePreview() {
    // ...
    isLayeredMode = false
    previewManager.updatePreview(...)

    if isLayeredMode {          // ← always false; dead code path
        updateBackground()
        updateTitleImage()
    }
}
```

`isLayeredMode` is set to `false` right before the conditional, so the background and title updates in `updatePreview()` are **always skipped**. This appears intentional (the method produces a composite preview, not layered elements), but the guard is misleading dead code.

If `updatePreview()` is ever called standalone (without `updateAllPanelPreviews()`), the background and title will never update — but the current code already skips them via the dead conditional, so the behavior is unchanged.

**Fix**: Either remove the dead conditional, or rename the method to `updateCompositePreview()` to make the intent explicit and avoid the confusing guard.

---

## Validated Clean Changes

The following changes were validated with no issues found:

| Change | Validation |
|--------|-----------|
| **`@unchecked Sendable` on config structs** | Justified. `AssemblyConfig`, `LayoutConfig`, `TitleConfig`, `BackgroundConfig` are value types captured by async method parameters and only accessed on the serial `renderQueue`. No shared mutable state. |
| **`@unchecked Sendable` on `NSAttributedString`** | Justified with comment. Attributed strings are only accessed on the serial render queue after being captured by value in async method parameters. |
| **`@unchecked Sendable` on `TitleStyle`** | Justified. Plain struct with value-typed properties (`String`, `CGFloat`, `NSColor`). `NSColor` is `NSCopying`-based and safe to use cross-thread when not mutated concurrently. |
| **`@unchecked Sendable` on `CollageAssembler`** | Justified. All access is gated through a single serial `DispatchQueue` (`renderQueue`). No stored mutable state outside the queue. |
| **`PreviewManager` removing `Task.detached`** | Sound. The async assembler methods internally use `withCheckedContinuation` + `renderQueue.async`, so rendering work still runs off the main thread. The Task closures now run on `MainActor` (since `PreviewManager` is `@MainActor`), which is correct for setting `@Observable` properties. |
| **`ExportManager` adding `await`** | Correct. The `Task.detached` block correctly `await`s the now-async assembler method. |
| **Test mock updates** | `MockAssembler`, `TrackingAssembler`, and `TestPreviewAssembler` all correctly implement the updated async protocol signatures. |
| **Test method `async` marking** | All `@Test` methods in `CollageAssemblerTests.swift` correctly marked `async` with `await` on assembler calls. |
| **Concurrent stress test update** | `CollageAssemblerTests.swift:422` — `Task.detached` block correctly `await`s the async `renderBackground` call. |

---

## Summary

| # | Severity | File | Issue |
|---|----------|------|-------|
| 1 | **Critical** | `CollageAssembler.swift:471` | `renderTitle` early return bypasses continuation — causes deadlock on empty title |
| 2 | **Critical** | `CollageEditorView.swift:55` | Outer `if let previewImage` guard prevents ZStack from rendering in layered mode when `previewImage` is nil |
| 3 | **Moderate** | `CollageViewModel.swift:784` | Dead code: `if isLayeredMode` in `updatePreview()` always evaluates to false |

**Issues 1 and 2 are showstoppers.** Issue 1 will cause hangs whenever an empty title is rendered (default state). Issue 2 means the layered mode UI simply won't display anything in many scenarios. Both should be fixed before merging.
