# NSAttributedString Drawing — Text Overlay in CoreGraphics

## Modern API (Use This)

```swift
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 48),
    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
]

let attributedString = NSAttributedString(string: "Title", attributes: attributes)

// Calculate bounding box
let titleRect = attributedString.boundingRect(
    with: CGSize(width: maxWidth, height: 100),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

// Draw at position
attributedString.draw(at: CGPoint(x: x, y: y))
```

## Deprecated API (Avoid)

```swift
// DEPRECATED — CGContext text methods
context.selectFont("Helvetica-Bold", size: 48, textEncoding: .macRoman)
context.showTextAtPoint(x: 960, y: 1040, string: "Title", length: 5)
```

## Semi-Transparent Background

```swift
let padding: CGFloat = 12
let bgRect = boundingBox.insetBy(dx: -padding, dy: -padding)
let bgOrigin = CGPoint(x: x - padding, y: y - padding)

// Draw semi-transparent background with rounded corners
context.saveGState()
context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
let roundedPath = CGPath(
    roundedRect: CGRect(origin: bgOrigin, size: CGSize(
        width: boundingBox.width + padding * 2,
        height: boundingBox.height + padding * 2
    )),
    cornerWidth: 8,
    cornerHeight: 8,
    transform: nil
)
context.addPath(roundedPath)
context.fillPath()
context.restoreGState()

// Draw text on top
title.draw(at: CGPoint(x: x, y: y))
```

## Font Selection

```swift
NSFont.systemFont(ofSize: 48)          // Regular
NSFont.boldSystemFont(ofSize: 48)      // Bold
NSFont.mediumSystemFont(ofSize: 48)    // Medium
NSFont.semiboldSystemFont(ofSize: 48)  // Semi-bold
NSFont.labelFont(ofSize: 48)           // Labels
NSFont.titleFont(ofSize: 48)           // Titles
```

## Multi-Line Text

```swift
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center
paragraphStyle.lineBreakMode = .byWordWrapping

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 48),
    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
    .paragraphStyle: paragraphStyle
]

let boundingBox = attributedString.boundingRect(
    with: CGSize(width: maxWidth, height: 200),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

// Draw in rect for proper line breaking
attributedString.draw(in: CGRect(x: 20, y: y, width: maxWidth, height: boundingBox.height))
```

## Bottom-Center Position Calculation

```swift
let boundingBox = title.boundingRect(
    with: CGSize(width: canvasWidth - 40, height: 100),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

let x = (canvasWidth - boundingBox.width) / 2
let y = canvasHeight - boundingBox.height - 20  // 20pt margin from bottom
title.draw(at: CGPoint(x: x, y: y))
```

## boundingRect() Returns Tight Bounds, Not Position

`attributedString.boundingRect(with:options:)` returns the tight bounding box of the rendered text, **not** its position within the constrained rect. `boundingBox.origin.x` is always ~0 (left edge of the text), regardless of paragraph alignment. Cannot use it to compute where aligned text will appear within a wider draw rect.

To position a background around aligned text:
- **Option A — Full-width background (simplest):** Make the background span the full draw width. The box stays fixed at the anchor point regardless of alignment.
- **Option B — Tight background with manual offset:** Compute text offset from alignment:
  - Left: `offsetX = 0`
  - Center: `offsetX = (drawWidth - textWidth) / 2`
  - Right: `offsetX = drawWidth - textWidth`

## draw(at:) vs draw(in:) Baseline Semantics

- **`draw(at:point)`** — `point` is the **baseline** of the text. Combined with `boundingRect()`, the baseline Y is `anchorY - boundingBox.height` where `anchorY` is the desired text top.
- **`draw(in:rect)`** — `rect.y` is also the **baseline**, NOT the top of the text.
- **Both treat Y as baseline** — this is consistent across both APIs
- `draw(in:)` respects `NSParagraphStyle.alignment` natively — text aligns within the rect. `draw(at:)` always draws left-aligned at the point, requiring manual X offset.
- **For aligned text within a fixed-width box**, `draw(in:)` is the correct choice:
  ```swift
  attributedString.draw(in: CGRect(x: drawX, y: baselineY, width: drawWidth, height: boundingBox.height))
  ```
- **For title rendering with a tight background pill**, `draw(at:)` with manual offset is simpler and less error-prone.

## Alignment Should Move Text Within a Fixed Box

When the user changes text alignment, the visual expectation is that the text box stays put and the text inside it repositions. Do NOT shift the entire box (background + text) based on alignment — the user will see the whole title move across the canvas.

**Correct approach:** Background spans full draw width and stays centered at the anchor point. Text offset is computed from alignment and applied only to the draw position.

