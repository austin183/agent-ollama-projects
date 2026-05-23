# NSViewRepresentable Color Picker & Text View Re-entrancy — Learnings

**Date:** 2026-05-21
**Session:** 37 — Round 11 change request

---

## NSColorWell: Color Equality Trap in updateNSView

`NSColor` equality (`==`) compares the underlying `CGColor` values, which can differ for visually identical colors in different color spaces (e.g., sRGB vs Display P3). Using `well.color != color` as a guard in `updateNSView` means the color well may not receive binding updates, causing stale state.

**Symptom:** User changes a color, the well updates. Later, the binding changes (e.g., from another view or persistence load), but the well displays the old color because `!=` returned `false`.

**Anti-pattern:**
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    if well.color != color {  // Can be false for same visual color, different color space
        well.color = color
    }
}
```

**Fix:** Always unconditionally assign the binding value:
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    well.color = color  // Always push — no equality guard
}
```

**Also:** `makeNSView` must initialize `well.color = color` from the binding. Without this, the color well starts with a default system color, which can conflict with the binding's initial value.

```swift
func makeNSView(context: Context) -> NSColorWell {
    let well = NSColorWell()
    well.isContinuous = true
    well.color = color  // Initialize from binding
    well.target = context.coordinator
    well.action = #selector(Coordinator.colorChanged(_:))
    return well
}
```

---

## NSTextView: textDidChange Re-entrancy Cascade

When a coordinator's `textDidChange` normalizes text and assigns to a SwiftUI binding, the binding update triggers SwiftUI's render cycle, which calls `updateNSView`. If `updateNSView` modifies `typingAttributes` or `defaultParagraphStyle`, this can mutate the `NSTextStorage` and fire another `textDidChange`, creating a recursive loop that corrupts state.

**Cascade path:**
```
User types → textDidChange → normalizeForEditor → attributedString = normalized
→ SwiftUI re-renders → updateNSView → typingAttributes = newAttrs
→ NSTextStorage mutates → textDidChange → (loop)
```

**Symptom:** After changing a color or other style, editing text causes the color to reset to a default value. The recursive loop corrupts intermediate state.

**Fix 1 — Coordinator guard flag:**
```swift
class Coordinator: NSObject, NSTextViewDelegate {
    private var isUpdating = false

    func textDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let normalized = normalizeForEditor(textStorage, ...)
        attributedString = normalized
    }
}
```

**Fix 2 — updateNSView early return:**
Only update `typingAttributes` when the underlying value actually changed. Compare the current font's `fontName` and `pointSize` against the target before assigning:

```swift
func updateNSView(_ textView: NSTextView, context: Context) {
    let targetFont = resolveFont(...)

    if let currentFont = textView.typingAttributes[.font] as? NSFont,
       currentFont.fontName == targetFont.fontName,
       currentFont.pointSize == targetFont.pointSize {
        return  // No change needed — skip typingAttributes assignment
    }

    textView.typingAttributes[.font] = targetFont
    // ...
}
```

Both fixes together eliminate the cascade: the guard prevents re-entrant normalization, and the early return prevents unnecessary `typingAttributes` mutations.

---

## NSColorWell: Alpha Value Handling

When the bound color has an alpha component (e.g., `NSColor.black.withAlphaComponent(0.4)`), the `NSColorWell` must be configured to handle alpha. Set `well.alphaValue = 1.0` in `makeNSView` to ensure the color well displays alpha correctly.

**Note:** `NSColorWell` has no `allowsAlpha` property on macOS (that exists on iOS). The `alphaValue` property controls whether the well itself renders with alpha.

---

**Status:** Closed
**Follow-up:** None
