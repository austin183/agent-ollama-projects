# Preview Update Performance — 3-Phase Fix

**Date**: 2026-05-30
**Problem**: Panning, zooming, and title font slider produce live preview updates that lag behind the gesture by 1-2 seconds, then "catch up."

**Root Cause**: Three compounding issues in `CollageAssembler` and `PreviewManager`:
1. Redundant rendering — every property change submits 3 renders to the queue (full composite + background + title), but the view only displays one rendering mode
2. Blocking queue entry — `renderQueue.sync { }` blocks the calling thread even though it's already off-main-actor via `Task.detached`
3. FIFO stale work — older renders complete after newer ones, producing stale frames that overwrite fresh state

---

## Phase 1: Eliminate Redundant Rendering

**Goal**: Reduce queue submissions from 3 per property change to 1 (composite mode) or 3 only when layers are actually displayed.

### Problem Detail

`CollageViewModel.updatePreview()` (line 765-783) always calls:
1. `previewManager.updatePreview(...)` → `assemblePreviewWithCGImages` — renders full composite (background + panels + title)
2. `updateBackground()` → `renderBackground` — renders background again
3. `updateTitleImage()` → `renderTitle` — renders title again

`CollageEditorView.body` (line 55-94) has two rendering modes:
- **Composite mode** (`panelRenderedImages.isEmpty`): shows only `previewImage` (the full composite)
- **Layered mode** (`panelRenderedImages` not empty): shows `previewBackgroundImage` + individual panels + `titleImage`

In composite mode (the default, before any panel interaction), `updateBackground()` and `updateTitleImage()` are wasted — those renders sit in `previewBackgroundImage` and `titleImage` but are never displayed because the view shows `previewImage` instead.

### Design

#### New `isLayeredMode` flag

Add `isLayeredMode: Bool` to `CollageViewModel` (default `false`). This replaces the implicit `panelRenderedImages.isEmpty` check in the view with an explicit mode flag.

**Benefits over current approach**:
- Eliminates the race where `panelRenderedImages` is briefly empty between `clearAll()` and the first async panel render completing (causing a flicker back to composite mode)
- Fewer SwiftUI body recomputes — the flag only flips twice per session (layout regeneration → `false`, panel interaction → `true`), whereas the current `panelRenderedImages` dictionary is replaced on every single panel render

**Transition rules**:
- `regenerateLayout()` → `isLayeredMode = false` (layout changed, start fresh in composite mode)
- `updateAllPanelPreviews()` → `isLayeredMode = true` (user has interacted with a panel, enter layered mode)
- Individual panel updates (`updatePanelPreview`) → no change to flag (stay in current mode)

#### `CollageViewModel` changes

**`updatePreview()`** (line 765-783):
```swift
func updatePreview() {
    guard !isInitializing else { return }

    let config = buildAssemblyConfig()
    let cgImages = images.map { $0.cgImage }
    let backgroundImageCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

    previewManager.updatePreview(
        config: config,
        cgImages: cgImages,
        backgroundImage: backgroundImageCG,
        previewSize: CanvasConfig.defaultPreviewSize
    )

    // Only render layers when the view is actually displaying them
    if isLayeredMode {
        updateBackground()
        updateTitleImage()
    }
}
```

**`regenerateLayout()`** (line 430-449):
```swift
func regenerateLayout() {
    // ... existing layout logic ...

    isLayeredMode = false  // <-- new
    previewManager.panelRenderedImages.removeAll()
    updatePreview()
    updateAllPanelPreviews()
}
```

**`updateAllPanelPreviews()`** (line 786-793):
```swift
func updateAllPanelPreviews() {
    isLayeredMode = true  // <-- new
    previewManager.updateAllPanelPreviews(...)
    // Also render layers for the layered display
    updateBackground()
    updateTitleImage()
}
```

**`updateBackground()`** (line 746-755): No changes. It's called from `updatePreview()` (when layered) and `updateAllPanelPreviews()`.

**`updateTitleImage()`** (line 795-801): No changes. Same callers as above.

