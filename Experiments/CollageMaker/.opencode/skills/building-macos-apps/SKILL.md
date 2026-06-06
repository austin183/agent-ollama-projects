---
name: building-macos-apps
description: Develop macOS SwiftUI desktop applications with image processing, Vision framework analysis, CoreGraphics compositing, window management, commands, settings, and desktop conventions. Use when building macOS apps that manipulate images, run ML analysis, produce visual output, work with Apple graphics frameworks, or need macOS-specific UI patterns like scenes, inspectors, toolbars, and menu bar extras.
---
# SwiftUI macOS App Development

Guidance for building macOS SwiftUI desktop applications with image processing, ML analysis, and graphics compositing.

## Reference Files

### UI Patterns

| Topic | Reference |
|-------|-----------|
| **Split Views and Inspectors** | [references/ui/split-inspectors.md](references/ui/split-inspectors.md) |
| **SwiftUI Overlay Patterns** | [references/ui/swiftui-overlays.md](references/ui/swiftui-overlays.md) |
| **Scroll Views** | [references/ui/scroll-views.md](references/ui/scroll-views.md) |
| **CGRect Equality and Lookup** | [references/ui/cgrect-equality-crop-lookup.md](references/ui/cgrect-equality-crop-lookup.md) |
| **File Input (Drag-Drop, PhotosPicker, Panels)** | [references/ui/file-input.md](references/ui/file-input.md) |
| **File Export and Import** | [references/ui/file-export-import.md](references/ui/file-export-import.md) |

### Gestures

| Topic | Reference |
|-------|-----------|
| **SwiftUI Gestures (Core APIs)** | [references/gestures/swiftui-gestures.md](references/gestures/swiftui-gestures.md) |
| **Gesture Targeting (Per-Panel Hit Testing)** | [references/gestures/gesture-targeting.md](references/gestures/gesture-targeting.md) |
| **Resize Handles (Edge & Corner)** | [references/gestures/resize-handles.md](references/gestures/resize-handles.md) |
| **Drag and Drop** | [references/gestures/drag-and-drop.md](references/gestures/drag-and-drop.md) |

### AppKit Interop

| Topic | Reference |
|-------|-----------|
| **NSViewRepresentable** | [references/appkit/nsviarepresentable.md](references/appkit/nsviarepresentable.md) |
| **AppKit Interop (Bridging)** | [references/appkit/appkit-interop.md](references/appkit/appkit-interop.md) |
| **NSTextView Binding** | [references/appkit/nstextview-binding.md](references/appkit/nstextview-binding.md) |
| **NSColorWell** | [references/appkit/nscolorwell.md](references/appkit/nscolorwell.md) |
| **NSAttributedString Drawing** | [references/appkit/nsattributedstring-drawing.md](references/appkit/nsattributedstring-drawing.md) |
| **Codable AppKit Types** | [references/appkit/codable-appkit.md](references/appkit/codable-appkit.md) |

### State Management

| Topic | Reference |
|-------|-----------|
| **@Observable, @Bindable (macOS 14+)** | [references/state/observable-bindable.md](references/state/observable-bindable.md) |
| **@Published, Combine, State, Input (legacy)** | [references/state/combine-published.md](references/state/combine-published.md) |
| **FocusedValues (Cross-View Communication)** | [references/state/focused-values.md](references/state/focused-values.md) |
| **Swift Concurrency** | [references/state/swift-concurrency.md](references/state/swift-concurrency.md) |

### Graphics and Vision

| Topic | Reference |
|-------|-----------|
| **Coordinate System Traps** | [references/graphics/coordinate-systems.md](references/graphics/coordinate-systems.md) |
| **CoreImage, CoreGraphics, Compositing** | [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md) |
| **Vision API Details** | [references/graphics/vision-api-details.md](references/graphics/vision-api-details.md) |
| **vImage Processing** | [references/graphics/vimage-processing.md](references/graphics/vimage-processing.md) |
| **CoreText Background Rendering** | [references/graphics/coretext-background-rendering.md](references/graphics/coretext-background-rendering.md) |

### Testing

| Topic | Reference |
|-------|-----------|
| **Testing Patterns** | [references/testing/testing-patterns.md](references/testing/testing-patterns.md) |

### Desktop Conventions and HIG

