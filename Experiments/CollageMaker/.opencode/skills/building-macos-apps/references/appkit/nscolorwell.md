# NSColorWell — Wrapping in NSViewRepresentable

When wrapping `NSColorWell` in `NSViewRepresentable`, bind to `NSColor` with a coordinator for color change callbacks.

## Basic Pattern

```swift
struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isContinuous = true
        well.color = color  // Initialize from binding — never omit
        well.alphaValue = 1.0  // Enable alpha display if color may have transparency
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color  // Always assign unconditionally — no equality guard
        well.target = context.coordinator    // Re-set every update — NSColorWell may reset these
        well.action = #selector(Coordinator.colorChanged(_:))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    final class Coordinator: NSObject {
        @Binding var color: NSColor

        init(color: Binding<NSColor>) {
            _color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color = sender.color
        }
    }
}
```

## Color Equality Trap

`NSColor ==` compares underlying `CGColor` values, which can differ for visually identical colors in different color spaces (e.g., sRGB vs Display P3). Using `well.color != color` as a guard in `updateNSView` means the color well may not receive binding updates, causing stale state.

**Anti-pattern:**
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    if well.color != color {  // FALSE for same visual color, different color space
        well.color = color
    }
}
```

**Fix:** Always unconditionally assign. Never guard `NSColorWell.color` with `!=`.

## Target/Action Re-assignment in updateNSView

`NSColorWell` may reset its `target` and `action` when added to or reconfigured in the view hierarchy. If `updateNSView` doesn't re-set these, the coordinator reference can be lost after a SwiftUI view update cycle.

**Fix:**
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    well.color = color
    well.target = context.coordinator    // re-set every update
    well.action = #selector(Coordinator.colorChanged(_:))
}
```

## Alpha Handling

When the bound color may have an alpha component, set `well.alphaValue = 1.0` in `makeNSView`. This ensures the color well renders and accepts alpha values. (`NSColorWell` has no `allowsAlpha` property on macOS — that exists on iOS only.)
