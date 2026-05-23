# Codable AppKit Types

Several AppKit types don't conform to `Codable`. When your models need persistence, use manual encoding.

## NSColor via NSKeyedArchiver

`NSColor` doesn't conform to `Codable`. A wrapper struct also can't auto-synthesize because the underlying type doesn't conform. Use custom `encode(to:)`/`init(from:)` with `NSKeyedArchiver`:

```swift
struct TitleStyle: Codable, Equatable {
    var fontColor: NSColor = .black
    var fontFamily: String = ""
    var fontSize: Double = 24
}

extension TitleStyle {
    private enum CodingKeys: String, CodingKey {
        case fontColorData, fontFamily, fontSize
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fontFamily, forKey: .fontFamily)
        try c.encode(fontSize, forKey: .fontSize)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: fontColor, requiringSecureCoding: false) {
            try c.encode(data, forKey: .fontColorData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try c.decode(String.self, forKey: .fontFamily)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        if let data = try? c.decode(Data.self, forKey: .fontColorData),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            fontColor = color
        } else {
            fontColor = .black  // fallback
        }
    }
}
```

**Critical:** Keep `Codable` on the struct declaration only. Put custom `encode`/`init(from:)` in an extension **without** re-declaring `: Codable`. Swift sees two separate conformances and produces "redundant conformance" errors.

```swift
struct MyStyle: Codable { ... }      // Codable here
extension MyStyle {                   // No : Codable here
    func encode(to encoder: Encoder) throws { ... }
    init(from decoder: Decoder) throws { ... }
}
```

## Backward-Compatible Codable with `decodeIfPresent`

When adding new fields to an existing `Codable` model, use `decodeIfPresent` with a fallback default so saved data without the new keys decodes gracefully instead of crashing:

```swift
struct TitleStyle: Codable, Equatable {
    var positionX: CGFloat
    var positionY: CGFloat

    static let `default` = TitleStyle(
        positionX: 0.5,
        positionY: 0.88
    )
}

extension TitleStyle {
    private enum CodingKeys: String, CodingKey {
        case positionX, positionY, // ... other keys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Existing fields (required):
        // ...
        // New fields (optional with fallback):
        positionX = try c.decodeIfPresent(CGFloat.self, forKey: .positionX)
            ?? TitleStyle.default.positionX
        positionY = try c.decodeIfPresent(CGFloat.self, forKey: .positionY)
            ?? TitleStyle.default.positionY
    }
}
```

**Key points:**
- Existing saved JSON without the new keys decodes to defaults instead of crashing
- Always pair with a `static let default` that provides the fallback values
- Use `decodeIfPresent` for all new optional fields added to persisted models

## Effective Width Helper for Backward Compatibility

When adding a custom width property to a model where "use default" is the zero value, a helper method centralizes the fallback logic:

```swift
func effectiveWidth(canvasWidth: CGFloat) -> CGFloat {
    if width > 0 { return width }
    return canvasWidth - 40  // default: full canvas minus padding
}
```

This avoids duplicating the `width > 0 ? width : canvasWidth - 40` check at every call site (assembler, editor view, etc.).

## NSAttributedString via NSKeyedArchiver

`NSAttributedString` doesn't conform to `Codable`. Archive with `NSKeyedArchiver` using `requiringSecureCoding: false` (matches the `NSColor` pattern):

```swift
if let data = try? NSKeyedArchiver.archivedData(withRootObject: attrString, requiringSecureCoding: false) {
    // encode data
}

if let data = /* decoded */,
   let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
    // use attr
}
```

### UserDefaults Migration from String to NSAttributedString

When replacing a persisted `String` with `NSAttributedString`, old users have the old key but not the new one. Migration pattern:

