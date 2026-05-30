# Diff Review — 2026-05-30

**Changeset**: Uncommitted work on `main` branch
**Scope**: 13 modified files — NSColor serialization, CollageAssembler refactoring, LayoutGenerator strategy pattern, TitleMetrics caching, ScrollPanManager consolidation

## Files Changed

| File | Change |
|------|--------|
| `Models/TitleStyle.swift` | NSKeyedArchiver → RGBA hex encoding for serialization |
| `Services/LoggingExtensions.swift` | New `NSColor` extension with `rgbaHex` property/initializer |
| `Services/CollageAssembler.swift` | Protocol split (ISP), `renderIntoContext()` dedup |
| `Services/LayoutGenerator.swift` | Strategy pattern for layout generation |
| `ViewModel/CollageViewModel.swift` | Removed `ScrollPanManager`, added `cachedTitleMetrics` |
| `ViewModel/CropManager.swift` | Inlined scroll pan state from `ScrollPanManager` |
| `Views/CollageEditorView.swift` | Use cached `viewModel.titleMetrics` |
| `Views/SettingsView.swift` | NSKeyedArchiver → RGBA hex for UserDefaults colors |
| `Models/LayoutStyle.swift` | Trailing blank line |
| `SKILL.md` | Added Swift compilation gotchas section |
| `common-prompts.md` | Updated learnings reference |
| `project-timeline.md` | Added session entry |

---

## Issue 1: Behavioral — `NSColor.rgbaHex` silently converts unsupported color spaces to transparent black (Low)

**Location**: `Services/LoggingExtensions.swift:20-21`

```swift
var rgbaHex: String {
    guard let rgb = usingColorSpace(.sRGB) else { return "#00000000" }
```

If an `NSColor` exists in a color space that cannot be converted to sRGB (e.g., certain device-gray or device-CMYK colors), `usingColorSpace(.sRGB)` returns `nil` and the property silently falls back to `"#00000000"` — a fully transparent black. The original color is lost without any indication.

In practice, this is unlikely to be hit because the app uses `NSColor.white`, `NSColor.black`, `NSColor.darkGray`, and colors from `NSColorWell` — all of which are sRGB-compatible.

**Suggested fix**: Add a warning log for robustness:
```swift
guard let rgb = usingColorSpace(.sRGB) else {
    Logger(subsystem: "austin183.indie.CollageMaker", category: "Color").warning("Cannot convert color to sRGB, using transparent black fallback")
    return "#00000000"
}
```

---

## Issue 2: Breaking — NSKeyedArchiver → hex encoding drops existing persisted data (Medium)

**Location**: `Models/TitleStyle.swift:36-75`, `Views/SettingsView.swift:13-14, 43-44`

The `TitleStyle` `CodingKeys` enum was renamed from `fontColorData`/`backgroundColorData` to `fontColorHex`/`backgroundColorHex`. The decode side uses `try? container.decode(String.self, forKey: .fontColorHex)` which will return `nil` for old persisted data (which was `Data`), falling back to `TitleStyle.default.fontColor`/`backgroundColor`. Similarly, `SettingsView` reads `UserDefaults` as `String` instead of `Data`.

This is a **silent migration** — users with existing saved `TitleStyle` data will see their custom font/background colors reset to defaults on first launch after this change. The decode logic handles this gracefully (no crash), but the user experience impact should be considered.

This appears to be intentional, but worth documenting in the project timeline or migration notes.

---

## Issue 3: Minor — Redundant `renderQueue.sync` on `@MainActor` class (Low)

**Location**: `Services/CollageAssembler.swift:81, 104, 334, 382, 440`

`CollageAssembler` is a `final class` running on the `@MainActor` (confirmed by usage from `CollageViewModel` which is `@MainActor @Observable`). All calls to `renderQueue.sync` execute synchronously on the main thread, which is already serialized. The `renderQueue` becomes a no-op queue that adds overhead without providing any concurrency benefit.

The original intent was likely to serialize `NSGraphicsContext` access (per skill reference: *"NSGraphicsContext.current is NOT thread-safe"*). But since `CollageAssembler` runs on the main thread, the queue is unnecessary.

If the intent is future-proofing (e.g., moving rendering to background), the queue is fine. But if it stays on `@MainActor`, it's dead weight.

---

