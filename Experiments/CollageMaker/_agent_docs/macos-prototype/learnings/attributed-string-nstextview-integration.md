# NSAttributedString & NSTextView Integration — Learnings

**Date:** 2026-05-18 (updated from 2026-05-17)
**Session:** 25 (Round 8, full plan implementation) + Round 8.1 (title fixes)

---

## NSAttributedString Across the Full Stack

### Protocol Migration

Changing `title: String` to `titleAttrString: NSAttributedString` in `CollageAssembly` protocol required updating the protocol declaration, all 4 protocol methods, the `CollageAssembler` class implementation, and every call site in `CollageViewModel.updatePreview()` and `exportCollage()`. The change propagates in 3 layers:

1. **Protocol** — signature change
2. **Implementation** — parameter forwarding + `drawTitle` logic
3. **Caller** — captured `let` values before `Task.detached`

### NSAttributedString is Not Sendable

`NSAttributedString` does not conform to `Sendable`. Capturing `self.titleAttrString` inside `Task.detached { [weak self] in ... }` produces a compile error: "main actor-isolated property cannot be accessed from outside of the actor" + "non-Sendable type cannot exit main actor-isolated context". The fix mirrors the `NSColor` pattern: capture as a local `let` on the main thread before the detached task:

```swift
let titleAttrString = self.titleAttrString  // captured on @MainActor
// ...
previewTask = Task.detached { [weak self] in
    assembler.assemblePreviewWithCGImages(
        titleAttrString: titleAttrString,  // uses local let
        // ...
    )
}
```

### UserDefaults Migration

When replacing a persisted `String` with `NSAttributedString`, old users have the `"title"` key but not the new `"titleAttrString"` key. Migration pattern:

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

Use `NSKeyedArchiver` with `requiringSecureCoding: false` — matches the existing `NSColor` pattern in this codebase. Keep a computed `var title: String { titleAttrString.string }` for any code paths that only need the plain string.

---

## NSTextView via NSViewRepresentable

### Binding Sync via NSTextViewDelegate

The coordinator bridges `NSTextView` changes back to SwiftUI via `NSTextViewDelegate.textDidChange(_:)`:

```swift
func textDidChange(_ notification: Notification) {
    guard let textView = textView else { return }
    if let newStorage = textView.textStorage {
        attributedString = NSAttributedString(attributedString: newStorage)
    }
}
```

Key: create a copy with `NSAttributedString(attributedString:)` rather than assigning `NSTextStorage` directly, to avoid lifetime issues.

### textDidChange Does NOT Fire for Attribute-Only Changes

`NSTextViewDelegate.textDidChange(_:)` only fires when the string **content** changes (characters added, removed, or replaced). It does NOT fire when only attributes change (e.g., toggling bold, italic, underline on selected text). This means the SwiftUI binding and the ViewModel's `didSet` will not be triggered by style-only edits.

**Fix:** After any attribute-only mutation on `NSTextStorage`, explicitly read the text storage and assign it to the binding:

```swift
private func syncBinding() {
    guard let textView = textViewHolder.textView,
          let textStorage = textView.textStorage else { return }
    let normalized = normalizeForEditor(textStorage, fontFamily: currentFontFamily)
    attributedString = normalized
}
```

Call `syncBinding()` at the end of each style toggle method (`toggleBold`, `toggleItalic`, `toggleUnderline`). This ensures the binding updates, the ViewModel's `didSet` fires, and `updatePreview()` is called.

### Cursor Preservation with isEqual

`updateNSView` must not reset cursor/selection on every render. Use `NSTextStorage.isEqual(_:)` (not `==` or `===`) to compare content:

```swift
if !currentText.isEqual(attributedString) {
    let savedRange = textView.selectedRange
    textView.textStorage?.setAttributedString(attributedString)
    textView.selectedRange = clampedRange  // restore cursor
}
```

`isEqual` compares both string content and attributes. Using `===` would always trigger (different object instances), and comparing `.string` would miss attribute changes.

### NSTextView Configuration for SwiftUI Embedding

```swift
textView.drawsBackground = false       // Transparent background
textView.backgroundColor = NSColor.clear
textView.textContainer?.widthTracksTextView = true  // Auto-width
textView.textContainer?.heightTracksTextView = false // Fixed height
textView.textContainerInset = NSSize(width: 4, height: 4)
```

Without `drawsBackground = false`, the text view renders its own white background, conflicting with SwiftUI's styling.

### ObservableObject with PassthroughSubject

A lightweight holder class (`StyleableTextViewHolder`) that exposes `NSTextView?` to the SwiftUI parent for style queries needs `ObservableObject` conformance. The default `objectWillChange` is `ObservableObjectPublisher` which requires `send()` from within the class. For external notification:

```swift
class StyleableTextViewHolder: ObservableObject {
    let objectWillChange = PassthroughSubject<StyleableTextViewHolder, Never>()
    var textView: NSTextView? {
        didSet { objectWillChange.send(self) }
    }
}
```

This allows the `@StateObject` in the SwiftUI view to react when the representable assigns the text view.

---

## Editor Display vs. Rendered Output

### The Two-Layer Approach

The editor and the rendered image need different font sizes and colors, but the same style traits (bold, italic, underline). The solution is a two-layer approach:

1. **Editor normalization** — The `NSTextView` always displays text at a fixed size (14pt) and color (white), but preserves bold/italic/underline traits from the attributed string. A `normalizeForEditor` function strips size and color from the attributed string on load and on every text storage read, replacing them with editor-specific defaults while preserving symbolic traits.

2. **Render-time application** — `drawTitle` in `CollageAssembler` applies the real `fontSize`, `fontFamily`, and `fontColor` from `titleStyle` at render time, ensuring the final image reflects the user's settings.

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

This function is called:
- In `makeNSView` when loading text into the editor
- In `textDidChange` when the user types
- In `syncBinding` after style toggles

### Font Trait Merging in drawTitle

`drawTitle` must NOT simply overwrite the entire `.font` attribute across the full range, as this would destroy per-character bold/italic traits. Instead, it must enumerate existing font runs and merge their traits with the target font family and size:

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

This preserves bold/italic from the attributed string while applying the user's font family and size settings.

### drawTitle Must Apply fontColor Explicitly

`drawTitle` must apply `.foregroundColor` from `titleStyle.fontColor` across the full range. Without this, the text renders with whatever color is embedded in the attributed string (or the CGContext default, which is black). The `fontColor` attribute should be applied to the entire range (not per-run), since the user's color picker sets a single color for all title text:

```swift
mutable.addAttribute(.foregroundColor, value: titleStyle.fontColor, range: NSRange(location: 0, length: mutable.length))
```

### titleCanvasFrame Must Match drawTitle's Font (Including Trait Merging)

The `titleCanvasFrame` computed property in `CollageEditorView` measures the title's bounding box for the UI overlay. It must apply the **exact same font processing** as `drawTitle` before measuring — including the `enumerateAttribute` + `withSymbolicTraits` trait merging pattern. Simply overwriting `.font` with `defaultFont` across the full range **destroys per-character bold/italic traits**, producing a smaller bounding box than the actual rendered text when the user has applied bold/italic formatting.

**Wrong (destroys traits):**
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

### titleMinWidth Must Also Apply Full Style and Trait Merging

Any computed property that measures `titleAttrString` for layout purposes must apply the full `titleStyle` (font family, size, paragraph alignment) and merge font traits. If `titleMinWidth` measures at the editor font size (14pt) instead of the display font size (e.g., 48pt), the minimum resize constraint will be wrong and the user can shrink the text box below the actual text content.

**Rule of thumb:** Every code path that calls `boundingRect()` on a copy of `titleAttrString` must apply the same font processing pipeline as `drawTitle`: resolve `defaultFont` from `titleStyle`, apply paragraph style, enumerate + merge font traits, then measure.

---

## Font Trait Manipulation in Swift

### NSFontManager.convert API Limitations

`NSFontManager.shared.convert(_:toHaveTrait:)` and `convert(_:toWithoutTrait:)` (two-argument forms) are **not available** in Swift on macOS. The Swift-exposed API only has the three-argument form `convert(_:toFamily:toHaveTrait:)` where `toFamily` is `String` (not `String?`). Passing `nil` fails.

### NSFontDescriptor.withSymbolicTraits (Recommended)

The reliable approach for toggling bold/italic:

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

Key details:
- `withSymbolicTraits(_:)` returns **non-optional** `NSFontDescriptor` (not `Optional`)
- `NSFont(descriptor:size:)` returns `NSFont?` — it can fail if the system can't find a matching font
- Always provide a fallback for the `nil` case

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

`NSFont.fontTraits` doesn't exist as a property. `NSFontTraitMask.boldTrait` and `.italicTrait` static members don't exist in Swift.

### Enumerating Attribute Runs in a Selection

`textStorage.attributeRuns(in:)` is not callable as a function in Swift. Use `enumerateAttribute`:

```swift
textStorage.enumerateAttribute(.font, in: sel, options: []) { value, range, _ in
    if let font = value as? NSFont {
        // Apply per-run font transformation
    }
}
```

This iterates over each contiguous range with the same `.font` attribute value, allowing per-run style toggling.

---

## draw(in:) vs draw(at:) — Final Resolution

Session 21 reverted from `draw(in:)` to `draw(at:)` because `draw(in:)` treated `rect.y` as baseline, causing vertical misalignment with the background box. Session 25 re-applied `draw(in:)` with the correct understanding:

- **Both** `draw(at:)` and `draw(in:)` treat Y as the **baseline**
- `draw(in:)` respects `NSParagraphStyle.alignment` natively — text aligns within the rect
- `draw(at:)` always draws left-aligned at the point, requiring manual X offset
- The Session 21 vertical shift was caused by passing the wrong Y coordinate, not by `draw(in:)` semantics

For aligned text within a fixed-width box, `draw(in:)` is the correct choice:

```swift
attributedString.draw(in: CGRect(x: drawX, y: baselineY, width: drawWidth, height: boundingBox.height))
```

---

## Inline Search TextField in Form

`.searchable(text:prompt:)` places a search field at the top of the split view, outside the sidebar's `Form`. To embed search inside the sidebar:

```swift
Form {
    HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search images", text: $searchQuery).font(.caption)
        if !searchQuery.isEmpty {
            Button { searchQuery = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(6)
    .background(Color.secondary.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 6))

    Section("Images") { ... }
}
```

This gives a native-looking search bar with clear button, styled to match macOS form controls.

---

**Status:** Open
**Follow-up:** Test mocks for `CollageAssembly` protocol need `titleAttrString: NSAttributedString` parameter updates before running test suite.