| Topic | Reference |
|-------|-----------|
| **Desktop Conventions (Rules, Anti-Patterns, Workflows)** | [references/conventions/desktop-conventions.md](references/conventions/desktop-conventions.md) |
| **HIG: Accessibility** | [references/conventions/hig-accessibility.md](references/conventions/hig-accessibility.md) |
| **HIG: Alerts and Feedback** | [references/conventions/hig-alerts-feedback.md](references/conventions/hig-alerts-feedback.md) |
| **HIG: Keyboard Shortcuts** | [references/conventions/hig-keyboard-shortcuts.md](references/conventions/hig-keyboard-shortcuts.md) |
| **HIG: Context Menus** | [references/conventions/hig-context-menus.md](references/conventions/hig-context-menus.md) |
| **HIG: Progress Indicators** | [references/conventions/hig-progress-indicators.md](references/conventions/hig-progress-indicators.md) |
| **HIG: Undo and Redo** | [references/conventions/hig-undo-redo.md](references/conventions/hig-undo-redo.md) |
| **HIG: Sidebars** | [references/conventions/hig-sidebars.md](references/conventions/hig-sidebars.md) |

### Tooling

| Topic | Reference |
|-------|-----------|
| **Scene Types (WindowGroup, Window, DocumentGroup)** | [references/tooling/windowing.md](references/tooling/windowing.md) |
| **Window Management (macOS 15+ modifiers)** | [references/tooling/window-management.md](references/tooling/window-management.md) |
| **Commands and Menus** | [references/tooling/commands-menus.md](references/tooling/commands-menus.md) |
| **Settings** | [references/tooling/settings.md](references/tooling/settings.md) |
| **Menu Bar Extras** | [references/tooling/menu-bar-extra.md](references/tooling/menu-bar-extra.md) |
| **Build, Run, Debug Scripts** | [references/tooling/build-and-run.md](references/tooling/build-and-run.md) |
| **Performance Debugging** | [references/tooling/performance-debugging.md](references/tooling/performance-debugging.md) |

## Project Structure

```
AppTarget/
  AppTargetApp.swift          # @main entry -- WindowGroup with defaultSize
  ContentView.swift           # Root view -- NavigationSplitView for sidebar+detail
  Assets.xcassets/
  Models/
    *.swift                   # Value types: structs with Identifiable, Equatable, Codable
  Services/
    *Analyzer.swift           # ML/heavy computation -- use `actor` for thread safety
    *Generator.swift          # Pure computation -- `struct` with `static func`
    *Assembler.swift          # Compositing/export -- `class` or `struct`
  ViewModel/
    *ViewModel.swift          # @MainActor @Observable class (macOS 14+) or ObservableObject with @Published (legacy)
  Views/
    *PickerView.swift         # Input: drag-drop, PhotosPicker, NSOpenPanel
    *EditorView.swift         # Main workspace with live preview
    *Panel.swift              # Controls: sliders, color pickers, export
```

## Apple Framework Mappings

| General Concept | Apple Framework | Purpose |
|---|---|---|
| Image loading/resizing | CoreGraphics + AppKit.NSImage | Load, resize, composite images |
| Attention/saliency ML | Vision VNGenerateAttentionBasedSaliencyImageRequest | Attention-based saliency detection |
| Face detection | Vision VNDetectFaceRectanglesRequest | Face rectangle detection |
| Pixel buffer ops | vImage (Accelerate) / CVPixelBuffer | Fast pixel buffer manipulation |
| Image blur | vImage tentConvolve / boxConvolve | Blurred background, soft effects |
| Dominant color extraction | vImage + BNNS k-means | Auto-match background color to image |
| File input | PhotosPicker + NSOpenPanel + .onDrop | Image/file selection |

## Coordinate System Traps

Vision, CoreGraphics, and NSImage use different origins. See [references/graphics/coordinate-systems.md](references/graphics/coordinate-systems.md) for conversion functions, EXIF mismatch fixes, canvas-to-preview mapping, normalized position storage, and the producer-tracing verification pattern.

**Critical mismatches:**
- Vision: bottom-left (0,0), normalized 0-1
- CoreGraphics CGContext: bottom-left (0,0)
- NSImage / SwiftUI: top-left (0,0)
- EXIF orientation corrections shift CGImage coordinates -- strip EXIF with `NSImage(cgImage:cgImage, size: .zero)`