```swift
let padding: CGFloat = 12
let drawWidth = canvasWidth - 40

// Background spans full width, anchored at positionX
let bgX = (canvasWidth - drawWidth) / 2
let bgY = canvasHeight - boundingBox.height - 20
context.saveGState()
context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
let bgPath = CGPath(roundedRect: CGRect(x: bgX - padding, y: bgY - padding, width: drawWidth + padding * 2, height: boundingBox.height + padding * 2), cornerWidth: 8, cornerHeight: 8, transform: nil)
context.addPath(bgPath)
context.fillPath()
context.restoreGState()

// Text offset computed from alignment
let textOffsetX: CGFloat
switch alignment {
case .left: textOffsetX = 0
case .right: textOffsetX = drawWidth - boundingBox.width
default: textOffsetX = (drawWidth - boundingBox.width) / 2
}

let baselineY = bgY + boundingBox.height  // bgY is text top, baseline is top + height
title.draw(at: CGPoint(x: bgX + textOffsetX, y: baselineY))
```

## Font Trait Manipulation

### NSFontDescriptor.withSymbolicTraits (Recommended)

`NSFontManager.shared.convert(_:toHaveTrait:)` two-argument forms are **not available** in Swift on macOS. Use `NSFontDescriptor.withSymbolicTraits`:

```swift
func fontWithBold(_ font: NSFont, toggle: Bool) -> NSFont? {
    var traits = font.fontDescriptor.symbolicTraits
    if toggle {
        traits.insert(.bold)
    } else {
        traits.remove(.bold)
    }
    let descriptor = font.fontDescriptor.withSymbolicTraits(traits)  // non-optional
    return NSFont(descriptor: descriptor, size: font.pointSize)
        ?? NSFont.boldSystemFont(ofSize: font.pointSize)
}
```

- `withSymbolicTraits(_:)` returns **non-optional** `NSFontDescriptor`
- `NSFont(descriptor:size:)` returns `NSFont?` — always provide a fallback

### Bold/Italic Detection

Use `NSFontDescriptor.SymbolicTraits`, not `NSFontTraitMask`:

```swift
func fontIsBold(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.bold)
}

func fontIsItalic(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.italic)
}
```

`NSFont.fontTraits` doesn't exist as a property. `NSFontTraitMask.boldTrait` doesn't exist in Swift.

### Enumerating Attribute Runs

`textStorage.attributeRuns(in:)` is not callable as a function in Swift. Use `enumerateAttribute`:

```swift
textStorage.enumerateAttribute(.font, in: sel, options: []) { value, range, _ in
    if let font = value as? NSFont {
        // Apply per-run font transformation
    }
}
```

## Font Trait Merging in Render Code

When rendering text with user-configured font family and size, you must **preserve per-character bold/italic traits** from the attributed string. Do NOT simply overwrite the entire `.font` attribute — this destroys per-character styling.

```swift
let mutable = NSMutableAttributedString(attributedString: titleAttrString)
mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))
mutable.addAttribute(.foregroundColor, value: titleStyle.fontColor, range: NSRange(location: 0, length: mutable.length))

mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
    let traits: NSFontDescriptor.SymbolicTraits
    if let existingFont = value as? NSFont {
        traits = existingFont.fontDescriptor.symbolicTraits
    } else {
        traits = []
    }
    let baseDescriptor = defaultFont.fontDescriptor
    let mergedDescriptor = baseDescriptor.withSymbolicTraits(traits) ?? baseDescriptor
    let mergedFont = NSFont(descriptor: mergedDescriptor, size: titleStyle.fontSize) ?? defaultFont
    mutable.addAttribute(.font, value: mergedFont, range: range)
}
```

**Critical:** Must apply `.foregroundColor` explicitly across the full range. Without this, text renders with whatever color is embedded in the attributed string (or CGContext default, which is black).

## Editor Display vs. Rendered Output (Two-Layer Approach)

The editor and the rendered image need different font sizes and colors, but the same style traits (bold, italic, underline). Use two layers:

1. **Editor normalization** — The `NSTextView` always displays text at a fixed size (e.g., 14pt) and color (white), but preserves bold/italic/underline traits. A `normalizeForEditor` function strips size and color and replaces them with editor defaults while preserving symbolic traits.
2. **Render-time application** — `drawTitle` applies the real `fontSize`, `fontFamily`, and `fontColor` from user settings at render time.

### Normalizing for Editor Display