## Issue 4: Minor — `NSColor` extension in misleading file (Low)

**Location**: `Services/LoggingExtensions.swift:19`

The `NSColor` extension (`rgbaHex` computed property + `init(rgbaHex:)` convenience initializer) is placed in `LoggingExtensions.swift`, a file that contains `DebugHelpers` struct for debug string formatting. While this is a minor organizational concern, the file name strongly implies logging-only content.

**Suggested fix**: Rename the file to `Extensions.swift` or move the `NSColor` extension to a more appropriate location.

---

## Issue 5: Minor — Protocol composition creates 4 methods on `CollageAssembly` (Low)

**Location**: `Services/CollageAssembler.swift:11-52`

```swift
protocol CollageAssembly: CollageRenderer, PanelRenderer, BackgroundRenderer, TitleRenderer {}
```

Each of the four composed protocols defines exactly one method. This is a valid application of the Interface Segregation Principle, but results in `CollageAssembly` exposing 4 methods that callers may not need. Consider whether these protocols are needed at all, or if a single `CollageAssembler` protocol with all methods would be simpler.

The value of this split becomes apparent only if different conformers implement different subsets of the protocols. Since `CollageAssembler` implements all four, the split may be premature.

---

## Validated Non-Issues

| Concern | Verdict |
|---------|---------|
| `notifyCropMapChanged()` undefined | ✅ Verified defined at `CollageViewModel.swift:49` |
| `cachedTitleMetrics` race condition | ✅ `CollageViewModel` is `@MainActor`, single-threaded access |
| `TitleMetrics(preparedString:style:)` initializer signature | ✅ Verified in `TitleMetrics.swift` |
| `NSColor(rgbaHex:)` convenience init calls designated init | ✅ `init(srgbRed:green:blue:alpha:)` is a valid designated init |
| `NSColorWell` binding in `SettingsView` | ✅ Uses `@Binding`, initializes in `makeNSView`, unconditionally updates in `updateNSView` |
| `TitleStyle` Codable in extension without re-declaring `: Codable` | ✅ Correct per project conventions |
| `activePanelId` priority (`scrollPanPanelId ?? gestureActivePanelId`) | ✅ Correct — scroll pan takes priority over gesture pan |
| `scrollPanApply(finish: false)` doesn't call `endGesture()` | ✅ Correct — `applyPan` only calls `endGesture()` when `finish: true` |
| `beginPan` after `scrollPanApply(finish: true)` in commit timer | ✅ Correct — re-baselines gesture state for continued interaction |
| Hex format consistency (`%02lX` uppercase ↔ `UInt32(hexStr, radix: 16)` case-insensitive) | ✅ `UInt32(_:radix:)` handles both cases |
| `LayoutGenerator` creates new strategy structs per call | ✅ Lightweight structs, no state — acceptable |

---

## Positive Findings

### Strategy pattern in `LayoutGenerator`
Cleanly replaces the switch statement and makes adding new layout types trivial. The `LayoutStyle.makeStrategy()` factory keeps the call site simple.

### `TitleMetrics` caching
Eliminates redundant `boundingRect` computations that previously ran on every view body evaluation. Stored cache + invalidation in ViewModel is properly integrated.

### Scroll pan consolidation
Removing `ScrollPanManager` and inlining its state into `CropManager` is a net simplification — reduces indirection without making CropManager unwieldy.

### Hex encoding over `NSKeyedArchiver`
More human-readable, smaller, and avoids archiver class-wholesale issues across app versions.

### Protocol split in `CollageAssembler`
Good application of the Interface Segregation Principle. Extracted `renderIntoContext()` correctly eliminates duplication between `assemble()` and `renderPreview()`.

---

## Summary

| # | Severity | Issue |
|---|----------|-------|
| 1 | **Medium** | NSKeyedArchiver → hex encoding silently drops existing persisted user color preferences |
| 2 | Low | `NSColor.rgbaHex` silently returns `"#00000000"` for unsupported color spaces without logging |
| 3 | Low | `renderQueue.sync` calls are redundant on `@MainActor` class |
| 4 | Low | `LoggingExtensions.swift` name no longer matches contents |
| 5 | Low | Protocol composition creates 4 methods but all implemented by a single conformer |

Only **Issue 1** is user-facing. Issues 2-5 are code quality observations with no functional impact.