**Before writing a coordinate conversion:** Trace the value to its producer. The producer's arithmetic is the source of truth — plan descriptions and variable names can be wrong about coordinate space. See [references/graphics/coordinate-systems.md](references/graphics/coordinate-systems.md) § "Verify Data Flow Before Adding Conversions".

## State Management

### @Observable (macOS 14+, preferred)

See [references/state/observable-bindable.md](references/state/observable-bindable.md).

**Critical rules:**
- **`@Observable` cannot track computed properties** -- all properties driving UI must be stored. Use `didSet` for `UserDefaults` persistence
- **Views must use `@Bindable var`** -- `let viewModel: MyViewModel` renders once and never updates
- Side effects (e.g., `updatePreview()`) must be called in `didSet`, not computed setters
- **Three-way didSet decomposition** — When a `didSet` has cache invalidation, undo registration, and preview rendering, decompose into independent concerns with separate guards. A single `guard ... else { return }` that skips all side effects for "non-important" changes will silently break color/background/attribute updates:

```swift
var titleStyle: TitleStyle = .default {
    didSet {
        // 1) Cache invalidation — only for layout-affecting changes
        if oldValue.layoutKey != titleStyle.layoutKey {
            cachedTitleMetrics = nil
        }

        // 2) Fast path — interaction-specific, returns early
        if isDraggingTitle {
            updateTitleImageLive()
            return
        }

        // 3) Full side effects — all non-drag changes
        undoManager.registerUndo(...)
        updatePreview()
        debouncedSave()
    }
}
```

- **@Bindable nested struct mutations bypass `didSet`** — Bindings like `$viewModel.titleStyle.backgroundColor` may use `withMutation` internally, skipping the parent property's `didSet`. Use explicit setter methods with `Binding(get:set:)` when side effects are required. See [references/state/observable-bindable.md](references/state/observable-bindable.md)
- **Cache key struct** — Use a dedicated `Hashable` struct for cache invalidation instead of manual tuple/hash comparison. Synthesizes conformance from `let` properties and documents which properties affect the cache. Compare with `oldValue.key != newValue.key` in `didSet`
- **`NSAttributedString.isEqual(_:)`** — When caching on attributed string content, use `isEqual(_:)` instead of comparing `.string`. The latter misses attribute changes (bold, italic, font swap)
- **Multi-field cache invalidation** — Every code path that clears a multi-field cache (result + key + input) must clear ALL fields. Leaving keys stale causes the cache to return stale `nil` on restore. Prefer defensive guard: `if let cachedResult = cachedResult, ...`. See [references/state/observable-bindable.md](references/state/observable-bindable.md)
- **Gesture hot path caching** — `@Observable` has no path-based granularity for computed properties. Cache expensive computation (CoreText layout) in ViewModel method; keep cheap math (frame from position) in computed property. Position changes during drag reuse cached result. See [references/state/observable-bindable.md](references/state/observable-bindable.md)

### @ObservableObject (legacy, still valid)

See [references/state/combine-published.md](references/state/combine-published.md).

**Critical rules:**
- **Never** store reference types in `@State` -- lost silently on re-render
- **Never** use `@ObservedObject` as stored property with `@MainActor` ViewModel -- use `@EnvironmentObject`
- `@Published` only fires on **property assignment**, not in-place element mutation
- Use `.id()` on conditionally shown views to stabilize identity
- **Prefer `.onReceive(publisher.dropFirst())`** over `.onChange(of:)` for reacting to `@Published` changes

## Codable AppKit Types

Several AppKit types don't conform to `Codable`. See [references/appkit/codable-appkit.md](references/appkit/codable-appkit.md) for:
- `NSColor` via `NSKeyedArchiver` with custom `encode`/`init(from:)`
- Backward-compatible `decodeIfPresent` for new model fields
- `NSTextAlignment` via `rawValue`
- Permutation-based content reordering with `[Int]` arrays
- Persisting to `UserDefaults` with `@Observable` + `didSet`

**Critical:** Keep `Codable` on struct declaration only. Put custom `encode`/`init(from:)` in an extension **without** re-declaring `: Codable`.

