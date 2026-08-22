# Migrate Preview Rendering to Pure CoreGraphics

## Problem

`CollageAssembler` uses `NSBitmapImageRep` + `NSGraphicsContext.current` to create drawing contexts inside `scheduler.render {}` closures on a background `DispatchQueue`. The actual pixel drawing is 100% CoreGraphics, but the context creation and output wrapping exercise AppKit APIs that Apple does not document as thread-safe.

This is the same class of issue that was fixed in round-21 (Title → CoreText), but applied to all five rendering paths.

## Current pipeline

Every rendering method in `CollageAssembler` follows this pattern:

```
NSBitmapImageRep(...)              // AppKit on background thread
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ...    // AppKit thread-local on background thread
let context = NSGraphicsContext.current?.cgContext  // bridge to CG
// ... CGContext.draw, fill, clip ... (all thread-safe)
NSImage(cgImage:size:)             // AppKit on background thread
```

The five methods are:
1. `assemblePreviewWithCGImages()` — full composite preview
2. `renderPanel()` — per-panel preview
3. `renderBackground()` — background preview
4. `renderTitle()` — title preview
5. `renderExportImage()` — export image generation

## Proposed pipeline

```
CGContext(data:width:height:...)   // Pure CG, thread-safe
// ... CGContext.draw, fill, clip ... (unchanged)
context.makeImage()                // Pure CG
NSImage(cgImage:size:)             // AppKit, but moved to main thread via MainActor.run
```

## What changes

### `CollageAssembler.swift` — Core change

Replace the `NSBitmapImageRep` / `NSGraphicsContext` boilerplate in all 5 rendering methods with direct `CGContext` creation:

```swift
// Before (each method)
let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .sRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)
bitmapRep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
guard let context = NSGraphicsContext.current?.cgContext else { return nil }
// ... drawing ...
NSGraphicsContext.restoreGraphicsState()
return NSImage(cgImage: bitmapRep.cgImage!, size: size)

// After
guard let colorSpace = CGColorSpaceCreateDeviceRGB(),
      let context = CGContext(
          data: nil,
          width: Int(size.width),
          height: Int(size.height),
          bitsPerComponent: 8,
          bytesPerRow: Int(size.width) * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
      ) else { return nil }
// ... drawing (unchanged) ...
guard let cgImage = context.makeImage() else { return nil }
return NSImage(cgImage: cgImage, size: size)
```

### `CollageAssembler.swift` — `NSColor.cgColor` extraction

`BackgroundConfig` currently carries `NSColor` properties (`color`, `gradientStart`, `gradientEnd`). The `.cgColor` accessor is invoked inside the render closure on the background thread. This needs to move to the call site on MainActor.

**Approach:** Add `CGColor` properties to `BackgroundConfig` (mirroring how `TitleConfig` already carries `fontColor: CGColor`). Convert at call sites.

### `AssemblyConfig.swift` — `BackgroundConfig`

Add CGColor properties:
- `backgroundColor: CGColor`
- `gradientStartColor: CGColor?`
- `gradientEndColor: CGColor?`

Keep the existing `NSColor` properties for MainActor-side use (serialization, settings view).

### `CollageViewModel.swift` — `buildAssemblyConfig()`

Convert `NSColor` → `CGColor` on MainActor before building the `BackgroundConfig`:

```swift
let bgConfig = BackgroundConfig(
    style: backgroundStyle,
    color: backgroundColor,
    gradientStart: gradientStartColor,
    gradientEnd: gradientEndColor,
    backgroundColor: backgroundColor.cgColor,
    gradientStartColor: gradientStartColor?.cgColor,
    gradientEndColor: gradientEndColor?.cgColor
)
```

### `CollageViewModel.swift` — `updatePanelPreview()`

The `panelImage.cgImage` extraction already happens on MainActor. No change needed.

### `PreviewManager.swift` — Output wrapping on main thread

The `NSImage(cgImage:size:)` call currently happens inside the `scheduler.render {}` closure on the background queue. Two options:

