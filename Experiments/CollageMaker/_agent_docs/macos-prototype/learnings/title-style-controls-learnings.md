# Title Style Controls — Codable NSColor & Font Picker Patterns — Learnings

**Date:** 2026-05-14
**Session:** 13
**Purpose:** Document learnings from implementing multiline title, font controls, and TitleStyle model in CollageMaker.

---

## What Worked

- **`@Observable` stored property with custom Codable persistence** — `TitleStyle` is a `Codable` struct persisted as JSON to UserDefaults via `NSKeyedArchiver` round-trip for the embedded `NSColor`. The `didSet` on `titleStyle` calls `saveToUserDefaults()` then `updatePreview()`, giving both persistence and live preview in one property assignment.
- **`Menu` + `Picker` for font family selection** — Wrapping a `Picker` inside a `Menu` avoids the native `.pickerStyle(.menu)` height limit. The `Picker` inside the `Menu` body can scroll through all `NSFontManager.shared.availableFontFamilies` without truncation.
- **`NSFontManager.shared.availableFontFamilies`** — Returns font family names (e.g., "Helvetica Neue", "SF Pro Display"), not individual font names. These work directly with `NSFont(name:size:)`. Empty string fallback to `NSFont.boldSystemFont(ofSize:)` covers the "System Default" case.
- **Custom `Codable` for `Codable`-nonconforming types** — When a `Codable` struct contains a non-`Codable` type (like `NSColor`), use custom `CodingKeys` + `encode(to:)`/`init(from:)` that serialize the problematic property as `Data` using `NSKeyedArchiver`/`NSKeyedUnarchiver`.

## What Didn't Work / Gaps

- **`NSColor` doesn't conform to `Codable`** — Cannot auto-synthesize `Codable` for a struct containing `NSColor`. Attempting `struct CodableNSColor: Codable { let color: NSColor }` also fails — the wrapper can't auto-synthesize because the underlying type still doesn't conform. Must use manual encoding:
  ```swift
  // Encode
  if let data = try? NSKeyedArchiver.archivedData(withRootObject: fontColor, requiringSecureCoding: false) {
      try container.encode(data, forKey: .fontColorData)
  }
  // Decode
  if let data = try? container.decode(Data.self, forKey: .fontColorData),
     let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
      fontColor = color
  }
  ```

- **Redundant `Codable` conformance** — Declaring `struct TitleStyle: Codable` on the struct definition, then `extension TitleStyle: Codable` for custom `encode`/`init(from:)` produces "redundant conformance" errors. Swift sees two separate conformances. Fix: keep `Codable` on the struct declaration only, put custom `encode`/`init(from:)` in an extension **without** re-declaring the conformance:
  ```swift
  struct TitleStyle: Codable, Equatable { ... }  // Codable here
  extension TitleStyle {                          // No : Codable here
      func encode(to encoder: Encoder) throws { ... }
      init(from decoder: Decoder) throws { ... }
  }
  ```

- **`TextArea` requires macOS 26+** — The plan called for `TextArea` for multiline input, but the project targets macOS 26.4 SDK with a lower deployment target. `TextArea` is unavailable. `TextEditor` is the macOS 12+ alternative but has different styling: no `.textFieldStyle()`, different padding behavior.

- **`TextEditor.border(NSColor, width:)` type mismatch** — `.border()` takes `some ShapeStyle`, not a raw `NSColor`. While `NSColor` technically conforms to `ShapeStyle`, the compiler couldn't infer it in context. Replaced with `.background(Color.secondary.opacity(0.1))` + `.overlay(RoundedRectangle.stroke(Color.secondary.opacity(0.3), lineWidth: 1))`.

## Key Patterns

### Codable Struct with NSColor

```swift
struct MyStyle: Codable {
    var color: NSColor
    var name: String
}

extension MyStyle {
    private enum CodingKeys: String, CodingKey {
        case colorData, name
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            try c.encode(data, forKey: .colorData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        if let data = try? c.decode(Data.self, forKey: .colorData),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            color = c
        } else {
            color = .black  // fallback
        }
    }
}
```

### Font Family Picker with Menu

```swift
private var fontFamilies: [String] {
    ["(System Default)"] + NSFontManager.shared.availableFontFamilies.sorted()
}

Menu {
    Picker("Font", selection: $selectedFamily) {
        ForEach(fontFamilies, id: \.self) { family in
            Text(family).tag(family)
        }
    }
} label: {
    HStack {
        Text(selectedFamily).lineLimit(1)
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
    }
}
```

### NSTextAlignment Codable

`NSTextAlignment` doesn't conform to `Codable` but has `rawValue: Int`. Encode/decode via the raw value:
```swift
try container.encode(alignment.rawValue, forKey: .alignment)
alignment = NSTextAlignment(rawValue: try container.decode(Int.self, forKey: .alignment)) ?? .center
```

## Next Steps

- Phase 2: Title drag-to-position on canvas (add `positionX/Y` to `TitleStyle`, canvas gesture for free-form placement)
- Phase 3: Panel drag-to-reorder (canvas `DragGesture` that swaps images between panels)

---
**Status:** Closed
**Follow-up:** Round 3 Phase 2 (title positioning), Phase 3 (panel drag reorder)
