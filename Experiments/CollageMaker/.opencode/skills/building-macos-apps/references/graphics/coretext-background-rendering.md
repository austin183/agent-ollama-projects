# CoreText Background Thread Rendering

## Contents
- Problem: Swift overlay gap
- CoreFoundation C API solution
- Attribute keys and types
- macOS 26 SDK API changes
- NSMutableAttributedString bridge (AppKit-dependent alternative)
- Summary rules
- Pitfalls
- Verification strategy

## Problem: Swift Overlay Gap

The Swift overlay for `CFMutableAttributedString` does **not** expose `addAttribute(_:value:range:)` or `getLength()`. Attempting to call these on a bridged `NSMutableAttributedString` produces compile errors. Similarly, `CFAttributedString.Key` is not accessible — the Swift overlay only exposes Foundation/AppKit keys (`.font`, `.foregroundColor`), not CoreText keys (`kCTFontAttributeName`, etc.).

```swift
let cf = nsMutable as CFMutableAttributedString
cf.addAttribute(.font, value: someFont, range: CFRange()) // ERROR: no member 'addAttribute'
let len = cf.getLength() // ERROR: no member 'getLength'
```

## CoreFoundation C API Solution

For pure CoreText rendering on a background thread (no AppKit dependency), use the C API directly:

```swift
import CoreText
import CoreGraphics
import Foundation

let cfAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
CFAttributedStringReplaceString(cfAttrString, CFRange(), "Hello" as CFString)
let stringLength = CFAttributedStringGetLength(cfAttrString)

CFAttributedStringSetAttribute(
    cfAttrString,
    CFRange(location: 0, length: stringLength),
    kCTFontAttributeName,
    someCTFont
)

CFAttributedStringSetAttribute(
    cfAttrString,
    CFRange(location: 0, length: stringLength),
    kCTParagraphStyleAttributeName,
    someCTParagraphStyle
)

CFAttributedStringSetAttribute(
    cfAttrString,
    CFRange(location: 0, length: stringLength),
    kCTForegroundColorAttributeName,
    someCGColor
)

let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)
```

## Attribute Keys and Types

| Concept | CoreText C API | AppKit Bridge |
|---|---|---|
| Font key | `kCTFontAttributeName` | `.font` |
| Color key | `kCTForegroundColorAttributeName` | `.foregroundColor` |
| Paragraph key | `kCTParagraphStyleAttributeName` | `.paragraphStyle` |
| Font type | `CTFont` (`CTFontCreateWithName`) | `NSFont` |
| Color type | `CGColor` | `NSColor` (convert to `.cgColor`) |
| Range type | `CFRange(location:length:)` | `NSRange` |

**Key points:**
- `CFAttributedStringCreateMutable` returns optional — unwrap with `guard` or `!`
- Attribute keys are **C constants**, not Swift enum cases
- `CTFont` objects created with `CTFontCreateWithName`, `CTFontCreateCopyWithAttributes`, etc.
- `CGColor` works directly as foreground color value
- Entire pipeline is **thread-safe** — no AppKit mutation, safe for background threads

## macOS 26 SDK API Changes

The macOS 26 SDK (Xcode 26.5+) changes several CoreText Swift overlay signatures. The underlying C headers remain the same — only the Swift presentation differs.

### CTFrameDraw parameter order

```swift
// macOS 26 (canonical C order):
CTFrameDraw(frame, context)
```

<details>
<summary>Legacy macOS 10–25 (old Swift overlay)</summary>

```swift
CTFrameDraw(context, frame)
```

</details>

### CTFramesetterSuggestFrameSizeWithConstraints last parameter

```swift
// macOS 26:
var fitRange = CFRange()
CTFramesetterSuggestFrameSizeWithConstraints(setter, range, maxSize, constraints, &fitRange)
```

<details>
<summary>Legacy macOS 10–25 (old Swift overlay)</summary>

```swift
var lineCount: CFIndex = 0
CTFramesetterSuggestFrameSizeWithConstraints(setter, range, maxSize, constraints, &lineCount)
```

</details>

### CTTextAlignment (was CTAlignment)

```swift
// macOS 26:
let alignment: CTTextAlignment = .left
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
let alignment: CTAlignment = .left
```

</details>

### CTParagraphStyleSpecifier enum syntax

```swift
// macOS 26:
CTParagraphStyleSetting(spec: CTParagraphStyleSpecifier.alignment, valueSize: ..., value: ...)
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
CTParagraphStyleSetting(spec: kCTParagraphStyleSpecifierAlignment, valueSize: ..., value: ...)
```

