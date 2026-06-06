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

## Cross-View `updateNSView` Cascade

The re-entrancy trap above covers the **self-referential** case (user types in the text view → cascade). A more insidious variant is the **cross-view** cascade: an unrelated `@Observable` property change triggers `updateNSView` on **every** `NSViewRepresentable` in the tree, including ones whose own data hasn't changed.

**Key insight:** When ANY `@Observable` property changes, SwiftUI re-renders the entire view tree. Every `NSViewRepresentable` has `updateNSView` called, even if the data it depends on hasn't changed. If an unrelated `NSViewRepresentable` performs unconditional mutations (e.g., `typingAttributes` assignment, `setAttributedString`), those mutations can trigger delegate callbacks that write to bindings, starting a re-render cascade that freezes other UI controls.

**Cascade path:**
```
User drags color picker → backgroundColor changes
→ @Observable marks dirty → SwiftUI re-renders entire tree
→ AttributedStringEditorView.updateNSView fires (unrelated to text)
→ typingAttributes = newAttrs triggers textDidChange
→ Coordinator writes normalized text to $attributedString binding
→ $viewModel.titleAttrString binding writes → titleAttrString.didSet
→ updatePreview() → another re-render → (loop)
→ Color picker frozen, only white/full opacity selectable
```

**Symptom:** A color picker becomes stuck — only white and full opacity are selectable. The issue manifests after editing text in a text view (which populates the `NSAttributedString` binding), because the cascade requires non-empty text to produce a meaningful binding write.

**Why the existing guard wasn't enough:** The existing `isUpdating` flag in `textDidChange` only guards against user-typing re-entrancy. The cross-view cascade originates from a completely different trigger (unrelated property change → SwiftUI re-render → `updateNSView`), which the existing guard doesn't intercept because `textDidChange` hasn't fired yet at that point.

**Fix 1 — Guard `typingAttributes` assignment:**

Compare current font against target before assigning:

```swift
func updateNSView(_ textView: NSTextView, context: Context) {
    let targetFont = resolveFont(...)

    if let currentFont = textView.typingAttributes[.font] as? NSFont,
       currentFont.fontName == targetFont.fontName,
       currentFont.pointSize == targetFont.pointSize {
        // Skip typingAttributes — prevents textDidChange trigger
    } else {
        textView.typingAttributes[.font] = targetFont
    }
}
```

**Fix 2 — Guard text storage mutations with coordinator flag:**

Set `isUpdating` from `updateNSView` to guard against programmatic re-entrancy:

```swift
func updateNSView(_ textView: NSTextView, context: Context) {
    // ... early returns for unchanged data ...

    context.coordinator.isUpdating = true
    defer { context.coordinator.isUpdating = false }

    textStorage.setAttributedString(normalized)
    attributedString = normalized
}
```

The coordinator's `isUpdating` flag (already used in `textDidChange` to guard against user-typing re-entrancy) is now also set from `updateNSView`. Both paths write to the same binding, so a single guard covers both.

**Fix 3 — Conditional re-normalization:**

Only re-normalize when font family or alignment actually changed:

```swift
let storageFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
let currentAlignment = (textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
    as? NSParagraphStyle)?.alignment
if storageFont?.fontName == targetFont.fontName,
   storageFont?.pointSize == targetFont.pointSize,
   currentAlignment == titleStyle.alignment {
    return  // Skip normalization and binding write
}
```

**Diagnostic clues:**
- **Color picker stuck on white/full opacity** — The cascade causes rapid re-renders that prevent the color picker's internal state from updating correctly.
- **Issue appears after editing text** — Empty `NSAttributedString` produces a no-op binding write. Non-empty text produces a meaningful write that triggers `titleAttrString.didSet`.
- **No crash, just frozen control** — The loop doesn't cause a stack overflow (SwiftUI batches renders), but it prevents the color picker from processing user input.