## Concurrency Patterns

See [references/state/swift-concurrency.md](references/state/swift-concurrency.md).

**Key patterns:**
- `Task { [weak self] }` -- inherits MainActor, use for ViewModel updates
- `Task.detached` -- off MainActor, use for heavy computation
- **`Task { [weak self] in let result = await Task.detached { ... }.value; self.prop = result }`** -- preferred pattern for @Observable state updates from background work. Cancellation propagates, no manual actor hop needed. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md)
- **`withCheckedContinuation` + `queue.async`** -- when a serial `DispatchQueue` is needed for thread safety (e.g., `NSGraphicsContext.current`), expose `async` protocol methods that bridge the queue. Non-blocking, simpler callers. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md)
- `defer { isProcessing = false }` -- always reset processing state
- Cancel previous `Task` before starting new one
- **Extract `CGImage`/`CGColor` on main thread before `Task.detached`** -- AppKit types are not thread-safe
- **Capture `NSAttributedString` as `let` before `Task.detached`** -- not `Sendable`, same pattern as `NSColor`
- **Computed properties on structs crossing actor boundaries evaluate on the destination thread** -- A computed `var cgColor: CGColor { nsColor.cgColor }` on a struct captured by `Task.detached` will call `.cgColor` on the background thread. Store the derived value at init time instead: `let cgColor: CGColor` assigned in `init` on MainActor. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md)
- **`NSGraphicsContext.current` is NOT thread-safe** -- concurrent `Task.detached` rendering tasks can clobber each other's context. Mitigate with a serial `DispatchQueue`. See [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md)
- **Background thread text rendering** — `NSAttributedString`/`NSMutableAttributedString` require AppKit and are not thread-safe. For `CTFrameDraw` on a background thread, use CoreFoundation C API (`CFAttributedStringCreateMutable`, `CFAttributedStringSetAttribute` with `kCTFontAttributeName`, etc.). See [references/graphics/coretext-background-rendering.md](references/graphics/coretext-background-rendering.md)
- **`@unchecked Sendable` on model types** -- safe when non-Sendable AppKit properties (NSColor, NSAttributedString) are only accessed on a known thread. Document the justification. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md)
- **Synchronous dispatch closures can't `await`** -- `RenderScheduler.render { }` takes a synchronous closure. `await` is a compile error. Mutating captured `var` fails Swift 6. Use `ThreadSafeArray` with `NSLock` + `@unchecked Sendable` for mutable state. Use `Thread.sleep(forTimeInterval:)` not `Task.sleep`. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md)

## Swift Compilation Gotchas

- **Same-file extension ordering:** Swift compiles each `.swift` file as a separate compilation unit. Within a single file, an `extension` on a type from another file cannot reference types defined later in the same file. Place the extension **after** any local types it references, or move the extension to the extended type's own file (cross-file references have no ordering constraint).

## Finder Drag Gotcha

Finder drag payloads send `public.file-url`, not the content type. See [references/gestures/drag-and-drop.md](references/gestures/drag-and-drop.md) for the extraction pattern.

**Key points:**
- Accept `UTType.fileURL.identifier` for Finder drags
- `NSItemProvider` payload can be `Data` (UTF-8 URL string) or `NSURL` -- handle both
- Validate file extension after extraction

## Image Processing Pipeline

```
NSImage -> CGImage -> VNImageRequestHandler -> ML observations
-> cgImage.cropping(to:) -> CGContext.draw() -> context.makeImage()
-> NSBitmapImageRep -> .representation(using: .jpeg) -> Data.write(to:)
```

## Vision Framework

See [references/graphics/vision-api-details.md](references/graphics/vision-api-details.md).

**Key points:**
- Use `actor` for thread-safe async isolation
- Use legacy API (`VN`-prefixed) for macOS 13.0+ compatibility
- Saliency heat map is 68x68 `CVPixelBuffer` of `Float` values
- Always pass `cgImage.imageOrientation` to `VNImageRequestHandler`

## vImage Processing

See [references/graphics/vimage-processing.md](references/graphics/vimage-processing.md).

