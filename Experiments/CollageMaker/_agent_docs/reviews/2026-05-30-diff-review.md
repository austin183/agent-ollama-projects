# Diff Review — 2026-05-30 (Arch Review Phase 2)

**Changeset**: Uncommitted work on `main` branch (9 commits ahead of origin/main)
**Scope**: 13 modified files + 3 new files — NSColor hex encoding, CollageAssembler refactoring, LayoutGenerator strategy pattern, TitleMetrics caching, ScrollPanManager consolidation
**Session**: [Session 065](../project-timeline/sessions/session-065.md)

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
| `.opencode/skills/building-macos-apps/SKILL.md` | Added Swift compilation gotchas section |
| `_agent_docs/common-prompts.md` | Updated learnings reference |
| `_agent_docs/project-timeline/prototype-2-project-timeline.md` | Added session-065 entry |

---

## Issue 1: Dead files not cleaned up — `ScrollPanManager.swift` and `ScrollPanManagerTests.swift`

**Severity: Medium**

The scroll pan refactoring moved scroll pan state into `CropManager` and removed the `scrollPanManager` property from `CollageViewModel`. However, two files remain on disk as dead code:

- `CollageMaker/Services/ScrollPanManager.swift` — the old standalone manager (39 lines)
- `CollageMakerTests/ScrollPanManagerTests.swift` — its 129-line test suite

These files are **not included in the Xcode project** (`project.pbxproj` has no references to either file), so they won't cause compilation errors. But they are misleading — they suggest `ScrollPanManager` still exists and its tests pass, when in fact the class has been fully replaced by `CropManager`'s new scroll pan methods.

**Suggested fix**: Delete both files as part of this refactoring cleanup.

---

## Validated Clean Changes

The following refactors were validated with no issues found:

| Refactor | Validation |
|----------|-----------|
| **CollageAssembler rendering dedup** | `renderIntoContext()` correctly consolidates duplicated bitmap context creation + panel/title drawing from `assemble()` and `assemblePreview()`. Logging moved into shared function. `renderQueue.sync` guard preserved in each caller. |
| **CollageAssembly protocol split (ISP)** | Clean split into `CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`. `CollageAssembler` implements all methods. Default `assemble()` method via protocol extension. |
| **TitleMetrics caching** | `cachedTitleMetrics` correctly invalidated in both `titleAttrString.didSet` and `titleStyle.didSet`. Computed property is `@MainActor`-safe. `CollageEditorView` uses `viewModel.titleMetrics` instead of computing inline. |
| **NSColor → RGBA hex encoding** | Hex format string `#%02lX%02lX%02lX%02lX` with `Int` values is correct on macOS (64-bit). Decoder bit shifts `(hexValue >> 24) & 0xFF` correctly extract R, G, B, A from `#RRGGBBAA`. All callers have `import AppKit`. |
| **Scroll pan collapsed into CropManager** | New methods (`beginScrollPan`, `scrollPanAccumulateDelta`, `scrollPanApply`, `endScrollPan`) correctly replicate old `ScrollPanManager` behavior. `activePanelId` priority (`scrollPanPanelId ?? gestureActivePanelId`) is correct. `notifyCropMapChanged()` properly called after mutations. |
| **LayoutGenerator strategy pattern** | `UniformLayoutStrategy`, `HeroLayoutStrategy`, `MosaicLayoutStrategy` conform to `LayoutStrategy`. `LayoutStyle.makeStrategy()` factory replaces switch. `imageOrder` optional preserved through protocol. |

---

## Agent Self-Correction

The diff-review agent initially suspected a breaking change where `imageOrder` was made non-optional in the new `LayoutStrategy` protocol. Upon re-reading the source, the protocol correctly preserves `imageOrder: [Int]?` — no breaking change exists.

---

## Summary

| # | Severity | Issue |
|---|----------|-------|
| 1 | **Medium** | Dead `ScrollPanManager.swift` and `ScrollPanManagerTests.swift` files remain on disk after scroll pan consolidation |

**No compilation errors, logic bugs, or CLAUDE.md violations detected.** The refactoring is structurally sound.
