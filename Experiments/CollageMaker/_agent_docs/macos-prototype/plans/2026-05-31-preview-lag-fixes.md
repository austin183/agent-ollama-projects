# Preview Lag — Remaining Fixes

**Date**: 2026-05-31
**Problem**: `updatePreview` still causes hitches during rapid user input (slider drags, color picker, gradient angle). The 3-phase plan from 2026-05-30 (layered mode, async protocol, RenderScheduler + generation tracking) has been implemented, but lag persists.

**Root Cause**: Six remaining issues compound to produce visible lag:
1. No debouncing on background/title property `didSet` — every slider tick fires a full render
2. `RenderScheduler` cannot actually cancel in-flight work — `DispatchQueue.async` runs to completion
3. Preview renders at full canvas resolution (1920x1080) then scales down to preview size (960x540)
4. Single `panelPreviewTask` shared across all panels — only one panel can render at a time
5. `regenerateLayout` fires redundant preview calls
6. `PreviewManager` is `@MainActor` — task setup/teardown competes with UI

---

## Phase 1: Debounce Background and Title Property Changes

**Goal**: Reduce render submissions from 30-60/sec (slider ticks) to ~6/sec (150ms debounce).

### Problem Detail

Every `didSet` on these properties calls `updatePreview()` immediately with no debounce:

| Property | Line | Fires During |
|----------|------|-------------|
| `titleAttrString` | 85 | typing, paste |
| `titleStyle` | 102 | font/style picker (non-drag) |
| `backgroundColor` | 133 | color picker drag |
| `backgroundStyle` | 156 | style picker |
| `gradientStartColor` | 168 | color picker drag |
| `gradientEndColor` | 180 | color picker drag |
| `gradientAngle` | 192 | slider drag |
| `backgroundImage` | 207 | image selection |
| `backgroundOpacity` | 219 | slider drag |

Compare with `applyPanLive()` (line 555-568) which debounces at 150ms via `previewDebounceTask`. The gradient/color properties have no such protection. A single slider drag can fire 50+ events, each spawning a new full-canvas render task.

### Design

#### Add debounced variants for rapid-interaction properties

Create a new `updatePreviewDebounced()` method on `CollageViewModel`:

```swift
private var previewDebounceTask: Task<Void, Never>?   // already exists, line 725

func updatePreviewDebounced() {
    previewDebounceTask?.cancel()
    previewDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)
        self?.updatePreview()
    }
}
```

Change these `didSet` callers to use `updatePreviewDebounced()` instead of `updatePreview()`:
- `gradientAngle` (line 192) — slider drag, most frequent
- `gradientStartColor` (line 168) — color picker drag
- `gradientEndColor` (line 180) — color picker drag
- `backgroundOpacity` (line 219) — slider drag
- `backgroundColor` (line 133) — color picker drag
- `backgroundStyle` (line 156) — picker selection (can stay immediate, but debouncing is harmless)

Keep these as immediate `updatePreview()` (user expects instant feedback on discrete changes):
- `titleAttrString` (line 85) — typing, each keystroke should show
- `titleStyle` (line 102) — discrete picker selection
- `backgroundImage` (line 207) — discrete selection

**Rationale**: Color pickers and angle sliders produce rapid, continuous values. 150ms debounce gives ~7 updates/sec which is visually smooth. Title text and discrete selections benefit from immediate feedback.

#### Files Modified

| File | Change |
|------|--------|
| `CollageMaker/ViewModel/CollageViewModel.swift` | Add `updatePreviewDebounced()`, change 5 `didSet` callers |

#### Verification

- Build + test pass
- Manual: drag gradient angle slider — preview updates smoothly at ~7fps, no hitch
- Manual: drag background opacity slider — same
- Manual: type in title — still immediate

**Expected impact**: 8-40x reduction in render queue submissions during slider/color picker interaction. This is the single largest contributor to current lag.

---

## Phase 2: Render Preview at Preview Size

**Goal**: Reduce pixel count from 2,073,600 (1920x1080) to 518,400 (960x540) — a 4x reduction in rendering work.

### Problem Detail

`CollageAssembler.assemblePreviewWithCGImages` (line 103-123) calls `renderIntoContext` which creates an `NSBitmapImageRep` at `config.canvasSize` (1920x1080). The `previewSize` parameter (960x540) is only used when constructing the final `NSImage`:

