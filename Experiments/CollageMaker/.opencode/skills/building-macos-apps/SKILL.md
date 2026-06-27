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
| **CGImage Pixel Extraction via CGBitmapContext** | [references/graphics/cgbitmapcontext-pixel-extraction.md](references/graphics/cgbitmapcontext-pixel-extraction.md) |
| **CoreImage, CoreGraphics, Compositing** | [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md) |
| **Vision API Details** | [references/graphics/vision-api-details.md](references/graphics/vision-api-details.md) |
| **vImage Processing** | [references/graphics/vimage-processing.md](references/graphics/vimage-processing.md) |
| **CoreText Background Rendering** | [references/graphics/coretext-background-rendering.md](references/graphics/coretext-background-rendering.md) |

### Testing

| Topic | Reference |
|-------|-----------|
| **Unit Testing Patterns** | [references/testing/testing-patterns.md](references/testing/testing-patterns.md) |
| **XCUIAutomation macOS Gotchas** | [references/testing/testing-patterns.md § XCUIAutomation](references/testing/testing-patterns.md) |

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
| **Logging Quality** | [references/tooling/logging-quality.md](references/tooling/logging-quality.md) |

### Debugging

| Topic | Reference |
|-------|-----------|
| **Debugging Strategy** | [references/debugging/debugging-strategy.md](references/debugging/debugging-strategy.md) |

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

See [references/graphics/coordinate-systems.md](references/graphics/coordinate-systems.md).

## State Management

### @Observable (macOS 14+, preferred)

See [references/state/observable-bindable.md](references/state/observable-bindable.md).

**Critical rules:**
- **`@Observable` cannot track computed properties** -- all properties driving UI must be stored. Use `didSet` for `UserDefaults` persistence
- **Views must use `@Bindable var`** -- `let viewModel: MyViewModel` renders once and never updates
- Side effects (e.g., `updatePreview()`) must be called in `didSet`, not computed setters
- **Circular init (sub-object needs `self`)** — Put the IUO on the sub-object's back-reference, not the owner. Assign after init: `self.coordinator = Coordinator(); coordinator.target = self`. See [references/state/observable-bindable.md](references/state/observable-bindable.md) § "Circular Init"
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
- **Body re-evaluation cascades** — High-frequency gesture state (e.g., `DragGesture.onChanged`) invalidates all `@Bindable` observers. Fix: extract state into a self-contained sibling struct with local `@State`, sync to ViewModel once on `onEnded`. Only the isolated struct re-evaluates. See [references/state/observable-bindable.md](references/state/observable-bindable.md) § "Body Re-evaluation Cascades During Gestures"

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

## Swift Compilation Gotchas

- **Circular init (`self` used before initialized):** Put the IUO on the sub-object's back-reference, not the owner. Assign after init: `self.coordinator = Coordinator(); coordinator.target = self`. See [references/state/observable-bindable.md](references/state/observable-bindable.md) § "Circular Init"
- **Same-file extension ordering:** See [references/state/swift-concurrency.md](references/state/swift-concurrency.md) § "Swift Compilation Gotchas"

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
- **Mark `analyze` as `nonisolated`** — without it, `withThrowingTaskGroup` calls serialize through the actor executor, giving zero parallelism. The method must access no actor-stored state (only locals, params, Vision API). Caller extracts `CGImage` on main thread before passing in. See [references/graphics/vision-api-details.md](references/graphics/vision-api-details.md)
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
- **CGBlendMode on empty CGContext produces black** — multiply on transparent buffer = `source × (0,0,0,0)` = black. Render overlay without blend mode in CGContext, apply `.blendMode()` in SwiftUI ZStack where destination pixels exist. See [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md) § Pitfalls
- **CGContext implicit clipping vs ZStack** — single-context rendering clips to bitmap bounds automatically; layered per-panel rendering in ZStack does not. Add `.clipShape(Rectangle())` + `.frame()` + `.position()` to the ZStack. See [references/graphics/coreimage-filters.md](references/graphics/coreimage-filters.md) § Pitfalls

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

See [references/tooling/performance-debugging.md](references/tooling/performance-debugging.md) for budgets, rendering rules, timing APIs, Instruments templates, and sanitizers.

## CLI Build and Launch

```bash
# Build
xcodebuild -project "App.xcodeproj" -scheme AppName \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build

# Launch (use glob for DerivedData hash)
open "$HOME/Library/Developer/Xcode/DerivedData/AppName-*/Build/Products/Debug/AppName.app"

# Launch with env var (use absolute paths — `open` sets ~ as cwd)
TEST_DIR=/absolute/path open "$HOME/Library/Developer/Xcode/DerivedData/AppName-*/Build/Products/Debug/AppName.app"
```

- `NSUnbufferedIO=YES open ...` does not produce useful stdout for SwiftUI apps
- When debugging GUI behavior without app visibility, write ViewModel integration tests with real data
- **Sandbox blocks arbitrary file reads** — `FileManager` silently returns `nil` for paths outside the sandbox. If test infrastructure reads fixtures from env vars, set `ENABLE_APP_SANDBOX = NO` in the Debug config. See [references/testing/testing-patterns.md](references/testing/testing-patterns.md) § "App Sandbox Blocks Test File Access"

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

See [references/debugging/debugging-strategy.md](references/debugging/debugging-strategy.md).

## Logging Quality

See [references/tooling/logging-quality.md](references/tooling/logging-quality.md).
