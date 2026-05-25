# NSTextView Binding — NSAttributedString in NSViewRepresentable

When wrapping `NSTextView` in `NSViewRepresentable` for rich text editing, use `NSAttributedString` bindings instead of plain `String`.

## Basic Pattern

```swift
struct AttributedTextView: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = textView.textStorage ?? NSAttributedString(string: "")
        if !currentText.isEqual(attributedString) {
            let savedRange = textView.selectedRange
            textView.textStorage?.setAttributedString(attributedString)
            let clampedRange = NSRange(
                location: min(savedRange.location, attributedString.length),
                length: min(savedRange.length, attributedString.length - min(savedRange.location, attributedString.length))
            )
            textView.selectedRange = clampedRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedString: $attributedString)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var attributedString: NSAttributedString

        init(attributedString: Binding<NSAttributedString>) {
            _attributedString = attributedString
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let newStorage = textView.textStorage else { return }
            attributedString = NSAttributedString(attributedString: newStorage)
        }
    }
}
```

## Critical Details

- **`isEqual` for cursor preservation** — Use `NSTextStorage.isEqual(_:)` (not `==` or `===`) to compare content before updating. `isEqual` compares both string content and attributes. Using `===` always triggers (different instances), and comparing `.string` misses attribute changes.
- **Copy with `NSAttributedString(attributedString:)`** — Create a copy in `textDidChange` rather than assigning `NSTextStorage` directly, to avoid lifetime issues.
- **`drawsBackground = false`** — Without this, the text view renders its own white background, conflicting with SwiftUI styling.
- **`widthTracksTextView = true`** — Auto-width for single-line or wrapping text.
- **`heightTracksTextView = false`** — Fixed height to prevent the text view from growing unbounded.

## textDidChange Does NOT Fire for Attribute-Only Changes

`NSTextViewDelegate.textDidChange(_:)` only fires when string **content** changes (characters added, removed, or replaced). It does NOT fire for attribute-only changes (e.g., toggling bold, italic, underline). The SwiftUI binding and ViewModel's `didSet` will not be triggered by style-only edits.

**Fix:** After any attribute-only mutation on `NSTextStorage`, explicitly read and assign:

```swift
private func syncBinding() {
    guard let textView = textView,
          let textStorage = textView.textStorage else { return }
    attributedString = NSAttributedString(attributedString: textStorage)
}
```

Call `syncBinding()` at the end of each style toggle method (`toggleBold`, `toggleItalic`, `toggleUnderline`).

## ObservableObject Holder with PassthroughSubject

A lightweight holder class that exposes `NSTextView?` to the SwiftUI parent for style queries needs `ObservableObject` conformance. Use `PassthroughSubject` for external notification:

```swift
class TextViewHolder: ObservableObject {
    let objectWillChange = PassthroughSubject<TextViewHolder, Never>()
    var textView: NSTextView? {
        didSet { objectWillChange.send(self) }
    }
}
```

This allows `@StateObject` in the SwiftUI view to react when the representable assigns the text view.

## Re-entrancy Cascade Trap

When a coordinator's `textDidChange` normalizes text and assigns to a SwiftUI binding, the binding update triggers SwiftUI's render cycle, which calls `updateNSView`. If `updateNSView` modifies `typingAttributes` or `defaultParagraphStyle`, this mutates `NSTextStorage` and fires another `textDidChange`, creating a recursive loop that corrupts state.

**Cascade path:**
```
User types → textDidChange → normalize → attributedString = normalized
→ SwiftUI re-renders → updateNSView → typingAttributes = newAttrs
→ NSTextStorage mutates → textDidChange → (loop)
```

**Symptom:** After changing a color or other style, editing text causes the color to reset. The recursive loop corrupts intermediate state.

**Fix 1 — Coordinator guard flag:**
```swift
final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var attributedString: NSAttributedString
    private var isUpdating = false

    init(attributedString: Binding<NSAttributedString>) {
        _attributedString = attributedString
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        guard let textView = notification.object as? NSTextView,
              let newStorage = textView.textStorage else { return }
        attributedString = NSAttributedString(attributedString: newStorage)
    }
}
```

**Fix 2 — updateNSView early return:** Only update `typingAttributes` when the underlying value actually changed. Compare specific properties before assigning:

```swift
func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }

    // Content check (as above)
    let currentText = textView.textStorage ?? NSAttributedString(string: "")
    if !currentText.isEqual(attributedString) {
        let savedRange = textView.selectedRange
        textView.textStorage?.setAttributedString(attributedString)
        textView.selectedRange = NSRange(
            location: min(savedRange.location, attributedString.length),
            length: min(savedRange.length, max(0, attributedString.length - savedRange.location))
        )
    }

    // Style check — only assign when font actually differs
    let targetFont = NSFont.systemFont(ofSize: 13)  // or your font source
    if let currentFont = textView.typingAttributes[.font] as? NSFont,
       currentFont.fontName == targetFont.fontName,
       currentFont.pointSize == targetFont.pointSize {
        return  // No style change needed — skip typingAttributes assignment
    }
    textView.typingAttributes[.font] = targetFont
}
```

Both fixes together eliminate the cascade: the guard prevents re-entrant normalization, and the early return prevents unnecessary `typingAttributes` mutations.
