# macOS 26 SDK CoreText API Changes — Learnings

**Date:** 2026-06-02
**Context:** Migrating title rendering to CoreText for background-thread safety. The macOS 26 SDK (Xcode 26.5) has renamed or restructured several CoreText APIs compared to earlier macOS versions.

## API Changes

### 1. `CTFrameDraw` parameter order swapped

```swift
// Before (macOS 10–25):
CTFrameDraw(context, frame)

// macOS 26:
CTFrameDraw(frame, context)
```

The C header (`CTFrame.h`) declares `void CTFrameDraw(CTFrameRef frame, CGContextRef context)`, but the Swift overlay in earlier SDKs presented the parameters in a different order. macOS 26 presents them in the canonical C order.

### 2. `CTFramesetterSuggestFrameSizeWithConstraints` last parameter

```swift
// Before (macOS 10–25):
var lineCount: CFIndex = 0
CTFramesetterSuggestFrameSizeWithConstraints(..., &lineCount)

// macOS 26:
var fitRange = CFRange()
CTFramesetterSuggestFrameSizeWithConstraints(..., &fitRange)
```

The last parameter changed from `UnsafeMutablePointer<CFIndex>` (line count) to `UnsafeMutablePointer<CFRange>` (fit range). The C header has always declared `CFRange * _Nullable fitRange`, but the Swift overlay in earlier SDKs exposed it differently.

### 3. `CTAlignment` renamed to `CTTextAlignment`

```swift
// Before:
let alignment: CTAlignment = .left

// macOS 26:
let alignment: CTTextAlignment = .left
```

The type was renamed. The constants (`kCTTextAlignmentLeft`, etc.) remain the same in the C header.

### 4. `kCTParagraphStyleSpecifierAlignment` enum syntax

```swift
// Before:
spec: kCTParagraphStyleSpecifierAlignment

// macOS 26:
spec: CTParagraphStyleSpecifier.alignment
```

The C constant is still `kCTParagraphStyleSpecifierAlignment`, but the Swift overlay exposes it as an enum member.

### 5. `CTFontCopySymbolicTraits` renamed to `CTFontGetSymbolicTraits`

```swift
// Before:
let traits = CTFontCopySymbolicTraits(font)

// macOS 26:
let traits = CTFontGetSymbolicTraits(font)
```

The C header declares `CTFontGetSymbolicTraits`. The old name may have been a Swift overlay alias.

### 6. `kCTFontSymbolicTraitAttribute` no longer available

```swift
// Before:
let attrs = [kCTFontSymbolicTraitAttribute: mergedTraits.rawValue] as CFDictionary
let font = CTFontCreateCopyWithAttributes(baseFont, 0, nil, attrs)

// macOS 26:
let font = CTFontCreateCopyWithSymbolicTraits(baseFont, 0, nil, mergedTraits, existingTraits)
```

The `kCTFontSymbolicTraitAttribute` constant is not exposed in the Swift overlay. Use `CTFontCreateCopyWithSymbolicTraits` directly, which takes `symTraitValue` and `symTraitMask` parameters.

### 7. `CTFontUIFontType.systemUI` → `.system`

```swift
// Before:
CTFontCreateUIFontForLanguage(.systemUI, size, nil)

// macOS 26:
CTFontCreateUIFontForLanguage(.system, size, nil)
```

The C constant is `kCTFontUIFontSystem`. The Swift overlay maps it to `.system`, not `.systemUI`.

### 8. Symbolic trait enum case names

```swift
// Before:
traits.union(.bold)

// macOS 26:
traits.union(.traitBold)
```

The Swift overlay uses full trait names (`.traitBold`, `.traitItalic`) instead of shortened names (`.bold`, `.italic`).

### 9. `CTParagraphStyleSetting` value pointer lifetime

```swift
// Before (works in older Swift):
var value = ctAlignment
CTParagraphStyleSetting(spec: ..., value: &value)

// macOS 26 (required):
var value = ctAlignment
CTParagraphStyleSetting(spec: ..., value: withUnsafePointer(to: &value) { UnsafeRawPointer($0) })
```

Swift 6 strict pointer lifetime requires explicit pointer conversion for `UnsafeRawPointer` parameters.

## Verification Strategy

When encountering CoreText API errors in Xcode, verify the actual C header signatures:

```bash
grep -A5 "FUNCTION_NAME" /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreText.framework/Headers/CTFont.h
```

The C headers are the source of truth. Swift overlay differences between SDK versions are common for C frameworks.