**`updateTitleImageLive()`** (line 803-809): No changes. Debounced live title updates fire during drag.

#### `CollageEditorView` changes

**`body`** (line 55-94): Replace `if viewModel.panelRenderedImages.isEmpty` with `if !viewModel.isLayeredMode`:

```swift
var body: some View {
    if let previewImage = viewModel.previewImage {
        GeometryReader { geometry in
            // ... existing frame calculations ...

            ZStack {
                if !viewModel.isLayeredMode {
                    // Composite mode — single image
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id("preview")
                } else {
                    // Layered mode — bg + panels + title
                    if let bg = viewModel.previewBackgroundImage {
                        Image(nsImage: bg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    ForEach(viewModel.panels) { panel in
                        if let renderedImage = viewModel.panelRenderedImages[panel.id],
                           let scaledFrame = panelFrames[panel.id] {
                            Image(nsImage: renderedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: scaledFrame.width, height: scaledFrame.height)
                                .position(x: scaledFrame.midX, y: scaledFrame.midY)
                        }
                    }

                    if let titleImg = viewModel.titleImage {
                        Image(nsImage: titleImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }

                // ... existing hit areas, overlays, etc. ...
            }
        }
    }
}
```

#### Test changes

- `CollageViewModelTests.swift` — `MockAssembler` unchanged (no protocol changes in Phase 1)
- `ExportFlowTests.swift` — `TrackingAssembler` unchanged
- `PreviewManagerTests.swift` — `TestPreviewAssembler` unchanged
- `CollagePerformanceTests.swift` — Tests may need updating if they assert on `previewCalls` / `renderBackgroundCalls` counts, since Phase 1 changes how many times these are called

**Expected impact**: 66% reduction in render queue submissions during common interactions (font slider, background color picker, gradient angle). No reduction during layout regeneration (all renders are needed), but that's a one-shot operation, not a rapid gesture.

---

## Phase 2: Async Protocol + Non-Blocking Queue Entry

**Goal**: Eliminate blocking on queue entry. Cancelled tasks yield immediately instead of blocking the serial queue.

### Problem Detail

Current implementation uses `renderQueue.sync { }`:
```swift
func assemblePreviewWithCGImages(...) -> NSImage? {
    renderQueue.sync {
        // ... heavy CoreGraphics rendering ...
    }
}
```

Even though callers are `Task.detached` (off-main-actor), `sync` blocks the detached task's thread until the serial queue processes the work. During rapid gestures, 5-10 tasks queue up, each blocking its thread waiting for the queue. The result is accumulated latency — the UI "catches up" as the queue drains.

### Design

#### Protocol changes

All rendering methods become `async`:

```swift
protocol CollageRenderer {
    func assembleWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        quality: Double
    ) async -> Data?

    func assemblePreviewWithCGImages(
        config: AssemblyConfig,
        cgImages: [CGImage?],
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage?
}

protocol PanelRenderer {
    func renderPanel(
        crop: CropInfo,
        cgImage: CGImage,
        panelSize: CGSize
    ) async -> NSImage?
}

protocol BackgroundRenderer {
    func renderBackground(
        config: BackgroundConfig,
        canvasSize: CGSize,
        backgroundImage: CGImage?,
        previewSize: CGSize
    ) async -> NSImage?
}

protocol TitleRenderer {
    func renderTitle(
        titleAttrString: NSAttributedString,
        titleStyle: TitleStyle,
        canvasSize: CGSize
    ) async -> NSImage?
}
```

#### `CollageAssembler` changes

Replace `renderQueue.sync { }` with `withCheckedContinuation` + `renderQueue.async { }`:

```swift
func assemblePreviewWithCGImages(
    config: AssemblyConfig,
    cgImages: [CGImage?],
    backgroundImage: CGImage?,
    previewSize: CGSize
) async -> NSImage? {
    await withCheckedContinuation { cont in
        renderQueue.async {
            let result = self.renderPreviewImpl(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
            cont.resume(returning: result)
        }
    }
}
```

