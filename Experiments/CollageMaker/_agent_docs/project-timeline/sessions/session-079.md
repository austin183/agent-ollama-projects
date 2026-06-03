# Round 22: Migrate Preview Rendering to Pure CoreGraphics — Session 79

**Date:** 2026-06-02
**Change Request:** 2026-06-02-preview-rendering-pure-cg.md — Migrate Preview Rendering to Pure CoreGraphics

## Context

`CollageAssembler` used `NSBitmapImageRep` + `NSGraphicsContext.current` to create drawing contexts inside `scheduler.render {}` closures on a background `DispatchQueue`. The actual pixel drawing was 100% CoreGraphics, but the context creation and output wrapping exercised AppKit APIs (`NSBitmapImageRep`, `NSGraphicsContext.save/restoreGraphicsState`, `NSGraphicsContext.current`) that Apple does not document as thread-safe.

This is the same class of issue that was fixed in round 21 (Title → CoreText), but applied to all five rendering paths (export, preview, panel, background, title).

## Approach

Replace the `NSBitmapImageRep` / `NSGraphicsContext` boilerplate in all 5 rendering methods with direct `CGContext` creation. Convert `NSColor` → `CGColor` on MainActor before crossing the concurrency boundary.

## Changes Completed

### `Models/AssemblyConfig.swift`
- `BackgroundConfig` — added `backgroundColor: CGColor`, `gradientStartCGColor: CGColor`, `gradientEndCGColor: CGColor` properties
- Added convenience `init` that derives `CGColor` from `NSColor` (used by `CollageViewModel.updateBackground()` and `TestHelpers.makeAssemblyConfig()`)

### `Services/CollageAssembler.swift`
- Added `createPureCGContext(size:)` — creates a `CGContext` directly with `CGColorSpaceCreateDeviceRGB()` + `premultipliedFirst` bitmap info
- Replaced `NSBitmapImageRep` / `NSGraphicsContext.saveGraphicsState()` / `NSGraphicsContext.current` / `NSGraphicsContext.restoreGraphicsState()` boilerplate in all 5 rendering methods with `createPureCGContext` + `context.makeImage()`
- Changed `drawGradient()` and `drawImageBackground()` to accept `CGColor` instead of `NSColor`
- `renderIntoContext()` and `renderPreviewIntoContext()` now return `CGImage?` instead of `NSBitmapImageRep?`
- Eliminated all `NSColor.cgColor` calls from background rendering paths

### Files NOT changed
- `CollageViewModel.swift` — `buildAssemblyConfig()` and `updateBackground()` use the convenience init which handles `NSColor` → `CGColor` conversion on MainActor
- `TestHelpers.swift` — `makeAssemblyConfig()` flows through `AssemblyConfig.init` → convenience init
- `RenderScheduler.swift` — serial queue still valuable for concurrency control
- `PreviewManager.swift` — no rendering code, `NSImage` wrapping stays in assembler

## Bug Fixed During Session

- **Y-axis flip** — Initial implementation added `context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)` to `createPureCGContext` to "match" the existing coordinate system. This rendered everything upside down because `NSBitmapImageRep` + `NSGraphicsContext.current.cgContext` already produces a bottom-left origin context matching raw `CGContext`. The Y-flip was a double-inversion. Fix: removed the transform.

## Build Status

**BUILD SUCCEEDED** — Zero warnings.

**ALL TESTS PASS** — Full test suite passes.

## Files Changed

- `Models/AssemblyConfig.swift` — BackgroundConfig CGColor properties + convenience init
- `Services/CollageAssembler.swift` — Pure CGContext in all 5 rendering methods