**Quick reference:**
- **Blurred background:** `tentConvolve(kernelSize: 31)` -- best speed/quality balance
- **Fastest blur:** `boxConvolve(kernelSize: 31)` -- stack two passes for Gaussian quality
- **Dominant color:** k-means with BNNS `argMin` + vDSP `gather`/`mean` -- scale to 64x64 first
- Always run on background queue; cache results per-image

## CoreGraphics Compositing

See [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md).

**Key points:**
- `bytesPerRow: 0` lets system calculate it
- `interpolationQuality = .high` for resize quality
- Use `NSAttributedString.draw(at:)` for text, not deprecated CGContext text API

## Gesture Patterns

See [references/gestures/swiftui-gestures.md](references/gestures/swiftui-gestures.md) for comprehensive gesture targeting, composition, and coordinate space patterns.

**Key pitfalls:**
- **Per-region gesture targeting:** Parent-level gesture + `startLocation` hit-test on first `onChanged`. Do NOT use `.simultaneousGesture` on per-panel ZStack overlays
- **`MagnificationGesture` has no location** -- `Value` is `CGFloat` only. Target the selected panel
- **`MagnificationGesture` values are cumulative** -- use `baseZoom / magnification` (division), NOT multiplication
- **Dynamic zoom bounds** -- compute zoom-out limit from content: `min(imageW/panelW, imageH/panelH)`. Never hardcode — see [references/gestures/swiftui-gestures.md](references/gestures/swiftui-gestures.md)
- **No `.onStarted`** -- Use `@State` flag in first `onChanged`
- **Live preview:** Use `finish: Bool` parameter + cancel stale `Task.detached` with `previewTask?.cancel()`
- **Canvas is NOT suitable** for interactive elements
- **Corner resize aspect ratio:** Use dominant-dimension pattern — compare `rawW / rawH` to target aspect ratio, derive the other dimension. Use `min`/`abs` for uniform bounding box across all four corners
- **CG-rendered gesture preview:** Never use SwiftUI `Text` as a live overlay for `NSAttributedString.draw` content — different font engines produce different metrics. Debounce the CG render at ~150ms on the specific layer instead.

## Scroll Views

See [references/ui/scroll-views.md](references/ui/scroll-views.md).

**Key decisions:**
- **Canvas panning is NOT a scroll operation** -- use raw `scrollWheel(with:)` on `NSView` overlay
- **Snapping:** `.scrollTargetBehavior(.viewAligned)` + `.scrollTargetLayout()` for thumbnail strips
- **Avoid same-orientation nesting** -- HIG explicitly warns against this

## CGRect Equality

See [references/ui/cgrect-equality-crop-lookup.md](references/ui/cgrect-equality-crop-lookup.md).

**Problem:** `CGRect ==` uses exact equality -- computed `CGFloat` values from layout division have precision errors.
**Solution:** Add `id: UUID` to layout items, use `[UUID: Item]` dictionary for O(1) access.

## File Export and Import

See [references/ui/file-export-import.md](references/ui/file-export-import.md) for `.fileExporter` with `ReferenceFileDocument` and `.importsItemProviders` patterns.

## FocusedValues

See [references/state/focused-values.md](references/state/focused-values.md) for communicating selection state from detail views to menu bar commands without binding traversal.

## SwiftUI Overlay Patterns

See [references/ui/swiftui-overlays.md](references/ui/swiftui-overlays.md) for eoFill cutout overlays and fixed container image previews.

## Version Requirements

| Feature | Minimum macOS |
|---|---|
| PhotosPicker, NavigationSplitView | 13.0 (Ventura) |
| Vision legacy API (VNGenerate...) | 10.13 (High Sierra) |
| Vision new Swift API (Generate...) | 15.0 (Sequoia) |
| .onDrop | 11.0 (Big Sur) |
| vImage Swift API (PixelBuffer, convolve) | 13.3 |
| BNNS Swift bindings (k-means) | 14.0 (Sonoma) |
| Transferable API (draggable, dropDestination) | 15.0 (Sequoia) |

## Performance Notes