The rendering logic is extracted into private `*Impl` methods to avoid code duplication. The key change is `async` submission instead of `sync` — the calling thread yields immediately after submitting work to the queue.

**Important**: `NSGraphicsContext.current` is thread-scoped. The serial queue ensures only one rendering operation modifies it at a time. The `withCheckedContinuation` pattern is safe because the continuation is resumed from the queue thread (which has the correct graphics context), and the resulting `NSImage`/`Data` is thread-safe data.

#### `PreviewManager` changes

Callers change from `await Task.detached { }.value` to `await assembler.method(...)`:

```swift
func updatePreview(...) {
    let assembler = self.assembler

    previewTask?.cancel()
    previewTask = Task { [weak self, assembler, config, cgImages, backgroundImage, previewSize] in
        guard let self else { return }
        let result = await assembler.assemblePreviewWithCGImages(
            config: config,
            cgImages: cgImages,
            backgroundImage: backgroundImage,
            previewSize: previewSize
        )
        self.previewImage = result
    }
}
```

Same pattern for `updateBackground`, `updatePanelPreview`, `updateTitleImage`.

#### `ExportManager` changes

```swift
exportTask = Task.detached { [assembler, config, cgImages, backgroundImageCG, quality, url] in
    let data = await assembler.assembleWithCGImages(
        config: config,
        cgImages: cgImages,
        backgroundImage: backgroundImageCG,
        quality: quality
    )
    if let data {
        try data.write(to: url)
    }
}
```

#### Test changes

**`MockAssembler`** (`CollageViewModelTests.swift`):
```swift
func assembleWithCGImages(...) async -> Data? { assembleData }
func assemblePreviewWithCGImages(...) async -> NSImage? { assemblePreviewImage }
func renderPanel(...) async -> NSImage? { NSImage(size: panelSize) }
func renderBackground(...) async -> NSImage? { NSImage(size: previewSize) }
func renderTitle(...) async -> NSImage? { nil }
```

**`TrackingAssembler`** (`ExportFlowTests.swift`): Same — add `async` to all 5 methods.

**`TestPreviewAssembler`** (`PreviewManagerTests.swift`): Same — add `async` to all 5 methods.

**`CollageAssemblerTests.swift`**: Concurrent tests already use `await` on the assembler methods (line 354, 388, 422). The `await` on non-async functions was a no-op; after this phase it becomes actual async suspension. No test code changes needed for the concurrent tests. The synchronous tests (lines 11-78) need `await` added at call sites and `async` on the test functions.

**`CollagePerformanceTests.swift`**: Uses `TrackingAssembler` which will be async. The tests already use `await Task.sleep` and may need minor adjustments.

#### Protocol extension

The `extension CollageAssembly` default `assemble()` method (line 54-70) calls `assembleWithCGImages` synchronously. Since this is only used for convenience (converting `NSImage` → `CGImage` → call the real method), it needs to become async:

```swift
extension CollageAssembly {
    func assemble(
        config: AssemblyConfig,
        images: [NSImage],
        backgroundImage: NSImage?,
        quality: Double
    ) async -> Data? {
        let cgImages = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        let bgCGImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return await assembleWithCGImages(
            config: config,
            cgImages: cgImages,
            backgroundImage: bgCGImage,
            quality: quality
        )
    }
}
```

Check if anything calls this default `assemble()` method. If not, can leave as-is or remove.

**Expected impact**: Cancelled `Task.detached` tasks no longer block on queue entry. The calling thread yields immediately. Queue contention remains (FIFO serial), but tasks don't pile up blocking their callers. This alone should reduce the "catch up" lag significantly.

---

## Phase 3: Actor-Based Render Scheduler + Generation Tracking

**Goal**: Discard stale render results. The UI only shows the latest render, not older renders that complete after newer ones.

### Problem Detail

Even with Phase 2's non-blocking queue entry, work already in the FIFO serial queue runs to completion. If the user drags a slider rapidly, 5 renders may be in the queue. When they complete, render #3 finishes, updates the UI, then render #5 finishes and updates again — but render #4's result was the "correct" intermediate state. The user sees frames from stale renders.

