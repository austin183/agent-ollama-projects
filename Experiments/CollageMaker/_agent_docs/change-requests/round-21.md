# Migrate Title Rendering to CoreText

## Problem

`drawTitle()` in `CollageAssembler.swift:365-405` runs inside `scheduler.render {}` on a background `DispatchQueue`. It exercises three AppKit code paths that are not thread-safe:

1. **`TitleMetrics.prepare()`** (`TitleMetrics.swift:8-21`) — mutates `NSMutableAttributedString`, `NSMutableParagraphStyle`, and calls `FontMerger.merge()` which manipulates `NSFont`/`NSFontDescriptor`
2. **`NSMutableAttributedString.addAttribute(.foregroundColor)`** (`CollageAssembler.swift:371-373`) — additional mutation of AppKit types
3. **`NSAttributedString.draw(in:)`** (`CollageAssembler.swift:404`) — walks AppKit font/layout engines to render glyphs
4. **`NSAttributedString.boundingRect(with:)`** (`TitleMetrics.swift:23-28, 30-35`) — measures text via AppKit internals

This is flagged as **C-1 (Critical)** in the 2026-06-02 architectural review. The code may work today because `NSGraphicsContext.current` is set up, but Apple does not document these APIs as thread-safe. Any macOS update could break this.

## Current pipeline

```
NSAttributedString (from editor, MainActor)
  → TitleMetrics.prepare()          // AppKit mutation: paragraph style, font merge
  → NSMutableAttributedString + foregroundColor  // AppKit mutation
  → metrics.boundingBox             // AppKit measurement
  → attributedString.draw(in:)      // AppKit rendering
All of the above runs on the background render queue.
```

## Proposed pipeline

```
NSAttributedString (from editor, MainActor)
  → TitleMetricsCT.prepare()        // CoreText: build CTFont, CTParagraphStyle, CFAttributedString
  → metrics.boundingBox             // CoreText: CTLineGetBounds / CTFramesetterSuggestFrameSize
  → CTFrameDraw(context:)           // CoreText: render glyphs directly to CGContext
All of the above runs on the background render queue (thread-safe).
```

## What changes

### New file: `TitleRendererCT.swift` (Services/)

Pure CoreText/CoreGraphics implementation. No AppKit dependency.

**`struct TitleMetricsCT`:**
- `let paragraphStyle: CTFramesetter` — pre-built framesetter for measurement + rendering
- `let style: TitleStyle`
- `let stringLength: CFIndex`

**`static func prepare(_ attrString: NSAttributedString, style: TitleStyle) -> TitleMetricsCT`:**
- Walk `attrString`'s runs, extract font family/size/traits and color per range
- Build `CTFontRef` per run via `CTFontCreateWithName()` + trait merging via `CTFontCopyAttribute(kCTFontSymbolicTraitAttribute)`
- Build paragraph style via `CTParagraphStyleCreate()` with alignment mapping (`.left` → `kCTLeftAlignment`, etc.)
- Construct `CFMutableAttributedString`, apply `kCTFontAttributeName`, `kCTForegroundColorFromContextAttributeName`, `kCTParagraphStyleAttributeName` per range
- Wrap in `CTFramesetter` for multi-line layout

**`var boundingBox(canvasSize: CGSize) -> CGRect`:**
- `CTFramesetterSuggestFrameSizeWithConstraints()` for text dimensions
- Account for `boundingBox.origin.y` (descent offset) to match current behavior

**`var minNaturalWidth(canvasSize: CGSize) -> CGFloat`:**
- Same as above with unconstrained width

**`func drawTitle(into context: CGContext, canvasWidth: CGFloat, canvasHeight: CGFloat)`:**
- Compute anchor/draw position from `TitleStyle` (same math as current `drawTitle`)
- Draw background pill with `CGPath(roundedRect:)` + `context.fillPath()` (this is already pure CG, no change)
- `CTFramesetterCreateFrame()` with constrained rect
- `CTFrameDraw(context:)` — CoreText draws bottom-left, same as CGContext, no flip needed

### Font merging: CoreText equivalent

Current `FontMerger.merge()` uses `NSFontDescriptor.withSymbolicTraits()`. CoreText equivalent:

```swift
let baseFont = CTFontCreateWithName(family as CFString, size, nil)
let existingTraits = CTFontCopySymbolicTraits(existingFont)
let baseTraits = CTFontCopySymbolicTraits(baseFont)
let mergedTraits = baseTraits.union(existingTraits)
let attributes = [kCTFontSymbolicTraitAttribute: mergedTraits.rawValue]
let mergedFont = CTFontCreateCopyWithAttributes(baseFont, 0, nil, attributes as CFDictionary)
```

### Files to modify