```swift
private func normalizeForEditor(_ attrString: NSAttributedString, fontFamily: String) -> NSAttributedString {
    let normalized = NSMutableAttributedString()
    let fullRange = NSRange(location: 0, length: attrString.length)
    let editorFontSize: CGFloat = 14

    let baseDescriptor: NSFontDescriptor
    if fontFamily.isEmpty {
        baseDescriptor = NSFont.systemFont(ofSize: editorFontSize).fontDescriptor
    } else {
        baseDescriptor = NSFont(name: fontFamily, size: editorFontSize)?.fontDescriptor
            ?? NSFont.systemFont(ofSize: editorFontSize).fontDescriptor
    }

    attrString.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
        let traits: NSFontDescriptor.SymbolicTraits
        if let existingFont = value as? NSFont {
            traits = existingFont.fontDescriptor.symbolicTraits
        } else {
            traits = []
        }
        let newDescriptor = baseDescriptor.withSymbolicTraits(traits) ?? baseDescriptor
        let newFont = NSFont(descriptor: newDescriptor, size: editorFontSize)
            ?? NSFont.systemFont(ofSize: editorFontSize)
        let sub = NSMutableAttributedString(attributedString: attrString.attributedSubstring(from: range))
        sub.addAttribute(.font, value: newFont, range: NSRange(location: 0, length: sub.length))
        sub.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: sub.length))
        normalized.append(sub)
    }

    return normalized
}
```

Call this function in `makeNSView`, in `textDidChange`, and after style toggles.

### Every boundingRect() Call Must Apply the Same Font Pipeline as drawTitle

Any code path that calls `boundingRect()` on a copy of an attributed string for layout purposes (overlay frames, hit areas, minimum resize width, etc.) must apply the **exact same font processing pipeline** as the rendering code. This means:

1. Resolve `defaultFont` from the style (font family + size)
2. Apply paragraph style (alignment)
3. **Enumerate + merge font traits** — do NOT simply overwrite `.font` with `defaultFont`

**Wrong (destroys per-character bold/italic traits):**
```swift
measureString.addAttribute(.font, value: defaultFont, range: NSRange(location: 0, length: measureString.length))
```

**Correct (merges traits):**
```swift
measureString.enumerateAttribute(.font, in: NSRange(location: 0, length: measureString.length), options: []) { value, range, _ in
    let traits: NSFontDescriptor.SymbolicTraits
    if let existingFont = value as? NSFont {
        traits = existingFont.fontDescriptor.symbolicTraits
    } else {
        traits = []
    }
    let baseDescriptor = defaultFont.fontDescriptor
    let mergedDescriptor = baseDescriptor.withSymbolicTraits(traits) ?? baseDescriptor
    let mergedFont = NSFont(descriptor: mergedDescriptor, size: style.fontSize) ?? defaultFont
    measureString.addAttribute(.font, value: mergedFont, range: range)
}
```

If you skip trait merging, the bounding box will be measured with the unbolded font, producing a smaller height than the rendered text when the user has applied bold formatting. If you skip applying the display font size, the bounding box will be measured at the editor font size (e.g., 14pt) instead of the display size (e.g., 48pt), producing wrong minimum resize constraints.

## Summary Rules

1. **Use `NSAttributedString.draw(at:)`** — never deprecated CGContext text methods
2. **Use `NSFont.boldSystemFont(ofSize:)`** — guaranteed available
3. **Calculate bounding box** with `.usesLineFragmentOrigin` and `.usesFontLeading`
4. **Draw background first** with `saveGState()`/`restoreGState()` to isolate fill state
5. **Use `CGPath(roundedRect:cornerWidth:cornerHeight:)`** for rounded corners
6. **Use `draw(at:)`** for single-line, **`draw(in:)`** for multi-line
7. **`draw(at:)` and `draw(in:)` both treat Y as baseline** — `y` is NOT the text top. Text top = `y - boundingBox.height`
8. **`boundingRect()` returns tight bounds** — `origin.x` is always ~0, not the aligned position within a wider rect
9. **Alignment moves text, not the box** — background spans full draw width; text offset is computed from alignment
10. **Merge font traits, don't overwrite** — enumerate existing font runs and merge symbolic traits with target family/size. Apply this in every code path that calls `boundingRect()`, not just the rendering code
11. **Always apply `.foregroundColor` explicitly** — the attributed string color may not match user settings
12. **Use `NSFontDescriptor.withSymbolicTraits`** — `NSFontManager.convert` two-argument forms don't exist in Swift

## Pitfalls

