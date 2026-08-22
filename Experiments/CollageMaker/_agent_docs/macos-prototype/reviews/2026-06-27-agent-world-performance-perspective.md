# CollageMaker Performance Perspective — Live, Responsive Workflow Review

**Date:** 2026-06-27  
**Author:** Agent World Performance Review  
**Project:** CollageMaker macOS SwiftUI Desktop App  

---

## Executive Summary

This review evaluates the CollageMaker project from a systems perspective, focusing on live, responsive workflow for collage making, performance optimization for real-time updates, testing strategies to ensure responsiveness and performance, and user experience considerations for a "live" collage editing experience.

The app has strong foundational patterns in place:
- **`@MainActor @Observable CollageViewModel`** as the single source of truth
- **Actor-based `SaliencyAnalyzer`** leveraging Vision framework GPU acceleration
- **Generation counters in `PreviewManager`** to prevent stale async rendering tasks from overwriting newer results
- **Debouncer pattern with `FrameTempo` constants** for gesture preview throttling

However, several systemic issues could present performance regressions or poor user experience scenarios that developers might overlook when implementing new features:

1. **Memory leak via retain cycle** between `CollageViewModel` and `ImageCoordinator`
2. **O(N) linear searches during live gestures** causing UI stutter during pan/pinch/overlay-crop operations
3. **Repeated `cgImage(forProposedRect:...)` extraction** without caching, wasting CPU cycles
4. **Gesture priority conflicts with overlapping hit regions** requiring preemptive exclusion patterns
5. **Throttled @Observable invalidation gaps** between per-frame notification and actual image rendering

---

## 1. Live, Responsive Workflow for Collage Making

### Current State: Throttling Architecture

The project uses a sophisticated timing architecture via `FrameTempo.swift`:

| Constant | Duration | Typical Use |
|----------|----------|-------------|
| `scrollRenderInterval` | 20ms | Gesture render throttle (~50fps) |
| `overlayRenderInterval` | 20ms | Overlay render throttle (~50fps) |
| `panPreviewDebounce` | 20ms | Pan gesture preview debounce |
| `pinchPreviewDebounce` | 13ms | Pinch gesture preview debounce (~77fps) |
| `overlayRenderDebounce` | 20ms | Overlay render debounce |
| `scrollPanPreviewDebounce` | 20ms | Scroll pan preview debounce |
| `layoutChangeDebounce` | 20ms | Post-interaction layout change debounce |
| `backgroundColorDebounce` | 20ms | Background color debounce |
| `fontSizeDebounce` | 6ms | Font size debounce (~167fps) |
| `previewRenderDebounce` | 20ms | Full preview render debounce |

### Recommendations for Live Workflow

#### 1.1 Separate Throttling from Debouncing for @Observable Invalidation

**Issue:** The current architecture throlls/debounces *image rendering* but the `@Observable` property invalidation (like `cropMapVersion`) may still fire per-frame during high-rate gestures, causing unnecessary SwiftUI view re-evaluation cascades.

**Pattern to implement (from learnings):**
```swift
private var lastNotifyTime: ContinuousClock.Instant = ContinuousClock.now
private let notifyInterval: Duration = .milliseconds(30) // ~33fps for live feedback

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        // Invalidate @Observable properties here
    }
}
```

**Why this matters:** SwiftUI's `@Observable` re-evaluation is expensive. Throttling the *notification* frequency (not just the render) ensures live visual feedback without per-frame overhead during active gestures.

#### 1.2 Gesture Priority with Preemptive Exclusion

**Issue:** When multiple `simultaneousGesture` handlers on the same view have overlapping hit regions (e.g., title overlay vs panel drag), setting an `isDraggingTitle` flag in one handler doesn't propagate to the other handler's `onChanged` until the next render cycle. Both handlers run in the same pass with stale state.

**Pattern to implement:**
```swift
// Lower-priority gesture checks higher-priority region first
.simultaneousGesture(
    DragGesture(minimumDistance: 5)
        .onChanged { value in
            // Preemptive exclusion: bail if drag started on higher-priority region
            if let highPriorityFrame = highPriorityRegion,
               highPriorityFrame.contains(value.startLocation) {
                return
            }
            // Normal hit-test for this gesture's region
            if let id = hitTest(value.startLocation) {
                // ... lock and handle
            }
        }
)
```

**Why this matters:** Without preemptive exclusion, clicking on the title overlay also triggers the panel drag-to-reorder gesture underneath, causing confusing user experience.

#### 1.3 Detail Panel ScrollView for Control Overflow Prevention

**Issue:** The detail pane stacks `PanelCropEditor` and `ExportPanel` vertically. With gradient background controls (two color wells, labels, angle slider) and export button, the content can flow off-screen at small window sizes or when panel editor is visible.