**Option A (Recommended):** Keep `NSImage` wrapping on background thread. It's a lightweight reference wrapper around the `CGImage`, not a rendering operation. This is the pragmatic choice — it works, the `NSImage` is only ever read on the main thread.

**Option B (Strict):** Return `CGImage` from the render closure, then wrap on MainActor:
```swift
let cgImage = await scheduler.render { assembler.renderPanelCGImage(...) }
await MainActor.run { self.panelRenderedImages[panelId] = NSImage(cgImage: cgImage, size: size) }
```

**Decision:** Option A for now. The `NSImage(cgImage:size:)` initializer is documented and doesn't exercise any mutable shared state. If Apple ever tightens this, we can migrate to Option B.

### `RenderScheduler.swift` — No functional change

The serial `DispatchQueue` remains valuable for:
- Preventing concurrent render work
- Bounded concurrency during rapid user interactions
- General discipline

The `NSGraphicsContext.current` protection is no longer needed, but the queue serves other purposes. No changes required.

## Files to modify

| File | Changes |
|------|---------|
| **`Services/CollageAssembler.swift`** | Replace `NSBitmapImageRep` + `NSGraphicsContext` pattern in all 5 rendering methods with direct `CGContext`. Use `CGColor` properties from `BackgroundConfig` instead of `NSColor.cgColor`. |
| **`Models/AssemblyConfig.swift`** | `BackgroundConfig` — add `CGColor` properties alongside existing `NSColor` properties. |
| **`ViewModel/CollageViewModel.swift`** | `buildAssemblyConfig()` — populate `CGColor` properties on `BackgroundConfig`. |
| **`Tests/TestHelpers.swift`** | `makeAssemblyConfig()` — update to pass `CGColor` properties. |

## Files NOT changing

| File | Reason |
|------|--------|
| `Services/PreviewManager.swift` | Orchestrates tasks, no rendering code. `NSImage` wrapping stays in assembler. |
| `Services/RenderScheduler.swift` | Serial queue still valuable for concurrency control. |
| `Services/TitleRendererCT.swift` | Already pure CG, no changes. |
| `Views/CollageEditorView.swift` | Display layer, `Image(nsImage:)` stays on MainActor. |
| `Views/ImagePickerGrid.swift` | Thumbnail display, unrelated. |
| `ViewModel/ImageLibraryManager.swift` | Already uses pure CG for thumbnails. |

## Implementation steps

1. **Add `CGColor` properties to `BackgroundConfig`** — mirror the `TitleConfig` pattern
2. **Update `CollageViewModel.buildAssemblyConfig()`** — populate `CGColor` properties on MainActor
3. **Refactor `CollageAssembler` render methods** — replace `NSBitmapImageRep` / `NSGraphicsContext` with direct `CGContext` in all 5 methods
4. **Update `TestHelpers.makeAssemblyConfig()`** — pass `CGColor` properties
5. **Build and verify** — compile, run all tests
6. **Visual verification** — run the app, verify preview rendering is identical (colors, gradients, panels, titles, backgrounds)

## Risk assessment

| Risk | Mitigation |
|------|-----------|
| Color rendering differs (color space, gamma) | `CGColorSpaceCreateDeviceRGB()` + `premultipliedFirst` bitmap info matches `NSBitmapImageRep` sRGB defaults |
| Alpha channel handling differs | Same `bitsPerComponent: 8`, `samplesPerPixel: 4`, `premultipliedFirst` as before |
| `NSColor.cgColor` lazy evaluation | Moved to MainActor in `buildAssemblyConfig()` |
| Export path breaks | `renderExportImage()` uses the same CG pattern — verify export output visually |
| Tests fail due to mock changes | `TestHelpers` update is straightforward; test assertions compare `NSImage` outputs, which are unchanged |

## Estimated effort

~1 hour. The drawing logic is unchanged — only the ~15 lines of context boilerplate per method (×5 methods = ~75 lines) plus the `BackgroundConfig` extension and call-site conversion.