- Vision analysis: 50-200ms per image (faster on Apple Silicon with Neural Engine)
- CGContext drawing at 1920x1080: < 100ms per element
- JPEG export at 0.92 quality: ~500KB-2MB
- Process images concurrently with `withThrowingTaskGroup`
- **CGImage caching** -- Extract `CGImage` from `NSImage` once at load time. Repeated `nsImage.cgImage(forProposedRect:)` calls are expensive
- **Background preview rendering** -- Move heavy CoreGraphics work to `Task.detached` with captured values, dispatch results back with `Task { @MainActor in self?.previewImage = result }`. Cancel stale tasks before starting new ones.
- **No computed NSImage in body** -- Never create `NSImage(cgImage:size:)` in a computed property accessed from `body`. SwiftUI calls `body` frequently during layout, allocating a new `NSImage` per render cycle. Pass as a stored `let` parameter from the parent view.
- **Never clear rendered state before async replacement** -- If a view depends on `someDict.isEmpty` to choose between rendering modes, clearing that dict before the async replacement arrives creates a blank frame. Keep stale content visible during the gap, then repopulate.
- **Multiple async rendering tasks race** -- When `updatePreview()`, `updateBackground()`, and `updatePanelPreview()` all run on separate `Task.detached` tasks, there's no ordering guarantee. If rendering mode depends on which task completed first, the mode can flip unpredictably during rapid interactions.
- **Composite-to-layered rendering transition** -- When splitting a full composite into individual layers, every element baked into the composite needs its own rendering path. Elements without a dedicated layer become invisible in layered mode. Render each element (title, panels, effects) separately and compose in a ZStack.
- **Property-level debounce for rapid controls** -- Slider and color picker `didSet` observers fire 30-60x/sec during drag. Use a debounced render method (cancel previous task, sleep 150ms, render) for continuous controls. Discrete controls (typing, enum picker, image selection) render immediately. Rule of thumb: >10 events/sec = debounce. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md) for cross-boundary cancellation pattern.
- **Throttled `@Observable` invalidation** -- When a version counter triggers full view re-evaluation, throttle its increments during high-rate input (pan/zoom gestures). Throttle fires immediately on first event, then skips until interval elapses — preserving live feedback unlike debounce. Use `ContinuousClock` + `Duration`, never `mach_absolute_time()` (returns ticks, not nanoseconds):

```swift
private var lastNotifyTime: ContinuousClock.Instant = .now
private let notifyInterval: Duration = .milliseconds(30) // ~33fps

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        versionCounter += 1
    }
}
```

- **Gesture-end notification gap** -- When per-frame notification is deferred to a debounce callback, gesture-end paths (e.g., `onEnded`, `finish*`) that cancel the debounce task will never fire the notification. Add explicit notification calls in gesture-end methods to ensure final state is visible.
- **Dual-responsibility timer/task cleanup** -- When removing a timer or background task for performance, audit what else it did beyond its primary purpose. A timer that both commits accumulated state AND calls `endGesture()` (clearing `gestureActivePanelId`, etc.) will leave stale gesture state if only the commit is replaced. Move cleanup to the explicit gesture-end path.
- **Gesture-end task cancellation** -- When a gesture uses a background render task (e.g., `previewDebounceTask`), cancel it in `endGesture()`. A pending render can fire after gesture end and overwrite a subsequent gesture's result. Different gesture types use different task variables and won't cancel each other automatically.

### Main Thread Timing Budgets

| Interaction type | Budget | Exceeding causes |
|---|---|---|
| Discrete (tap, key press) | < 50ms main thread work | Hang (>100ms noticeable) |
| Continuous (scroll, drag, animation) at 60Hz | < 5ms per frame | Hitch (frame drop) |
| Continuous at 120Hz | < 5ms per frame | Hitch (frame drop) |

**Rule:** Main thread = UI work only. All computation, I/O, and networking goes to background. See [references/tooling/performance-debugging.md](references/tooling/performance-debugging.md) for Instruments templates, sanitizers, OSSignpost, and profiling workflows.

**Timing API:** Use `ContinuousClock.now` + `Duration` for time-based logic. `ContinuousClock.Instant` survives sleep/wake and `Duration.milliseconds(30)` is self-documenting. `mach_absolute_time()` returns clock **ticks** (not nanoseconds) — the tick-to-nanos ratio varies on Apple Silicon. Comparing against hardcoded nanosecond thresholds produces incorrect throttling.

## CLI Build and Launch

```bash
# Build
xcodebuild -project "App.xcodeproj" -scheme AppName \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build

# Launch (use glob for DerivedData hash)
open "$HOME/Library/Developer/Xcode/DerivedData/AppName-*/Build/Products/Debug/AppName.app"
```

