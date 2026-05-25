# HIG: Accessibility

## SwiftUI Accessibility Modifiers

```swift
Text("Export")
    .accessibilityLabel("Export collage as JPEG")
    .accessibilityHint("Opens save dialog")
    .accessibilityValue("Quality: 92 percent")
    .accessibilityAddTraits(.isButton)
```

| Modifier | Purpose |
|---|---|
| `.accessibilityLabel(_:)` | What the element is |
| `.accessibilityValue(_:)` | Current value (slider position, toggle state) |
| `.accessibilityHint(_:)` | What happens when activated |
| `.accessibilityAddTraits(_:)` | Additional state: `.isButton`, `.isSelected`, `.isHeader` |
| `.accessibilityHidden(true)` | Remove from VoiceOver rotation |
| `.accessibilityElement(children: .ignore)` | Group children under single element |
| `.accessibilitySortPriority(1)` | Control VoiceOver reading order |

## Color Contrast

Meet WCAG Level AA minimum contrast ratios:
- Up to 17pt text: **4.5:1** minimum
- 18pt+ text: **3:1** minimum
- Check in both light and dark appearances

**Prefer system-defined colors** (`.red`, `.blue`, etc.) — they have accessible variants that adapt to "Increase Contrast" setting.

## Color Usage

- **Convey information with more than color alone** — add shapes, icons, or text alongside color for state changes
- Red-green and blue-orange pairings are problematic for color blind users
- Selected panel: white border (non-color indicator) is correct

## Control Sizing

- macOS: **60x60pt** default, **28x28pt** minimum control size
- Padding between elements: **12pt** with bezel, **24pt** without

## Reduce Motion

Respect the system "Reduce Motion" setting:

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// In animation code:
let animation: Animation? = reduceMotion
    ? nil  // no animation, just snap to final state
    : .spring(response: 0.3)
```

- Reduce automatic/repetitive animations
- Tighten springs, track with gestures
- Avoid z-axis animations
- Replace transitions with fades

## Keyboard Access

- Support Full Keyboard Access for keyboard-only navigation
- All inspector controls (sliders, pickers, buttons) must be keyboard-navigable
- Tab/arrow keys for navigation between controls

## Testing

- Test with VoiceOver enabled (Command-F5)
- Use Accessibility Inspector (Xcode > Open Developer Tool) for auditing