```swift
return NSImage(cgImage: finalImage, size: previewSize)
```

This `size` parameter tells NSImage how to *display* the image, but the actual CoreGraphics rendering already happened at full resolution. The 4x larger bitmap means 4x more pixel fills, 4x more image sampling, and 4x more memory bandwidth.

### Design

#### New `renderPreviewIntoContext` method

Add a variant that renders at the target preview size instead of canvas size:

```swift
func assemblePreviewWithCGImages(
    config: AssemblyConfig,
    cgImages: [CGImage?],
    backgroundImage: CGImage?,
    previewSize: CGSize
) async -> NSImage? {
    await scheduler.render {
        guard let bitmapRep = self.renderPreviewIntoContext(
            config: config,
            cgImages: cgImages,
            backgroundImage: backgroundImage,
            previewSize: previewSize
        ) else {
            return nil
        }
        guard let finalImage = bitmapRep.cgImage else {
            logger.error("Failed to extract CGImage from bitmap rep for preview")
            return nil
        }
        return NSImage(cgImage: finalImage, size: previewSize)
    }
}

private func renderPreviewIntoContext(
    config: AssemblyConfig,
    cgImages: [CGImage?],
    backgroundImage: CGImage?,
    previewSize: CGSize
) -> NSBitmapImageRep? {
    let scale = previewSize.width / config.canvasSize.width

    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(previewSize.width),
        pixelsHigh: Int(previewSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )
    guard let bitmapRep else { return nil }
    bitmapRep.size = previewSize
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    guard let context = NSGraphicsContext.current?.cgContext else { return nil }
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)

    // Draw background at canvas coordinates (scaled by context)
    switch config.background.style {
    case .solid:
        context.setFillColor(config.background.color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: config.canvasSize.width, height: config.canvasSize.height))
    case .gradient:
        drawGradient(into: context, size: config.canvasSize, ...)
    case .image:
        drawImageBackground(into: context, size: config.canvasSize, ...)
    }

    // Draw panels at canvas coordinates (scaled by context)
    drawPanels(into: context, panels: config.layout.panels, cgImages: cgImages, ...)

    // Draw title at canvas coordinates (scaled by context)
    if !config.title.attrString.string.isEmpty {
        drawTitle(into: context, titleAttrString: config.title.attrString, ...,
                  canvasWidth: config.canvasSize.width, canvasHeight: config.canvasSize.height)
    }

    return bitmapRep
}
```

The key insight: create the bitmap at `previewSize`, then `context.scaleBy(x: scale, y: scale)` so all drawing commands use canvas coordinates. CoreGraphics handles the downscaling automatically with high-quality interpolation.

#### Alternative: Simpler approach

If the scaled-context approach introduces coordinate issues, a simpler alternative is to just change the bitmap dimensions:

```swift
private func renderPreviewIntoContext(...) -> NSBitmapImageRep? {
    let scale = previewSize.width / config.canvasSize.width

    let bitmapRep = NSBitmapImageRep(
        pixelsWide: Int(previewSize.width),
        pixelsHigh: Int(previewSize.height),
        ...
    )
    // ... setup context ...
    context.scaleBy(x: scale, y: scale)
    // ... all existing draw calls use canvas coordinates unchanged ...
}
```

The `scaleBy` transform means all existing `drawPanels`, `drawTitle`, `drawGradient` calls work unchanged — they draw in canvas coordinates, and the context scales them down.

#### Files Modified

| File | Change |
|------|--------|
| `CollageMaker/Services/CollageAssembler.swift` | Add `renderPreviewIntoContext`, use in `assemblePreviewWithCGImages` |

#### Verification

- Build + test pass
- `CollageAssemblerTests.swift` line 247: `#expect(preview?.size == CanvasConfig.defaultPreviewSize)` — still passes
- Manual: preview looks the same visually (just lower resolution, which is appropriate for preview)
- Performance: render time drops ~4x

**Expected impact**: 4x reduction in per-render CPU time. Combined with Phase 1's 8-40x reduction in render count, total CPU usage drops 32-160x during slider drags.

---

## Phase 3: Per-Panel Task Tracking

**Goal**: Allow multiple panels to render concurrently instead of sequentially.