- `NSUnbufferedIO=YES open ...` does not produce useful stdout for SwiftUI apps
- When debugging GUI behavior without app visibility, write ViewModel integration tests with real data

## HIG Quick Reference

| Topic | Reference |
|-------|-----------|
| Accessibility | [references/conventions/hig-accessibility.md](references/conventions/hig-accessibility.md) |
| Alerts and Feedback | [references/conventions/hig-alerts-feedback.md](references/conventions/hig-alerts-feedback.md) |
| Keyboard Shortcuts | [references/conventions/hig-keyboard-shortcuts.md](references/conventions/hig-keyboard-shortcuts.md) |
| Context Menus | [references/conventions/hig-context-menus.md](references/conventions/hig-context-menus.md) |
| Progress Indicators | [references/conventions/hig-progress-indicators.md](references/conventions/hig-progress-indicators.md) |
| Undo and Redo | [references/conventions/hig-undo-redo.md](references/conventions/hig-undo-redo.md) |
| Sidebars | [references/conventions/hig-sidebars.md](references/conventions/hig-sidebars.md) |

## Implementation Phases

1. **Models** -- Define data structs first (Identifiable, Equatable, Codable). Include `id: UUID` in layout items
2. **Services** -- Pure computation and framework wrappers (testable in isolation)
3. **ViewModel** -- `@MainActor @Observable` class (preferred) or `ObservableObject`. All properties driving UI must be stored; use `didSet` for persistence. When it reaches 3+ related async tasks or 3+ related properties for a subsystem, extract into a dedicated `@Observable` manager (pure accumulator pattern preferred)
4. **Views** -- UI components using `@Bindable` for `@Observable` state, or `@EnvironmentObject` for legacy
5. **App Wiring** -- Entry point with `.environmentObject(viewModel)` on root view
6. **Build Verification** -- Zero errors, zero warnings
7. **Tests** -- Unit tests for Services, integration tests for ViewModel with real data
8. **Manual Testing** -- CLI build + `open` to run with real input, verify end-to-end

## Debugging Strategy

When GUI behavior is unclear (agent cannot observe running app):

1. **Write ViewModel integration tests** with real data exercising the same code paths. If tests pass, the bug is in the view layer.
2. **Check state wrapper choices** -- `@State` with reference types, `@ObservedObject` stored properties, and missing `@EnvironmentObject` injection are the most common culprits
3. **Check @Observable property types** -- computed properties are invisible to `@Observable`. If a binding "works locally" but dependent views don't update, the property is likely computed. Also check that the view uses `@Bindable var`, not `let`
4. **Check @Observable delegation chains** -- If a computed property delegates to a sub-manager (e.g., `var cropMap { cropManager.cropMap }`), SwiftUI won't observe changes. Fix: make the delegate `@Observable` AND have views read the delegate directly (`vm.cropManager.cropMap`, not `vm.cropMap`). Both parts are required. Alternative: use a **version counter** -- private `Int` read in the computed getter, incremented at mutation sites -- to preserve abstraction.
5. **Check @Bindable nested struct mutations** -- If a binding like `$viewModel.titleStyle.backgroundColor` "works" (value changes) but side effects in `didSet` don't fire, the binding is likely bypassing the parent setter via `withMutation`. Fix: use explicit setter methods with `Binding(get:set:)`.
6. **Check for spurious undo entries at launch** -- `didSet` fires during `init` property assignment, registering unwanted undo actions and triggering redundant persistence. Use an `isInitializing` guard. See [references/state/observable-bindable.md](references/state/observable-bindable.md)
7. **Check `.onChange` vs `.onReceive`** -- `.onChange(of:)` loses its previous-value tracker when SwiftUI recreates view struct. Use `.onReceive(viewModel.$property.dropFirst())` for reliable reaction to `@Published` changes.
8. **Check `@State` UUID-cache staleness** -- If hit-testing, overlays, or gesture highlights fail intermittently after operations that regenerate collections (layout changes, image swaps), the `@State [UUID: CGRect]` cache may be stale for one render cycle. Fix: compute frames on-the-fly in `GeometryReader` closure instead of caching in `@State`. See [references/state/observable-bindable.md](references/state/observable-bindable.md)
9. **Check CGRect equality** -- lookups by `frame == targetRect` may fail due to `CGFloat` precision errors. Use `id`-based lookup instead.
10. **Extract view-local mutable state** to `@MainActor final class` + `@StateObject` when the view needs timers, debouncers, or other reference-type members
11. **Runtime debugging:** `print()` goes to stdout (not visible in `log stream`). Use `os_log` for unified log, or run app from terminal to see `print()` output.
12. **Visual element "doesn't appear" diagnostic:** When rendering code looks correct but nothing shows up:
     a. Add `Logger` at pipeline boundaries -- file load, CGImage extraction, style branch, draw call
     b. Log actual values, not just nil/non-nil -- dimensions, opacity, color components
     c. Check `UserDefaults` defaults -- typed getters (`.double`, `.integer`, `.bool`) return zero for missing keys
     d. Check thread affinity -- AppKit methods (`NSImage.cgImage`, `NSColor.cgColor`) called on background threads may silently return `nil`
