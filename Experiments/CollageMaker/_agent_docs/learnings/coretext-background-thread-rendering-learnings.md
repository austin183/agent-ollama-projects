# CoreFoundation C API for Attributed String Mutation — Learnings

**Date:** 2026-06-02
**Context:** Migrating title rendering from AppKit (`NSAttributedString.draw(in:)`) to CoreText (`CTFrameDraw`) on a background thread.

## Problem

The Swift overlay for `CFMutableAttributedString` does **not** provide `addAttribute(_:value:range:)` or `getLength()` methods. Attempting to call these on a bridged `NSMutableAttributedString -> CFMutableAttributedString` produces compile errors:

```swift
let cf = nsMutable as CFMutableAttributedString
cf.addAttribute(.font, value: someFont, range: CFRange()) // ERROR: no member 'addAttribute'
let len = cf.getLength() // ERROR: no member 'getLength'
```

Similarly, `CFAttributedString.Key` (the Swift enum for attribute keys) is not accessible — the Swift overlay only exposes the Foundation/AppKit keys (`.font`, `.foregroundColor`, etc.), not the CoreText-specific keys (`kCTFontAttributeName`, `kCTParagraphStyleAttributeName`, etc.).

## Solution

Use the CoreFoundation C API directly:

```swift
import CoreText
import CoreGraphics
import Foundation

// Create mutable attributed string
let cfAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)
CFAttributedStringReplaceString(cfAttrString, CFRange(), "Hello" as CFString)
let stringLength = CFAttributedStringGetLength(cfAttrString)

// Set CoreText attributes using C constant keys
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

// Pass to framesetter
let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)
```

## Key Points

- **`CFAttributedStringCreateMutable`** returns an optional (`CFMutableAttributedString?`) — unwrap with `!` or `guard` after creation
- **Attribute keys** are C constants (`kCTFontAttributeName`), not Swift enum cases
- **`CFRange`** is used for ranges, not `NSRange` — construct manually: `CFRange(location: ..., length: ...)`
- **`CGColor`** works directly as the foreground color value via `kCTForegroundColorAttributeName`
- **`CTFont`** objects are created with `CTFontCreateWithName`, `CTFontCreateCopyWithAttributes`, etc. — no AppKit dependency
- This entire pipeline is **thread-safe** — no AppKit mutation, suitable for background threads

## Alternative: NSMutableAttributedString Bridge

You can also build the attributed string using `NSMutableAttributedString` (with AppKit keys like `.font`, `.foregroundColor`), then bridge to `CFAttributedString` (read-only) for the framesetter:

```swift
let nsAttr = NSMutableAttributedString(string: "Hello")
nsAttr.addAttribute(.font, value: someCTFont, range: NSRange(location: 0, length: 5))
nsAttr.addAttribute(.foregroundColor, value: someCGColor, range: NSRange(location: 0, length: 5))
let framesetter = CTFramesetterCreateWithAttributedString(nsAttr as CFAttributedString)
```

This works but **requires AppKit** (the `.font` key is a Foundation/AppKit key). For a pure CoreText solution that runs on a background thread without AppKit, use the C API approach above.

## Verification Tip

Use `swiftc -parse` to verify CoreText API signatures before committing to code:

```bash
swiftc -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -parse /tmp/TestAPI.swift
```

This validates syntax and type checking without a full project build.