### Design

#### `RenderScheduler` actor

New file `Services/RenderScheduler.swift`:

```swift
import Foundation

/// Serializes CoreGraphics rendering operations to protect NSGraphicsContext.current
/// from concurrent corruption, while yielding non-blockingly to the caller.
actor RenderScheduler {
    private let queue = DispatchQueue(label: "austin183.indie.CollageMaker.render")

    /// Submit rendering work to the serial queue. Returns non-blockingly.
    /// The caller's thread is freed immediately; work executes on the queue.
    func render<T: Sendable>(_ work: @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                let result = work()
                cont.resume(returning: result)
            }
        }
    }
}
```

The actor is thin — it wraps the serial `DispatchQueue` with async submission. The actor boundary provides structured concurrency integration (cancellation propagation, task grouping) while the underlying queue provides `NSGraphicsContext.current` thread safety.

#### `CollageAssembler` changes

Replace `private let renderQueue = DispatchQueue(...)` with `private let scheduler = RenderScheduler()`. Replace each `withCheckedContinuation { cont in renderQueue.async { ... } }` with `await scheduler.render { ... }`:

```swift
func assemblePreviewWithCGImages(...) async -> NSImage? {
    await scheduler.render {
        self.renderPreviewImpl(
            config: config,
            cgImages: cgImages,
            backgroundImage: backgroundImage,
            previewSize: previewSize
        )
    }
}
```

This is cleaner than the Phase 2 `withCheckedContinuation` pattern — the actor encapsulates the continuation logic.

#### `PreviewManager` generation tracking

Add a generation counter per render type. Increment on each `update*` call. After `await`, discard the result if a newer call has superseded it:

```swift
@MainActor
@Observable
final class PreviewManager {
    // ... existing properties ...

    private var previewGeneration: Int = 0
    private var backgroundGeneration: Int = 0
    private var panelGeneration: Int = 0
    private var titleGeneration: Int = 0

    func updatePreview(...) {
        previewGeneration += 1
        let gen = previewGeneration
        previewTask?.cancel()
        previewTask = Task { [weak self, assembler, config, cgImages, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await assembler.assemblePreviewWithCGImages(
                config: config,
                cgImages: cgImages,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
            guard gen == self.previewGeneration else { return }
            self.previewImage = result
        }
    }

    func updateBackground(...) {
        backgroundGeneration += 1
        let gen = backgroundGeneration
        backgroundTask?.cancel()
        backgroundTask = Task { [weak self, assembler, config, canvasSize, backgroundImage, previewSize] in
            guard let self else { return }
            let result = await assembler.renderBackground(
                config: config,
                canvasSize: canvasSize,
                backgroundImage: backgroundImage,
                previewSize: previewSize
            )
            guard gen == self.backgroundGeneration else { return }
            self.previewBackgroundImage = result
        }
    }

    func updatePanelPreview(...) {
        panelGeneration += 1
        let gen = panelGeneration
        panelPreviewTask?.cancel()
        panelPreviewTask = Task { [weak self, assembler, crop, cgImage, panelSize, panelId] in
            guard let self else { return }
            let result = await assembler.renderPanel(
                crop: crop,
                cgImage: cgImage,
                panelSize: panelSize
            )
            guard gen == self.panelGeneration else { return }
            self.panelRenderedImages[panelId] = result
        }
    }

    func updateTitleImage(...) {
        titleGeneration += 1
        let gen = titleGeneration
        titleTask?.cancel()
        titleTask = Task { [weak self, assembler, titleAttrString, titleStyle, canvasSize] in
            guard let self else { return }
            let result = await assembler.renderTitle(
                titleAttrString: titleAttrString,
                titleStyle: titleStyle,
                canvasSize: canvasSize
            )
            guard gen == self.titleGeneration else { return }
            self.titleImage = result
        }
    }

    func clearAll() {
        // ... existing task cancellation ...
        previewGeneration = 0
        backgroundGeneration = 0
        panelGeneration = 0
        titleGeneration = 0
    }

    func cancelAll() {
        // ... existing task cancellation ...
        // Don't reset generations — they're still valid for the next render
    }
}
```

