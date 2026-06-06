# Cross-View NSViewRepresentable Cascade — Learnings

**Date:** 2026-06-06
**Session:** 88 — Round-99 prep Phase 6 + color picker bug fix

---

## Cross-View `updateNSView` Cascade

When ANY `@Observable` property changes, SwiftUI re-renders the entire view tree. Every `NSViewRepresentable` in that tree has `updateNSView` called, even if the data it depends on hasn't changed. If an unrelated `NSViewRepresentable` performs unconditional mutations (e.g., `typingAttributes` assignment, `setAttributedString`), those mutations can trigger delegate callbacks that write to bindings, starting a re-render cascade that freezes other UI controls.

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

**Root cause:** `updateNSView` performs unconditional mutations on every SwiftUI re-render cycle, regardless of whether its own data changed.

**Fix 1 — Guard `typingAttributes` assignment:**
```swift
func updateNSView(_ textView: NSTextView, context: Context) {
    let targetFont = resolveFont(...)

    // Guard: only assign when font actually changed
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
```swift
func updateNSView(_ textView: NSTextView, context: Context) {
    // ... early returns for unchanged data ...

    // Block textDidChange during programmatic update
    context.coordinator.isUpdating = true
    defer { context.coordinator.isUpdating = false }

    textStorage.setAttributedString(normalized)
    attributedString = normalized
}
```

The coordinator's `isUpdating` flag (already used in `textDidChange` to guard against user-typing re-entrancy) is now also set from `updateNSView` to guard against programmatic re-entrancy. Both paths write to the same binding, so a single guard covers both.

**Fix 3 — Conditional re-normalization:**
```swift
// Only re-normalize when font family or alignment actually changed
let storageFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
let currentAlignment = (textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
    as? NSParagraphStyle)?.alignment
if storageFont?.fontName == targetFont.fontName,
   storageFont?.pointSize == targetFont.pointSize,
   currentAlignment == titleStyle.alignment {
    return  // Skip normalization and binding write
}
```

**Why the existing guard wasn't enough:** The existing `isUpdating` flag in `textDidChange` only guards against user-typing re-entrancy (user types → `textDidChange` → binding write → re-render → `updateNSView` → `typingAttributes` → `textDidChange`). The cross-view cascade originates from a completely different trigger (unrelated property change → SwiftUI re-render → `updateNSView`), which the existing guard doesn't intercept because `textDidChange` hasn't fired yet at that point.

---

## Diagnostic Clues

- **Color picker stuck on white/full opacity** — The cascade causes rapid re-renders that prevent the color picker's internal state from updating correctly.
- **Issue appears after editing text** — Empty `NSAttributedString` produces a no-op binding write. Non-empty text produces a meaningful write that triggers `titleAttrString.didSet`.
- **No crash, just frozen control** — The loop doesn't cause a stack overflow (SwiftUI batches renders), but it prevents the color picker from processing user input.

---

## Relationship to Existing Learnings

This extends `nsviarepresentable-color-picker-textview-reentrancy.md` (session 37). That file covers:
- Color equality trap in `updateNSView` (`well.color != color` guard)
- `textDidChange` re-entrancy from user typing
- `typingAttributes` guard in `updateNSView`

This file covers the **cross-view** variant: an unrelated ViewModel property change triggers the cascade, not user interaction with the text view itself. The same fixes apply (guard mutations in `updateNSView`, coordinator flag), but the trigger and diagnostic path are different.

---

**Status:** Closed
**Follow-up:** None