**Recommendation:** Wrap detail content in `ScrollView`:
```swift
private var detail: some View {
    ScrollView {
        VStack(spacing: 24) {
            if let selectedId = viewModel.selectedPanelId,
               let panel = viewModel.panels.first(where: { $0.id == selectedId }) {
                PanelCropEditor(panel: panel, viewModel: viewModel)
                    .id(panel.id)
            }

            ExportPanel(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
```

---

## 2. Performance Optimization for Real-Time Updates

### Current State: CPU Hot Spots Identified

From Time Profiler and performance instrumentation learnings:
- **`CollageAssembler.drawPanels` is the CPU hot spot** during heavy scrolling with many images
- Each scroll delta triggers a full `updatePreview()` which re-composites all panels
- The debounced preview in `applyPanLive()` (20ms) helps, but synchronous calls still occur

### Recommendations for Performance Optimization

#### 2.1 Fix Retain Cycle: CollageViewModel ↔ ImageCoordinator

**Issue:** In `ImageCoordinator.swift`, there is a property:
```swift
@MainActor
final class ImageCoordinator {
    var target: ImageCoordinationTarget! // Strong reference, implicitly-unwrapped optional
}
```

And in `CollageViewModel.init`:
```swift
self.imageCoordinator = ImageCoordinator(...)
imageCoordinator.target = self // Creates retain cycle
```

CollageViewModel strongly owns `imageCoordinator`, and `ImageCoordinator` strongly owns its `target`. This creates a retain cycle that will cause memory to leak over time, especially if the app supports multiple documents or windows.

**Fix:** Change the target property in `ImageCoordinator`:
```swift
@MainActor
final class ImageCoordinator {
    weak var target: (any ImageCoordinationTarget)? // Changed to weak and non-optional
    
    // Ensure you call target methods safely using `target?.method()` instead of `target.method()`
}
```

#### 2.2 Eliminate O(N) Linear Searches in Panel Lookups

**Issue:** In `CollageViewModel.updatePanelPreview(panelId:)`, there is an O(N) linear search over the panels array:
```swift
func updatePanelPreview(panelId: UUID) {
    guard let panel = panels.first(where: { $0.id == panelId }), // <-- O(N) linear scan
          let crop = cropMap[panelId] else { return }
    // ...
}
```

Similarly, in `ImageCoordinator.getEffectiveImageIndex(for:)`:
```swift
guard let panelIndex = layoutManager.panels.firstIndex(where: { $0.id == panelId }) else { return nil }
```

These methods are called frequently during pan, pinch, and overlay-crop gestures. Scanning the panels array repeatedly causes UI stutter and wasted CPU cycles.

**Fix:** Add an O(1) dictionary lookup in `LayoutManager`:
```swift
// In LayoutManager:
var panelById: [UUID: ImagePanel] {
    Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
}

// Or maintain it as a cached property that updates on layout regeneration:
private var _panelById: [UUID: ImagePanel]?

func invalidatePanelCache() {
    _panelById = nil
}

var panelById: [UUID: ImagePanel] {
    if let cached = _panelById { return cached }
    let dict = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
    _panelById = dict
    return dict
}
```

#### 2.3 Cache Extracted CGImage for Background Images

**Issue:** In both `CollageViewModel.updatePreview()` and `exportCollage()`, the background image's CGImage is extracted repeatedly:
```swift
let backgroundImageCG = backgroundManager.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
// ...
let bgCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
```

If the background image hasn't changed, this recomputation wastes CPU cycles. The `cgImage(forProposedRect:..., context:, hints:)` call on `NSImage` is expensive.

**Fix:** Cache the extracted CGImage inside `BackgroundManager`:
```swift
class BackgroundManager {
    private var _cachedBackgroundImageCG: CGImage?
    private var backgroundImageVersion: Int = 0
    
    var backgroundImage: NSImage? {
        didSet {
            if oldValue !== backgroundImage {
                _cachedBackgroundImageCG = nil
                backgroundImageVersion += 1
            }
        }
    }
    
    func getCachedBackgroundCGImage() -> CGImage? {
        guard let image = backgroundImage else { return nil }
        
        // Check if we need to re-extract (version check or cache miss)
        // Implementation depends on how NSImage identity is tracked
        
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        _cachedBackgroundImageCG = cgImage
        return cgImage
    }
}
```

#### 2.4 CoreGraphics Compositing vs. Metal / CoreImage Offloading

**Issue:** The `CollageAssembler` uses CoreGraphics (`PanelRenderer.drawPanels`, `OverlayRenderer.drawOverlay`) for compositing panels, overlays (like double exposure masks, diagonal slices, hexagonal tiling), and titles. While Quartz/CoreGraphics is hardware-accelerated on macOS, custom `CGPath` creation and repeated `context.clip()` operations for complex layouts can become CPU-bound bottlenecks when there are many panels.