| File | Changes |
|------|---------|
| **NEW `Services/TitleRendererCT.swift`** | `TitleMetricsCT` struct, `prepare()`, `drawTitle()`, CoreText font merging |
| **`Services/TitleMetrics.swift`** | Keep for MainActor-side measurement (editor view hit testing). Or deprecate if CoreText version is pixel-identical. |
| **`Services/CollageAssembler.swift`** | Replace `drawTitle()` (line 365-405) with `TitleMetricsCT.drawTitle(into:)`. Remove `NSAttributedString` parameter from `drawTitle`, pass `TitleMetricsCT` instead. Remove `@unchecked Sendable` extension on `NSAttributedString`. |
| **`Services/FontMerger.swift`** | Keep for MainActor-side use (AttributedStringEditor). Add CoreText variant in `TitleRendererCT.swift`. |
| **`Models/TitleStyle.swift`** | No changes needed — `NSTextAlignment` mapping to `CTAlignment` is internal to `TitleRendererCT`. |
| **`Views/CollageEditorView.swift`** | No changes — title frame math (`titleCanvasFrame`, line 23-44) uses `TitleMetrics.boundingBox` which is computed on MainActor. Keep `TitleMetrics` for the editor view. |
| **`ViewModel/CollageViewModel.swift`** | `buildAssemblyConfig()` passes `config.title.attrString` to assembler. Instead, pass a pre-built `TitleMetricsCT` (or keep `NSAttributedString` and build `TitleMetricsCT` inside the render closure on the background thread). |
| **`AssemblyConfig.swift`** | `TitleConfig` currently holds `attrString: NSAttributedString`. Either add `metricsCT: TitleMetricsCT?` or keep `attrString` and have the assembler build `TitleMetricsCT` inside the render closure. |

### Files NOT changing

| File | Reason |
|------|--------|
| `Views/AttributedStringEditor.swift` | Uses `NSAttributedString` for editing — stays on MainActor |
| `Views/CollageEditorView.swift` | Title hit-testing uses `TitleMetrics` computed on MainActor |
| `Views/PanelCropEditor.swift` | Unrelated to title rendering |
| `Services/PreviewManager.swift` | Calls assembler methods, no title-specific code |
| `Services/UserDefaultsPersistence.swift` | Serializes `NSAttributedString` via `NSKeyedArchiver` — stays on MainActor |

## Key design decisions

### Keep `TitleMetrics` for the editor view

`CollageEditorView.titleCanvasFrame` reads `viewModel.titleMetrics.boundingBox` on the main thread for hit-testing and gesture overlays. This computation stays as-is using AppKit's `NSAttributedString.boundingRect(with:)` since it runs on MainActor.

The CoreText version (`TitleMetricsCT`) is used **only** inside the render queue for measurement + drawing.

### Pixel-identical rendering requirement

`CTFrameDraw` and `NSAttributedString.draw(in:)` use the same underlying text engine (CoreText). The output should be pixel-identical for the same font, size, and alignment. The main difference is the coordinate system:
- `NSAttributedString.draw(in:)` expects top-left origin (AppKit convention)
- `CTFrameDraw()` draws in CGContext coordinates (bottom-left)

Since `drawTitle` already converts to CGContext coordinates (`anchorYcg = canvasHeight - positionY * canvasHeight`), the CoreText version uses the same coordinate space directly — no flip needed.

### Alignment mapping

```swift
extension NSTextAlignment {
    var ctAlignment: CTAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        case .natural: return .natural
        @unknown default: return .center
        }
    }
}
```

### Color conversion

`NSColor.cgColor` is already a `CGColorRef` — no conversion needed. The `@unchecked Sendable` on `TitleStyle` (which embeds `NSColor`) is still needed, but the color is only **read** (`..cgColor`), not mutated, which is the safe pattern.

Alternatively, pass `CGColor` instead of `NSColor` to the CoreText renderer and do the `..cgColor` extraction on MainActor before crossing the boundary.

## Implementation steps

1. **Create `TitleRendererCT.swift`** with `TitleMetricsCT.prepare()`, `boundingBox`, `minNaturalWidth`, `drawTitle(into:canvasWidth:canvasHeight:)`
2. **Update `CollageAssembler.drawTitle()`** to use `TitleMetricsCT` instead of `TitleMetrics` + `NSAttributedString.draw(in:)`
3. **Remove `@unchecked Sendable` extension on `NSAttributedString`** (line 14 of `CollageAssembler.swift`) — no longer needed if the assembler no longer passes `NSAttributedString` across actor boundaries
4. **Verify pixel-identical output** — build, run, compare title rendering before/after with various fonts, sizes, alignments, and background pill
5. **Update tests** — `TitleMetricsTests.swift` exercises `TitleMetrics.prepare()` on MainActor (still valid). Add `TitleMetricsCTTests.swift` for the CoreText path.

## Risk assessment

| Risk | Mitigation |
|------|-----------|
| CoreText renders differently than AppKit for some fonts | Test with system font, custom named fonts, bold/italic traits |
| Multi-line text layout differs | `CTFramesetter` handles wrapping; test with long titles and narrow widths |
| Performance regression | CoreText is typically faster than AppKit's `draw(in:)` — it skips the AppKit bridge layer |
| `NSColor.cgColor` on background thread is unsafe | Extract `..cgColor` on MainActor in `buildAssemblyConfig()`, pass `CGColor` to renderer |

## Estimated effort

~2 hours. The CoreText API is verbose (C-based) but the rendering path is straightforward: one framesetter, one frame, one `draw` call. Font merging adds ~20 lines. Alignment mapping adds ~10 lines. Total new code: ~120 lines.
