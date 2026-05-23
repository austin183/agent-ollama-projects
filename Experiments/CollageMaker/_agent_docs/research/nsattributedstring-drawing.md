# NSAttributedString Drawing — Title Overlay in CoreGraphics

## Drawing Text in a CGContext

### The Deprecated API (Avoid)
```swift
// DEPRECATED — CGContext text methods
context.selectFont("Helvetica-Bold", size: 48, textEncoding: .macRoman)
context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.8)
context.showTextAtPoint(x: 960, y: 1040, string: "Title", length: 5)
```

**Problems:**
- Limited font support (PostScript font names only)
- No attributed text (bold, italic, color changes within string)
- Manual text encoding handling
- Deprecated in macOS 10.6+

### The Modern API: NSAttributedString
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

## Coordinate System Considerations

### CGContext Default: Bottom-Left Origin
```swift
// Default CGContext — origin at bottom-left
let context = CGContext(...)!

// NSAttributedString.draw(at:) uses the context's coordinate system
// After flipping to top-left:
context.translateBy(x: 0, y: CGFloat(canvasHeight))
context.scaleBy(x: 1, y: -1)

// Now (0, 0) is top-left — draw coordinates are intuitive
attributedString.draw(at: CGPoint(x: 20, y: canvasHeight - 60))
```

### Calculating Bottom-Center Position
For a title at the bottom-center of the canvas:
```swift
let title = NSAttributedString(string: titleText, attributes: attributes)
let boundingBox = title.boundingRect(
    with: CGSize(width: canvasWidth - 40, height: 100),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

let x = (canvasWidth - boundingBox.width) / 2
let y = canvasHeight - boundingBox.height - 20  // 20pt margin from bottom

title.draw(at: CGPoint(x: x, y: y))
```

## Semi-Transparent Background for Title

### Drawing a Background Rectangle
```swift
// Background rect — slightly larger than text
let padding: CGFloat = 12
let bgRect = boundingBox.insetBy(dx: -padding, dy: -padding)
let bgOrigin = CGPoint(x: x - padding, y: y - padding)

// Draw semi-transparent background
context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
context.fill(CGRect(origin: bgOrigin, size: CGSize(
    width: boundingBox.width + padding * 2,
    height: boundingBox.height + padding * 2
)))

// Optional: rounded corners
let rectPath = CGPath(
    roundedRect: CGRect(origin: bgOrigin, size: CGSize(
        width: boundingBox.width + padding * 2,
        height: boundingBox.height + padding * 2
    )),
    cornerWidth: 8,
    cornerHeight: 8,
    transform: nil
)
context.addPath(rectPath)
context.fillPath()

// Then draw text on top
title.draw(at: CGPoint(x: x, y: y))
```

### Using saveGState/restoreGState
Prevent the background fill from affecting subsequent drawing:
```swift
context.saveGState()
context.setFillColor(backgroundColor.cgColor)
context.fill(backgroundRect)
context.restoreGState()  // Restore fill color, transform, clip state
```

## Font Selection

### System Fonts (Always Available)
```swift
NSFont.systemFont(ofSize: 48)                    // Regular
NSFont.boldSystemFont(ofSize: 48)                // Bold
NSFont.mediumSystemFont(ofSize: 48)              // Medium
NSFont.semiboldSystemFont(ofSize: 48)            // Semi-bold
NSFont.labelFont(ofSize: 48)                     // For labels
NSFont.titleFont(ofSize: 48)                     // For titles
```

### Custom Fonts
```swift
// By name — must be available on the system
NSFont(name: "Helvetica Neue", size: 48)
NSFont(name: "Avenir-Heavy", size: 48)

// Font descriptor for styling
let descriptor = NSFontDescriptor(
    name: "Helvetica Neue",
    size: 48,
    attributes: [.traits: [NSFontDescriptor.TraitKey.bold: 1]]
)
NSFont(descriptor: descriptor, size: 48)
```