15. **Check computed properties on structs crossing actor boundaries** — A computed `var cgColor: CGColor { nsColor.cgColor }` on a struct captured by `Task.detached` evaluates on the background thread. If colors are corrupted or crashes occur in rendering, verify that `CGColor` values are stored at init time on MainActor, not computed lazily.
16. **NSColorWell color stale** -- `NSColor ==` compares `CGColor` values, which differ across color spaces. Never guard `updateNSView` with `!=`. Always assign `well.color = color` unconditionally. See [references/appkit/nscolorwell.md](references/appkit/nscolorwell.md)
17. **NSColorWell target/action lost** -- `NSColorWell` may reset `target`/`action` during view hierarchy reconfiguration. Re-set both in `updateNSView` every cycle. See [references/appkit/nscolorwell.md](references/appkit/nscolorwell.md)
18. **NSTextView re-entrancy loop** -- If `textDidChange` normalizes text into a binding, the SwiftUI re-render may call `updateNSView`, which mutates `typingAttributes`, firing another `textDidChange`. Fix with coordinator guard flag + early return in `updateNSView`. See [references/appkit/nstextview-binding.md](references/appkit/nstextview-binding.md)
19. **Cross-view `updateNSView` cascade** -- ANY `@Observable` property change calls `updateNSView` on ALL `NSViewRepresentable`s in the tree. If an unrelated text view's `updateNSView` performs unconditional mutations (e.g., `typingAttributes` assignment), it can trigger `textDidChange` → binding write → re-render loop. Symptom: color picker frozen on white/full opacity after editing text. Fix: guard ALL mutations in `updateNSView` with change-detection, not just the self-referential path. See [references/appkit/nstextview-binding.md](references/appkit/nstextview-binding.md) § "Cross-View `updateNSView` Cascade"
20. **Text overlay size doesn't match rendered text** -- SwiftUI `Text` and `NSAttributedString.draw` use different font engines. Even with the same font family and point size, the rendered size will differ. If a gesture overlay appears misaligned or wrong-sized compared to CG-rendered text, the fix is not to tweak the SwiftUI font — it's to use a debounced CG render of the same layer. See [references/gestures/swiftui-gestures.md](references/gestures/swiftui-gestures.md)
21. **Cached value is `nil` despite populated input** -- Multi-field cache (result + key + input) only cleared the result field, leaving keys stale. On restore, keys match and return stale `nil`. Fix: clear ALL fields, or use defensive guard (`if let cachedResult = cachedResult, ...`).

## Logging Quality

- **Logging utility extraction** -- Private string formatting helpers (`rectStr`, `pointStr`, `sizeStr`) defined in view files should be moved to a shared `LoggingExtensions.swift` file as `internal` functions. Avoids duplication across files that need debug logging.
- **Error logging for silent failures** -- Always add `logger.error` before returning `nil` from rendering methods (e.g., `createBitmapContext` returning `nil`). Silent failures are invisible in production.
- **Redundant `privacy: .public`** -- `"\("\(value)", privacy: .public)"` has no effect — the outer string interpolation swallows the OSLog privacy annotation. Use `"\(value)"` directly or `"\(value, privacy: .public)"` at the top level.