### Problem Detail

`PreviewManager` has a single `panelPreviewTask` (line 20):
```swift
private var panelPreviewTask: Task<Void, Never>?
```

When `updateAllPanelPreviews()` iterates panels (line 106-123), each call to `updatePanelPreview` cancels the previous panel's task. Only the last panel's task is tracked. If the user triggers a panel update for panel A, then panel B, panel A's task is cancelled (though the DispatchQueue work still runs due to Phase 2's limitation).

### Design

#### Per-panel task dictionary

```swift
private var panelPreviewTasks: [UUID: Task<Void, Never>] = [:]

func updatePanelPreview(crop: ..., cgImage: ..., panelSize: ..., panelId: UUID) {
    panelGenerations[panelId, default: 0] += 1
    let gen = panelGenerations[panelId]!
    let assembler = self.assembler

    panelPreviewTasks[panelId]?.cancel()
    panelPreviewTasks[panelId] = Task { [weak self, assembler, crop, cgImage, panelSize, panelId, gen] in
        guard let self, gen == self.panelGenerations[panelId] else { return }
        let result = await assembler.renderPanel(crop: crop, cgImage: cgImage, panelSize: panelSize)
        guard gen == self.panelGenerations[panelId] else { return }
        self.panelRenderedImages[panelId] = result
    }
}
```

Update `clearAll()` and `cancelAll()` to clear the dictionary.

#### Files Modified

| File | Change |
|------|--------|
| `CollageMaker/Services/PreviewManager.swift` | `panelPreviewTask` → `panelPreviewTasks[UUID: Task]` |

#### Verification

- Build + test pass
- Manual: after layout regeneration, all panels render concurrently

**Expected impact**: N panels render in parallel instead of sequentially. For a 6-panel layout, initial render time drops from 6x to ~1x (bounded by the serial render queue, but tasks submit non-blockingly).

---

## Phase 4: Cancel Stale Work in RenderScheduler

**Goal**: Actually abort in-flight CoreGraphics work when superseded, not just mark the Swift task as cancelled.

### Problem Detail

`Task.cancel()` marks the Swift task as cancelled but does NOT interrupt `DispatchQueue.async` work. The render closure runs to completion, consuming CPU for a result that will be discarded by the generation check. During rapid slider drags with Phase 1's debounce, this is less severe, but still wastes CPU.

### Design

#### Option A: Generation check at submission time (recommended)

Add a global generation counter to `RenderScheduler`. Check it at queue entry — if the work is already stale, don't submit it:

```swift
actor RenderScheduler {
    private let queue = DispatchQueue(label: "austin183.indie.CollageMaker.render")
    private var generation: Int = 0

    func render<T: Sendable>(
        generation: Int,
        _ work: @escaping @Sendable () -> T
    ) async -> T? {
        let currentGeneration = generation
        generation += 1

        await withTaskCancellationHandler {
            // On cancellation, just return nil
        } operation: {
            await withCheckedContinuation { cont in
                queue.async {
                    // Check if this is still the latest submission
                    // (this check is approximate — the actor's generation may have advanced)
                    let result = work()
                    cont.resume(returning: result)
                }
            }
        }
    }
}
```

**Problem**: The actor's own execution model makes this tricky — the `generation` check inside the queue closure can't easily access the actor state.

#### Option B: Skip submission if task is already cancelled (simplest)

Check `Task.isCancelled` before submitting to the queue:

```swift
func render<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T? {
    await withCheckedContinuation { cont in
        if Task.isCancelled {
            cont.resume(returning: nil as! T)
            return
        }
        queue.async {
            let result = work()
            cont.resume(returning: result)
        }
    }
}
```

This catches the case where the Swift task is cancelled between creation and queue execution. It won't abort work already in the queue, but it prevents new submissions from cancelled tasks.

#### Option C: LIFO priority via queue re-submission (most effective)

The most effective approach for "latest wins" is to not try to cancel at all, but instead ensure only the latest render runs. This is what the generation counter in `PreviewManager` already does at the *result* level. At the *work* level, the simplest effective approach is to accept that stale work runs but is discarded.

**Recommendation**: Implement Option B (cheap, catches early cancellation) and rely on the existing generation counter at the result level for the rest. The CPU waste from stale renders is bounded by Phase 1's debouncing (max ~7 renders/sec) and Phase 2's 4x size reduction.