**Recommendation:** If you notice high CPU usage during layout regeneration or preview assembly with many panels:
- Consider offloading the compositing of overlays and masks to **CoreImage filters** or a custom **Metal shader** (using `MTLTexture` and `MTLRenderCommandEncoder`)
- Metal is highly optimized for parallel pixel operations and complex masking

Note: The Vision framework saliency analysis (`SaliencyAnalyzer`) is already GPU-accelerated via MPS/CoreML under the hood, so this part of the codebase is well-optimized.

---

## 3. Testing Strategies to Ensure Responsiveness and Performance

### Current State: Testing Patterns Identified

The project has several testing patterns in place:
- **`TrackingAssembler` mock pattern** for testing ViewModel behavior without running the CoreGraphics pipeline
- **Static methods on `CropManager` for coordinate math** allowing testability outside `@MainActor` isolation
- **Pure `CoordinateConverter` struct** with static methods for independent testing

### Recommendations for Testing Strategies

#### 3.1 Async Task Completion Patterns in ViewModel Tests

**Issue:** `CollageViewModel.updatePreview()` runs `assembler.assemblePreviewWithCGImages` inside a detached task or background work. The test process exits its synchronous assertions before the task completes, so mock tracking fields are still at their initial values.

**Fix pattern (from learnings):**
```swift
// Add await for pending tasks after calling ViewModel methods that spawn async work
await viewModel.awaitPendingTasks()

// Or use Task.sleep as a fallback in tests:
try? await Task.sleep(nanoseconds: 50_000_000) // 50ms yield
```

**Better alternative (for future):** Have `updatePreview()` return a `Task<Void, Never>` and have tests `await` it, or add a `previewCompletion: CheckedContinuation?` pattern. The sleep approach works for mocks but would be unreliable with real CoreGraphics rendering.

#### 3.2 Mock Method Symmetry for Protocol Conformance

**Issue:** When the `CollageAssembly` protocol has multiple methods (`assembleWithCGImages` for export, `assemblePreviewWithCGImages` for preview), the `TrackingAssembler` mock must track fields on **every method the ViewModel actually calls**. The original mock only populated tracking data in one method but tests asserted on another.

**Fix:** Ensure all protocol methods that the ViewModel delegates to have corresponding tracking properties:
```swift
final class TrackingAssembler: CollageAssembly {
    var lastAssemblePanels: [ImagePanel]?
    var lastExportCanvasSize: CGSize?
    
    var lastPreviewPanels: [ImagePanel]?
    var lastPreviewCanvasSize: CGSize?
    
    func assembleWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, quality: Double) async -> Data? {
        lastAssemblePanels = config.layout.panels
        lastExportCanvasSize = config.canvasSize
        return Data()
    }
    
    func assemblePreviewWithCGImages(config: AssemblyConfig, cgImages: [CGImage?], backgroundImage: CGImage?, previewSize: CGSize) async -> NSImage? {
        lastPreviewPanels = config.layout.panels
        // ... track other preview-specific fields
        return nil
    }
}
```

#### 3.3 Testing Throttled @Observable Invalidation

**Issue:** When per-frame notification is deferred to a debounce callback, gesture-end paths that cancel the debounce (e.g., `finishOverlayCrop` calls `panelPreviewTask?.cancel()`) never fire the notification. This leaves `PanelCropEditor` showing stale crop data after the user releases.

**Fix pattern:** Add explicit notification to gesture-end methods:
```swift
func finishOverlayCrop(panelId: UUID) {
    debouncer.cancel(id: "overlayRender")
    
    // Ensure final state is visible - this was a gap identified in learnings
    throttledNotify() // or equivalent notify method
    
    updatePanelPreview(panelId: panelId)
}

func endScrollPan() {
    debouncer.cancel(id: "scrollPanPreview")
    
    // Explicit notification for gesture end
    throttledNotify()
    
    cropManager.endScrollPan()
}
```

#### 3.4 Coordinate Math Test Patterns

When writing tests for coordinate conversion (like `sourceRectInContainer` with `.aspectRatio(contentMode: .fit)` math):

- **Image wider than container** (landscape image, square container): constrains by width, letterboxes top/bottom
- **Image taller than container** (portrait image, square container): constrains by height, letterboxes left/right
- Always compute the fitted dimensions first, then the offset, then the mapped rect. Never assume which axis constrains.

Use `CoordinateConverter` pure struct with static methods for testable coordinate math outside `@MainActor` isolation:
```swift
struct CoordinateConverter {
    static func canvasToPreviewFrame(_ canvasFrame: CGRect, in previewSize: CGSize, canvasSize: CGSize) -> CGRect { ... }
    static func hitTestPanel(at location: CGPoint, panelFrames: [UUID: CGRect], ...) -> UUID? { ... }
}
```