</details>

### CTFontGetSymbolicTraits (was CTFontCopySymbolicTraits)

```swift
// macOS 26:
let traits = CTFontGetSymbolicTraits(font)
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
let traits = CTFontCopySymbolicTraits(font)
```

</details>

### CTFontCreateCopyWithSymbolicTraits (was kCTFontSymbolicTraitAttribute dict)

```swift
// macOS 26:
let font = CTFontCreateCopyWithSymbolicTraits(baseFont, 0, nil, mergedTraits, existingTraits)
```

<details>
<summary>Legacy macOS 10–25</summary>

`kCTFontSymbolicTraitAttribute` was available as a dictionary attribute key for `CTFontCreateCopyWithAttributes`. This constant is no longer exposed in the Swift overlay. Use `CTFontCreateCopyWithSymbolicTraits` directly.

</details>

### CTFontUIFontType.system (was .systemUI)

```swift
// macOS 26:
CTFontCreateUIFontForLanguage(.system, size, nil)
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
CTFontCreateUIFontForLanguage(.systemUI, size, nil)
```

</details>

### Symbolic trait enum case names

```swift
// macOS 26:
traits.union(.traitBold)
traits.union(.traitItalic)
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
traits.union(.bold)
traits.union(.italic)
```

</details>

### CTParagraphStyleSetting value pointer lifetime (Swift 6)

```swift
// macOS 26 + Swift 6 strict pointers:
var value = ctAlignment
CTParagraphStyleSetting(
    spec: ...,
    valueSize: ...,
    value: withUnsafePointer(to: &value) { UnsafeRawPointer($0) }
)
```

<details>
<summary>Legacy macOS 10–25</summary>

```swift
var value = ctAlignment
CTParagraphStyleSetting(spec: ..., valueSize: ..., value: &value)
```

</details>

## NSMutableAttributedString Bridge (AppKit-Dependent Alternative)

For main-thread rendering where AppKit is available, build with `NSMutableAttributedString` and bridge to `CFAttributedString` (read-only) for the framesetter:

```swift
let nsAttr = NSMutableAttributedString(string: "Hello")
nsAttr.addAttribute(.font, value: someCTFont, range: NSRange(location: 0, length: 5))
nsAttr.addAttribute(.foregroundColor, value: someCGColor, range: NSRange(location: 0, length: 5))
let framesetter = CTFramesetterCreateWithAttributedString(nsAttr as CFAttributedString)
```

This works but **requires AppKit** (the `.font` key is a Foundation/AppKit key). For background-thread rendering without AppKit, use the C API approach above.

## Summary Rules

1. **Background thread text rendering** — Use CoreFoundation C API (`CFAttributedStringCreateMutable`, `CFAttributedStringSetAttribute`) for thread-safe attributed string construction without AppKit
2. **Attribute keys are C constants** — Use `kCTFontAttributeName`, not `NSAttributedString.Key.font`
3. **CTFont, not NSFont** — Create fonts with `CTFontCreateWithName` for pure CoreText pipelines
4. **CGColor, not NSColor** — Use `CGColor` directly; avoid `NSColor.cgColor` on background threads (AppKit type)
5. **CFRange, not NSRange** — Construct manually: `CFRange(location: ..., length: ...)`

## Pitfalls

- **Swift overlay missing methods** — `CFMutableAttributedString` in Swift doesn't have `addAttribute` or `getLength`. Use `CFAttributedStringSetAttribute` and `CFAttributedStringGetLength` C functions instead.
- **CFAttributedString.Key inaccessible** — The Swift enum for CoreText attribute keys is not exposed. Use C constants (`kCTFontAttributeName`, etc.).
- **NSColor.cgColor on background thread** — `NSColor` is an AppKit type and is not thread-safe. Extract `.cgColor` on the main thread before passing to a background task, or construct `CGColor` directly (e.g., `CGColor(red:green:blue:alpha:)`).
- **NSMutableAttributedString is not thread-safe** — Building attributed strings on a background thread with `NSMutableAttributedString.addAttribute` may crash or produce undefined behavior. Use the CoreFoundation C API for background thread construction.

## Verification Strategy

When encountering CoreText API errors in Xcode, verify the actual C header signatures — the C headers are the source of truth:

```bash
grep -A5 "FUNCTION_NAME" /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreText.framework/Headers/CTFont.h
```

Swift overlay differences between SDK versions are common for C frameworks. When in doubt, check the C header.
