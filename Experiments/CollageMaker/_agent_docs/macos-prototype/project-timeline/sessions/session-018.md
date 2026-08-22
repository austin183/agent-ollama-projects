# Session 18 — 2026-05-15

### Round 4, Phase 2: Hero Image Fix, then Remove Hero Index Feature

**Goal:** Fix `generateHero()` to respect `heroIndex`, then remove the hero index star feature entirely per user request — letting users drag-and-drop images in the sidebar to control which image lands in the hero slot.

**Changes Made:**

1. **Hero index fix (intermediate)** — `LayoutGenerator.swift:61-130`. The original `generateHero()` used `imageOrder[0]` as the hero image, ignoring `heroIndex`. Fixed by building an `adjustedOrder` that moves `heroIndex` to position 0 before the layout logic runs. Added 4 new tests covering: no custom order, custom order with hero reposition, hero already first, all indices unique.

2. **Remove hero index feature** — Per user request, removed the hero star selector entirely since sidebar drag-and-drop + `customImageOrder` already gives users full control over which image is the hero (first image = hero slot).

**Files Modified:**
- `Services/LayoutGenerator.swift` — Removed `heroIndex: Int?` parameter from `generate()` and `generateHero()`. Simplified `generateHero()` to use `imageOrder[0]` as the hero image (first image in sidebar order).
- `ViewModel/CollageViewModel.swift` — Removed `heroIndex` property, `UserDefaultsKeys.heroIndex`, and `setHeroIndex()` method. Removed `heroIndex` from `LayoutGenerator.generate()` call.
- `ContentView.swift` — Removed yellow star indicator on sidebar items, removed tap-to-select hero gesture, removed horizontal hero image strip below Layout Style picker.
- `CollageMakerTests/LayoutGeneratorTests.swift` — Removed all `heroIndex` parameters, removed heroIndex-specific tests, added tests for hero layout with custom `imageOrder`.
- `CollageMakerTests/CollageViewModelTests.swift` — Removed `setHeroIndexUpdatesValue` test, updated `LayoutGenerator.generate()` calls.
- `CollageMakerTests/CollageAssemblerTests.swift` — Removed `heroIndex: nil` from all `LayoutGenerator.generate()` calls.
- `CollageMakerTests/CropManagerTests.swift` — Removed `heroIndex: nil` from all `LayoutGenerator.generate()` calls.

**Build Issues Encountered and Resolved:**
1. Stray closing brace in `ContentView.swift` from multi-line edit — fixed by restoring proper brace nesting
2. `.onMove` modifier placed inside `ForEach` content closure instead of on the `ForEach` itself — caused "private can only be used in non-local scope" errors. Fixed by moving `.onMove` to the `ForEach` level.
3. Swift type-checker timeout on `ContentView.swift` — oversized expression from misplaced braces confused the compiler. Fixed brace structure resolved the issue.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **67 tests pass** (all passing, hero index tests removed)
- Hero layout: **Working** (first image in sidebar order = hero slot)
- Hero star selector: **Removed** (sidebar and image strip)
- Hero index ViewModel property: **Removed** (UserDefaults key cleaned up)

**Learnings Documented:**
- `_agent_docs/learnings/hero-index-removal-learnings.md`