---

## 4. User Experience Considerations for a "Live" Collage Editing Experience

### Current State: UX Patterns Identified

The project has several good UX patterns:
- **Generation counters in `PreviewManager`** to ignore stale async rendering tasks that complete out-of-order
- **Background export task** using `Task.detached` ensuring the main thread remains responsive during large file generation
- **OSLog with subsystem `austin183.indie.CollageMaker`** for structured logging and performance category

### Recommendations for UX Considerations

#### 4.1 Visual Feedback During Processing

**Recommendation:** Ensure the `isProcessing` indicator is visible during:
- Saliency analysis (already handled via `Task { await analyzeSaliency() }`)
- Layout regeneration after adding/removing images
- Export operations

The current `isProcessing` computed property (`var isProcessing: Bool { processingCount > 0 }`) with `beginProcessing()`/`endProcessing()` pattern is good, but ensure UI elements (like a progress indicator or disabled state) respond to this flag.

#### 4.2 Search and Filtering for Images at Scale

**Issue:** At 40+ images, finding a specific image by name requires scrolling through text-only rows.

**Recommendation — Add searchable modifier to sidebar:**
```swift
@State private var searchQuery = ""

private var filteredImages: [(index: Int, item: ImageItem)] {
    if searchQuery.isEmpty {
        return viewModel.images.enumerated().map { ($0.offset, $0.element) }
    } else {
        return viewModel.images.enumerated()
            .filter { $0.element.filename.localizedCaseInsensitiveContains(searchQuery) }
            .map { ($0.offset, $0.element) }
    }
}

// Then in the sidebar:
.searchable(text: $searchQuery, prompt: "Search images")
```

Note: The index shown in the row should be the original index (for hero selection), not the filtered position.

#### 4.3 Thumbnail Identification in Sidebar and Pickers

**Recommendation — Add thumbnails to sidebar rows:**
Small thumbnails (32x32) with filenames give users visual identification without losing the `Form`'s native section headers, grouped styling, and macOS-native scrollbar behavior.

**Recommendation — Horizontal thumbnail strip for hero picker:**
Replace menu-style pickers with a horizontally scrolling thumbnail strip when hero layout is active, giving visual identification and tap-to-select without consuming excessive vertical sidebar space.

#### 4.4 Warning When Images Are Dropped in Mosaic Layout

**Issue:** The mosaic layout has `maxSplits = min(numImages, 12)`, so only 12 of 40 images appear in the collage. The remaining 28 are silently discarded with no user indication.

**Recommendation — Add status message when panels.count < images.count:**
```swift
if viewModel.panels.count < viewModel.images.count {
    Section("Notice") {
        Label(
            "Only \(viewModel.panels.count) of \(viewModel.images.count) images are in the layout",
            systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.yellow)
        .font(.caption)
    }
}
```

---

## Summary of Priority Recommendations

| Priority | Category | Issue | Impact |
|----------|----------|-------|--------|
| **P0** | Performance/Memory | Retain cycle: CollageViewModel ↔ ImageCoordinator | Memory leak over time, especially with multiple documents/windows |
| **P0** | Performance | O(N) linear searches in panel lookups during gestures | UI stutter during pan/pinch/overlay-crop operations |
| **P1** | UX/Live Workflow | Gesture priority conflicts with overlapping hit regions | Clicking title overlay triggers panel drag underneath |
| **P1** | Performance | Repeated cgImage(forProposedRect:...) extraction without caching | Wasted CPU cycles during preview/export cycles |
| **P2** | Testing/Responsiveness | Async task completion patterns in ViewModel tests | Test flakiness, false negatives for mock tracking |
| **P3** | UX/Live Workflow | Detail panel controls flowing off-screen | Export button or gradient controls inaccessible at small window sizes |
| **P3** | UX/Discoverability | No search/filtering for images at scale | Finding specific images requires manual scrolling |
| **P3** | UX/Clarity | Mosaic layout silently drops images beyond 12 | Users unaware their extra images aren't in the collage |

---

## Conclusion

The CollageMaker project has strong foundational patterns and a solid architectural base. The `@Observable @MainActor` view model, actor-based services, generation counters for stale task prevention, and debouncer/throttle architecture with `FrameTempo` constants all demonstrate thoughtful design for a live collage editing experience.

By addressing the P0 issues (retain cycle and O(N) panel lookups), implementing preemptive exclusion for gesture priority conflicts, and ensuring throttled @Observable invalidation doesn't leave gaps in gesture-end paths, the project can provide a consistently responsive and enjoyable live collage making workflow.

The testing strategies outlined—particularly around async task completion patterns, mock method symmetry, and coordinate math testability—will help prevent performance regressions as new features are implemented or bugs are fixed.