- **Every boundingRect() must use the same font pipeline as draw()** — If you measure the attributed string with different fonts than you render with, the overlay frame, hit area, or minimum resize width will be wrong. This includes applying the display font size (not editor size), the display font family, paragraph style, and merging per-character bold/italic traits. A plain `.font` overwrite destroys traits and produces wrong bounding boxes.
- **Text overlay rect origin must match draw() y coordinate** — When computing a SwiftUI hit-area overlay for CoreGraphics-rendered text, the rect's origin must be at the text baseline (`anchorYcg - boundingBox.height`), NOT at the text top (`anchorYcg`). The `canvasToPreviewFrame` function flips Y: `flippedY = canvasHeight - origin.y - height`. With origin at the text top, the flipped rect places the overlay above the actual text. Use the same `y` coordinate that `draw(at:)` receives.
- **`boundingRect()` returns tight bounds, not position** — `origin.x` is always ~0 (left edge of text), regardless of paragraph alignment. Cannot use it to compute where aligned text appears within a wider draw rect. Either span the background to full draw width, or compute text offset manually from alignment.
- **`draw(at:)` and `draw(in:)` both treat Y as baseline** — `draw(in:rect)` does NOT treat `rect.y` as the text top. Switching from `draw(at:)` to `draw(in:)` without adjusting Y shifts text upward. For title rendering with tight background, prefer `draw(at:)` with manual offset.
- **Alignment should move text within a fixed box** — When alignment changes, the background box should stay put and only the text inside should reposition. Do NOT shift the entire box based on alignment.

## Title Overlay with Background

Complete example for bottom-centered title with semi-transparent rounded background:

```swift
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 48),
    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
]
let title = NSAttributedString(string: titleText, attributes: attributes)

// Calculate bounding box
let boundingBox = title.boundingRect(
    with: CGSize(width: canvasWidth - 40, height: 100),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

// Bottom-center position
let x = (canvasWidth - boundingBox.width) / 2
let y = canvasHeight - boundingBox.height - 20

// Semi-transparent rounded background
context.saveGState()
context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
let bgPath = CGPath(roundedRect: CGRect(x: x - 12, y: y - 12, width: boundingBox.width + 24, height: boundingBox.height + 24), cornerWidth: 8, cornerHeight: 8, transform: nil)
context.addPath(bgPath)
context.fillPath()
context.restoreGState()

title.draw(at: CGPoint(x: x, y: y))
```

## Text Frame Estimation for Hit Areas

When you need to compute a SwiftUI hit-area overlay for CoreGraphics-rendered text, estimate the bounding box using the same font/paragraph attributes as `draw(at:)`:

```swift
var titleCanvasFrame: CGRect? {
    guard !titleText.isEmpty else { return nil }

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: fontColor
    ]
    let attributedString = NSAttributedString(string: titleText, attributes: attributes)
    let boundingBox = attributedString.boundingRect(
        with: CGSize(width: canvasWidth - 40, height: 100),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )

    let anchorX = positionX * canvasWidth
    let originX: CGFloat
    switch alignment {
    case .left: originX = anchorX
    case .right: originX = anchorX - boundingBox.width
    default: originX = anchorX - boundingBox.width / 2
    }

    // Convert normalized top-left position to bottom-left (CoreGraphics):
    let anchorYcg = canvasHeight - positionY * canvasHeight
    // Origin at text baseline (same y passed to draw(at:)):
    let originY = anchorYcg - boundingBox.height

    return CGRect(x: originX, y: originY, width: boundingBox.width, height: boundingBox.height)
}
```

**Critical:** The `originY` must be `anchorYcg - boundingBox.height` (the text baseline), NOT `anchorYcg`. This matches the `y` coordinate passed to `draw(at:)`. When this rect is later converted to preview coordinates via `canvasToPreviewFrame`, the Y-flip will produce a hit area that exactly covers the rendered text.

## Alignment-Aware Anchor Points

When text position is controlled by an anchor point, the anchor's meaning changes per alignment:

| Alignment | Anchor meaning | X calculation |
|---|---|---|
| Left | Left edge of text | `x = anchorX` |
| Center | Center of text | `x = anchorX - width/2` |
| Right | Right edge of text | `x = anchorX - width` |

This means dragging the text moves the anchor point, and the text re-aligns relative to it. The visual effect is that the text stays anchored to the cursor at the alignment-appropriate edge.

## Natural Text Bounds for Minimum Resize Width

When a text box is user-resizable, prevent it from shrinking below the unbounded natural width of the text content:

```swift
let naturalBounds = attributedString.boundingRect(
    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
let minWidth = naturalBounds.width
```

**Swift type ambiguity:** `.greatestFiniteMagnitude` is ambiguous without explicit type — both `Float` and `Double` have the property. Must use `CGFloat.greatestFiniteMagnitude`.

**Critical:** The `attributedString` being measured must have the display font size and family applied (with trait merging), not the editor font size. If you measure at 14pt when the text renders at 48pt, the minimum width will be ~3x too small and the user can shrink the box below the actual text content.