#### Files Modified

| File | Change |
|------|--------|
| `CollageMaker/Services/RenderScheduler.swift` | Add `Task.isCancelled` check before queue submission, return `T?` |
| `CollageMaker/Services/CollageAssembler.swift` | Update callers to handle `T?` return |

#### Verification

- Build + test pass
- Manual: same visual behavior, less CPU usage visible in Activity Monitor during slider drags

**Expected impact**: Moderate. Prevents submission of already-cancelled tasks. Combined with generation-based discard, ensures wasted work is minimal.

---

## Phase 5: Deduplicate `regenerateLayout` Preview Calls

**Goal**: Eliminate redundant render submissions during layout regeneration.

### Problem Detail

`regenerateLayout()` (line 408-451) calls:
```swift
isLayeredMode = false
previewManager.panelRenderedImages.removeAll()
updatePreview()         // → renders full composite at canvas size
updateAllPanelPreviews() // → sets isLayeredMode=true, renders all panels + background + title
```

But `updatePreview()` renders the full composite while `isLayeredMode = false`. Then `updateAllPanelPreviews()` sets `isLayeredMode = true` and renders background + panels + title separately. The full composite from `updatePreview()` is immediately superseded by the layered renders.

### Design

#### Remove the redundant `updatePreview()` call

```swift
func regenerateLayout() {
    // ... existing layout logic ...

    isLayeredMode = false
    previewManager.panelRenderedImages.removeAll()

    // Remove this line — it's immediately superseded by updateAllPanelPreviews()
    // updatePreview()

    updateAllPanelPreviews()
}
```

**But**: If `updateAllPanelPreviews()` is async, the preview pane will be empty until all panel renders complete. To show something immediately, render the full composite first (synchronously or with higher priority), then update layers.

#### Alternative: Render composite only, let layered mode activate on demand

```swift
func regenerateLayout() {
    // ... existing layout logic ...

    isLayeredMode = false
    previewManager.panelRenderedImages.removeAll()
    updatePreview()  // show composite immediately

    // Don't call updateAllPanelPreviews() here — enter layered mode only
    // when the user interacts with a panel
}
```

This way the user sees the composite preview immediately. Layered mode (individual panels) only activates when the user pans/pinches a panel, which calls `updateAllPanelPreviews()`.

**Current behavior**: `analyzeSaliency()` (line 530-531) also calls both:
```swift
updatePreview()
updateAllPanelPreviews()
```
Apply the same fix there.

#### Files Modified

| File | Change |
|------|--------|
| `CollageMaker/ViewModel/CollageViewModel.swift` | Remove redundant `updateAllPanelPreviews()` from `regenerateLayout()` and `analyzeSaliency()` |

#### Verification

- Build + test pass
- Manual: after layout change, preview shows composite immediately. Pan/zoom a panel → layered mode activates with individual panel renders.

**Expected impact**: 50% reduction in render submissions during layout regeneration (from 1 composite + N panels + 1 bg + 1 title to just 1 composite). Layered mode renders only happen on demand.

---

## Phase 6: Move PreviewManager Off Main Actor

**Goal**: Eliminate main thread contention from task setup, generation counter updates, and result assignment.

### Problem Detail

`PreviewManager` is `@MainActor` (line 12). Every `updatePreview()` call from a `didSet` fires a `Task { }` closure that captures `[weak self, assembler, config, ...]`. The task body accesses `self.previewGeneration`, `self.previewTask`, and `self.previewImage` — all on the main actor. While the heavy CoreGraphics work runs on the render queue, the task lifecycle (creation, cancellation, generation increment, result assignment) competes with SwiftUI's body evaluation.

### Design

#### Remove `@MainActor` from PreviewManager

```swift
@Observable
final class PreviewManager {
    // ... no @MainActor ...
}
```

The `@Observable` macro generates a `changeHandler` that SwiftUI uses for view invalidation. `@Observable` objects accessed from views require main actor isolation at the *access point*, not on the type itself.