**Note on `updateAllPanelPreviews`**: This method calls `updatePanelPreview` in a loop. Each call increments `panelGeneration`, so only the last panel's render will have a matching generation. This is a bug — we need per-panel generation tracking, or we need to handle `updateAllPanelPreviews` differently.

**Fix**: Track generation per panel ID:

```swift
private var panelGenerations: [UUID: Int] = [:]

func updatePanelPreview(...) {
    panelGenerations[panelId, default: 0] += 1
    let gen = panelGenerations[panelId]!
    panelPreviewTask?.cancel()
    panelPreviewTask = Task { [weak self, assembler, crop, cgImage, panelSize, panelId, gen] in
        guard let self, gen == self.panelGenerations[panelId] else { return }
        let result = await assembler.renderPanel(...)
        guard gen == self.panelGenerations[panelId] else { return }
        self.panelRenderedImages[panelId] = result
    }
}
```

This ensures each panel has its own generation counter. `updateAllPanelPreviews` increments each panel's counter independently, and all renders will match.

#### Test changes

- `CollageAssemblerTests.swift` — Concurrent tests remain valid. May add a new test for generation-based stale discard.
- `PreviewManagerTests.swift` — `rapidPreviewUpdatesCancelPrevious` test may need adjustment since we're now using generation counters instead of task cancellation alone.
- `CollagePerformanceTests.swift` — May need to account for generation tracking in assertions.

**Expected impact**: Stale renders are produced (wasted CPU) but discarded at the caller level before updating UI state. Combined with Phase 2's non-blocking queue entry, the UI only ever shows the latest result. The "catch up" lag is eliminated because stale frames don't overwrite fresh ones.

---

## Files Modified

| File | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| `CollageMaker/Services/CollageAssembler.swift` | — | ✅ async protocol + impl | ✅ RenderScheduler |
| `CollageMaker/Services/PreviewManager.swift` | ✅ render strategy | ✅ await callers | ✅ generation tracking |
| `CollageMaker/Services/RenderScheduler.swift` | — | — | ✅ new file |
| `CollageMaker/ViewModel/CollageViewModel.swift` | ✅ isLayeredMode | — | — |
| `CollageMaker/ViewModel/ExportManager.swift` | — | ✅ await | — |
| `CollageMaker/Views/CollageEditorView.swift` | ✅ mode check | — | — |
| `CollageMakerTests/CollageViewModelTests.swift` | — | ✅ async mocks | — |
| `CollageMakerTests/ExportFlowTests.swift` | — | ✅ async mocks | — |
| `CollageMakerTests/PreviewManagerTests.swift` | — | ✅ async mocks | ✅ gen tests |
| `CollageMakerTests/CollageAssemblerTests.swift` | — | ✅ async tests | — |
| `CollageMakerTests/CollagePerformanceTests.swift` | ⚠️ may need update | ⚠️ may need update | ⚠️ may need update |

---

## Verification

After each phase:
1. `xcodebuild build -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64'` — compiles
2. `xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests` — all tests pass
3. `bash script/build_and_run.sh run` — app launches, no crashes
4. Manual test — pan/zoom/font slider feel responsive, no visible lag

After all 3 phases:
5. Manual stress test — rapid slider drags, scroll-wheel panning, pinch gestures — preview updates track the gesture in real-time with no "catch up" delay

## Risks

- **`NSGraphicsContext.current` thread safety**: The serial queue protects against concurrent context corruption. Phase 2 and 3 change from `sync` to `async` submission, but the queue remains serial. No additional risk.
- **Cancellation race**: `Task.cancel()` + generation counter provides double protection. If the task is cancelled, it won't resume. If it resumes but is stale, the generation check discards it.
- **Test timing**: Tests that use `try? await Task.sleep(for: .milliseconds(200))` to wait for renders may need adjustment if async behavior changes timing characteristics.