### Dynamic Type
For accessibility, consider scaling font size:
```swift
// Use point size that scales with user preferences
let fontSize: CGFloat = 48
// Or use NSFont.Metrics for adaptive sizing
```

## Text Truncation and Line Breaking

### Single Line with Truncation
```swift
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 48),
    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
]

// Check if text fits; truncate if needed
let maxWidth = canvasWidth - 40
let fullString = NSAttributedString(string: titleText, attributes: attributes)
let boundingBox = fullString.boundingRect(
    with: CGSize(width: maxWidth, height: 100),
    options: [.usesLineFragmentOrigin]
)

if boundingBox.width > maxWidth {
    // Truncate with ellipsis
    let truncated = titleText.prefix(while: { _ in true })  // Implement truncation
    // Or use NSString's truncation methods
    let nsString = titleText as NSString
    let truncatedString = nsString.truncated(toWidth: maxWidth, font: NSFont.boldSystemFont(ofSize: 48))
}
```

### Multi-Line Text
```swift
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center
paragraphStyle.lineBreakMode = .byWordWrapping

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 48),
    .foregroundColor: NSColor.white.withAlphaComponent(0.8),
    .paragraphStyle: paragraphStyle
]

let constrainedSize = CGSize(width: canvasWidth - 40, height: 200)
let boundingBox = attributedString.boundingRect(
    with: constrainedSize,
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

// Draw in a rect for proper line breaking
attributedString.draw(in: CGRect(x: 20, y: y, width: canvasWidth - 40, height: boundingBox.height))
```

## Drawing in CollageAssembler Context

### Full Example
```swift
private func drawTitle(
    _ title: String,
    in context: CGContext,
    canvasSize: CGSize
) {
    guard !title.isEmpty else { return }
    
    let fontSize: CGFloat = 48
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ]
    
    let attributedString = NSAttributedString(string: title, attributes: attributes)
    
    // Calculate bounding box
    let maxWidth = canvasSize.width - 40
    let boundingBox = attributedString.boundingRect(
        with: CGSize(width: maxWidth, height: 100),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    
    // Position: bottom-center with margin
    let padding: CGFloat = 12
    let x = (canvasSize.width - boundingBox.width) / 2 - padding
    let y = canvasSize.height - boundingBox.height - 20 - padding
    
    // Draw semi-transparent background
    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
    let bgRect = CGRect(x: x, y: y, width: boundingBox.width + padding * 2, height: boundingBox.height + padding * 2)
    let roundedPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    context.addPath(roundedPath)
    context.fillPath()
    context.restoreGState()
    
    // Draw text (centered within background)
    let textX = (canvasSize.width - boundingBox.width) / 2
    let textY = canvasSize.height - boundingBox.height - 20
    attributedString.draw(at: CGPoint(x: textX, y: textY))
}
```

## Performance Notes

- `NSAttributedString.boundingRect(with:options:)` is fast for short strings
- Font loading is cached by the system — no per-call overhead after first use
- For static titles, pre-compute the bounding box and position
- `draw(at:)` vs `draw(in:)` — use `draw(at:)` for single-line, `draw(in:)` for multi-line

## Summary: CollageMaker Title Rules

1. **Use `NSAttributedString.draw(at:)`** — not deprecated CGContext text methods
2. **Use `NSFont.boldSystemFont(ofSize:)`** — guaranteed available, scales with system
3. **Calculate bounding box** with `.usesLineFragmentOrigin` and `.usesFontLeading` options
4. **Draw background first** with `saveGState()`/`restoreGState()` to isolate fill state
5. **Remember coordinate system** — after flip, (0,0) is top-left; bottom position is `canvasHeight - height - margin`
6. **Consider text truncation** for long titles that exceed canvas width
7. **Use `CGPath(roundedRect:cornerWidth:cornerHeight:)`** for rounded background corners