**Changes needed**:
- `CollageViewModel` accesses `previewManager.previewImage`, `previewManager.previewBackgroundImage`, etc. through computed properties (line 229-244). These are `@MainActor` (inherited from `CollageViewModel`). The access happens on main actor, which is fine.
- Result assignment: `self.previewImage = result` inside the async task closure now runs on a background executor. `@Observable` property mutation is thread-safe (it uses `os_unfair_lock` internally).
- `previewTask?.cancel()` and generation counter updates are now non-actor-isolated — they need a lock or actor isolation.

#### Add a serial lock for internal state

```swift
@Observable
final class PreviewManager {
    var previewImage: NSImage?
    var previewBackgroundImage: NSImage?
    var panelRenderedImages: [UUID: NSImage] = [:]
    var titleImage: NSImage?

    private let lock = NSLock()
    private var previewTask: Task<Void, Never>?
    private var previewGeneration: Int = 0
    // ... etc ...

    func updatePreview(...) {
        lock.lock()
        previewGeneration += 1
        let gen = previewGeneration
        previewTask?.cancel()
        previewTask = Task { [weak self, ...] in
            // ... render ...
            guard let self, gen == self.lock.withLock({ self.previewGeneration }) else { return }
            self.previewImage = result
        }
        lock.unlock()
    }
}
```

Or simpler: make `PreviewManager` an `actor`:

```swift
@Observable
actor PreviewManager {
    // ... all state is actor-isolated ...
}
```

But `actor` + `@Observable` has caveats — `@Observable`'s generated `changeHandler` expects main actor access. The `NSLock` approach is safer.

**Actually**: The simplest approach is to keep `@MainActor` but recognize that the current code already offloads well. The `@MainActor` overhead is just the generation counter increment and task assignment — negligible work. The real cost is the `self.previewImage = result` assignment after render completion, which triggers `@Observable` change notification. This *must* happen on the main actor for SwiftUI to observe it correctly.

**Recommendation**: Skip this phase. The `@MainActor` overhead is negligible compared to the CoreGraphics rendering. The main thread contention comes from too many renders being submitted (Phase 1), each render being too large (Phase 2), and too many renders per event (Phase 5).

---

## Summary

| Phase | Fix | Effort | Impact |
|-------|-----|--------|--------|
| 1 | Debounce gradient/color/opacity properties | Small (5 `didSet` changes) | 8-40x fewer renders during slider drags |
| 2 | Render preview at preview size, not canvas size | Medium (new render method) | 4x faster per render |
| 3 | Per-panel task tracking | Small (dict instead of single var) | N panels render concurrently |
| 4 | Cancel stale work in RenderScheduler | Small (Task.isCancelled check) | Prevents wasted CPU on cancelled tasks |
| 5 | Deduplicate regenerateLayout preview calls | Small (remove 2 lines) | 50% fewer renders on layout change |
| 6 | Move PreviewManager off main actor | Skipped — negligible benefit | — |

**Combined impact**: Phases 1+2 alone produce 32-160x reduction in total preview CPU during slider/color picker interaction. Phases 3+4+5 clean up the remaining edge cases.

---

## Files Modified (Aggregate)

| File | Phases |
|------|--------|
| `CollageMaker/ViewModel/CollageViewModel.swift` | 1, 5 |
| `CollageMaker/Services/CollageAssembler.swift` | 2 |
| `CollageMaker/Services/PreviewManager.swift` | 3 |
| `CollageMaker/Services/RenderScheduler.swift` | 4 |
| `CollageMakerTests/PreviewManagerTests.swift` | 3 (per-panel task tests) |
| `CollageMakerTests/CollageAssemblerTests.swift` | 2 (preview size test) |

## Verification (After Each Phase)

1. `xcodebuild build -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64'`
2. `xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests`
3. `bash script/build_and_run.sh run` — app launches, no crashes
4. Manual stress test: rapid slider drags, color picker, scroll-wheel pan — preview tracks gesture in real-time

## Risks

- **Phase 2 `context.scaleBy`**: The scaled context approach is standard CoreGraphics practice. All existing drawing code uses canvas coordinates, so `scaleBy` is transparent. Risk: title text rendering at lower resolution may appear slightly blurrier in the preview (acceptable for preview, export still renders at full resolution).
- **Phase 5 removing `updateAllPanelPreviews()`**: Layered mode won't activate automatically. User must interact with a panel to enter layered mode. This is actually the desired behavior — composite mode is the default, layered mode is opt-in via panel interaction.