```swift
var titleAttrString: NSAttributedString = {
    if let data = UserDefaults.standard.data(forKey: "titleAttrString"),
       let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
        return attr
    }
    // Fallback: migrate from old plain-text key
    if let oldTitle = UserDefaults.standard.string(forKey: "title"), !oldTitle.isEmpty {
        return NSAttributedString(string: oldTitle)
    }
    return NSAttributedString(string: "")
}()
```

Keep a computed `var title: String { titleAttrString.string }` for code paths that only need the plain string.

## NSTextAlignment via rawValue

`NSTextAlignment` doesn't conform to `Codable` but has `rawValue: Int`:

```swift
try container.encode(alignment.rawValue, forKey: .alignment)
alignment = NSTextAlignment(rawValue: try container.decode(Int.self, forKey: .alignment)) ?? .center
```

## Persisting Codable models to UserDefaults

For a `Codable` struct with non-Codable members (like `NSColor`), persist via JSON + `NSKeyedArchiver` round-trip:

```swift
func saveToUserDefaults() {
    if let data = try? JSONEncoder().encode(self) {
        UserDefaults.standard.set(data, forKey: "titleStyle")
    }
}

static func loadFromUserDefaults() -> TitleStyle {
    guard let data = UserDefaults.standard.data(forKey: "titleStyle"),
          let style = try? JSONDecoder().decode(TitleStyle.self, from: data) else {
        return TitleStyle()
    }
    return style
}
```

Combine with `@Observable` stored property + `didSet` for persistence and live preview in one assignment:

```swift
@MainActor @Observable final class ViewModel {
    var titleStyle: TitleStyle = .loadFromUserDefaults() {
        didSet {
            titleStyle.saveToUserDefaults()
            updatePreview()
        }
    }
}
```

## Permutation-Based Content Reordering

When UI elements have fixed positions (panel slots) but variable content (images), use a `[Int]` permutation array instead of directly mutating the content array:

```swift
@MainActor @Observable final class CollageViewModel {
    var images: [ImageItem] = []
    // customImageOrder[i] = index into images that occupies panel slot i
    var customImageOrder: [Int] = [] {
        didSet { regenerateLayout() }
    }

    func swapPanelImages(at a: Int, and b: Int) {
        customImageOrder.swapAt(a, b)
    }
}
```

**Key points:**
- **`order[slot] = contentIndex`** — panel slot `i` displays `images[customImageOrder[i]]`
- **Swapping content is a single `swapAt()`** — panel frames never change, layout doesn't rebuild
- **Crop state stays stable** — crops are keyed by panel UUID, not image index
- **Reset on count change** — when images are added/removed, reset to `Array(0..<images.count)`
- **Persistence** — JSON-encode `[Int]` to UserDefaults; decode with fallback to default identity order
- **`panelAssignments` bridge** — A `[UUID: Int]` dict maps each panel UUID to its current image index. Populated from `customImageOrder` in `regenerateLayout()`, updated by `swapPanelImages()`. The assembler reads `panelAssignments` for rendering, so the permutation never needs to reach the assembler layer
- **Sidebar reorder remapping** — When the sidebar image order changes, `customImageOrder` must be remapped using an inverse permutation so the canvas layout stays stable. This is error-prone; test thoroughly
- **Consumer consistency** — When a mapping layer exists between UI slots and content (e.g., `panelAssignments: [UUID: Int]`), EVERY code path that resolves "which content belongs to this slot?" must use the mapping, not the slot's raw property. Resolution pattern: `effectiveIndex = mapping[slotId] ?? slot.defaultIndex`. A stale slot property (e.g., `panel.imageIndex`) is a latent bug — the preview may render correctly while scroll/pan uses wrong bounds, causing coordinate jumps that are decoupled from the root cause

**When to use vs direct array mutation:**

| Use permutation when... | Use direct mutation when... |
|---|---|
| Panel slots have fixed positions (layout-driven) | Order is the only concern (list, sidebar) |
| Per-panel state (crop, zoom) is keyed by slot ID | No per-slot state exists |
| You need to swap content without rebuilding layout | You're adding/removing items |
