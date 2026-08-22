# CollageMaker — Architectural Code Review

**Date:** 2026-05-26
**Reviewer:** Agent
**Scope:** Full codebase review (Models, ViewModel, Services, Views, Tests)

---

## Executive Summary

CollageMaker is a well-architected macOS SwiftUI app with a clean layering of models, view model, services, and views. The `@Observable` + `@MainActor` pattern is correctly applied, the service layer is protocol-based for testability, and the undo system is comprehensive. The 37 learnings files document hard-won SwiftUI knowledge that will benefit future development.

**Verdict:** Approve with requested changes (5 medium-priority issues, 4 minor issues).

---

## Architecture & Design

### Strengths

- **Clean 4-layer architecture**: Models → Services → ViewModel → Views with no backward dependencies
- **Protocol-based service layer**: `SaliencyAnalysis` and `CollageAssembly` protocols enable clean mocking in tests
- **Actor isolation for Vision work**: `SaliencyAnalyzer` as an `actor` provides thread-safe async computation
- **`AssemblyConfig` composition**: Flattened ViewModel state is restructured into focused sub-configs (`LayoutConfig`, `TitleConfig`, `BackgroundConfig`) before reaching the assembler — good separation
- **Stateless pure functions**: `LayoutGenerator`, `FitMath`, `TitleMetrics`, `FontMerger`, `CoordinateConverter` are all pure, easily testable
- **`@Observable` + `didSet` pattern**: Consistent use of `isInitializing` guard to prevent spurious undo/persistence during init
- **Debounced persistence**: 300ms debounce for UserDefaults saves prevents excessive writes during live gestures
- **Comprehensive undo**: 60 levels, grouped undo for gestures, undo for 11 properties and 5 mutation patterns

### Issues

#### Medium: Duplicate UserDefaults Key Definitions

**Files:** `CollageViewModel.swift:13-26`, `UserDefaultsPersistence.swift:29-50`

`ViewModelUserDefaultsKeys` enum duplicates 12 keys from `UserDefaultsPersistence.Keys`. The comment acknowledges this as technical debt ("Item 2 will remove"), but it remains a maintenance hazard — two sources of truth for the same string constants.

**Recommendation:** Complete the removal. Have `ExportPanel` reference `UserDefaultsPersistence.Keys` directly, then delete `ViewModelUserDefaultsKeys`.

#### Medium: `TitleStyle` Directly Accesses UserDefaults

**File:** `TitleStyle.swift:35-48`

The model has `fromUserDefaults()` and `saveToUserDefaults()` methods that read/write `UserDefaults.standard` directly. This violates persistence encapsulation — `UserDefaultsPersistence` should be the sole owner. It also creates a hidden dependency on the default UserDefaults suite, making testing harder.

**Recommendation:** Move these methods into `UserDefaultsPersistence` as `saveTitleStyle(_:)` and `loadTitleStyle()`. The model should remain a pure data type.

#### Medium: `SettingsView` Bypasses ViewModel Persistence

**File:** `SettingsView.swift`

Settings uses `@AppStorage` and `UserDefaultsColorView` (which writes directly to `UserDefaults.standard`) for default preferences. These keys (`defaultTitle`, `defaultFontFamily`, etc.) are separate from the session-level state managed by `UserDefaultsPersistence`. The precedence relationship between "session state" and "default preferences" is unclear — does the Settings value apply to new sessions, or does it override the current session?

**Recommendation:** Document the intended relationship. If Settings defines defaults for new sessions, consider having the ViewModel apply them during initialization when no session data exists.

#### Medium: `backgroundImage` Property Lacks Undo Registration

**File:** `CollageViewModel.swift:175-184`

The `backgroundImage` `didSet` calls `debouncedSave()` and `updatePreview()` but does not register an undo action. Setting or clearing a background image cannot be undone via Cmd+Z, unlike every other property.

**Recommendation:** Add undo registration consistent with other properties:
```swift
undoManager.registerUndo(withTarget: self) { target in
    target.backgroundImage = oldValue
    target.backgroundImagePath = nil // or preserve old path
}
undoManager.setActionName("Change Background Image")
```

#### Medium: `panelAssignments` Not Persisted

**File:** `CollageViewModel.swift:198`

`panelAssignments: [UUID: Int]` is a mutable dictionary that maps panels to images but is never saved to UserDefaults. Custom image-to-panel assignments are lost after relaunch.

**Recommendation:** Add to `UserDefaultsPersistence` save/load cycle. Since panel UUIDs change on layout regeneration, consider persisting the `customImageOrder` array (which is already persisted) as the canonical source and deriving `panelAssignments` from it on load.

---

## Code Quality

### Minor: `exportQuality` Default Value Mismatch

**File:** `CollageViewModel.swift:116`

Default is `0` (0% JPEG quality), while `SettingsView` defaults to `0.92`. A first-time user who hasn't opened Settings will produce near-zero quality exports.

**Recommendation:** Change the default to `0.92` to match Settings, or load from UserDefaults in the initializer.

### Minor: No Undo for `addImages`

**File:** `CollageViewModel.swift:300`

Adding images is the only major mutation without undo support. The learnings files document this as a deliberate gap, but it means users cannot undo image additions.

**Recommendation:** Consider adding undo for `addImages` — capture the pre-addition `images` array and restore it on undo. This is lower priority since `clearAll()` provides a recovery path.

### Minor: No-op Reassignment in `applyOverlayCrop`

**File:** `CollageViewModel.swift:668-671`

```swift
var tmp = cropMap
cropMap = tmp
```

This appears to be a workaround to trigger `@Observable` tracking after mutating the dictionary in place. It should be documented or replaced with a cleaner mutation pattern.

**Recommendation:** Add a comment explaining why this is needed, or use a more explicit pattern like `cropMap = cropMap` (which may work with `@Observable` for dictionary reassignment).

### Minor: `SaliencyResult.cropOrigin` Portrait Swap

**File:** `SaliencyResult.swift:22-25`

When `imageSize.width < imageSize.height`, the method swaps x and y coordinates. This undocumented heuristic may produce incorrect crop origins for certain image orientations.

**Recommendation:** Add a comment explaining the rationale, or verify this handles all EXIF orientations correctly.

---

## Service Layer Design

### `CollageAssembler` Code Duplication

**File:** `CollageAssembler.swift:62-147`

`assembleWithCGImages` and `assemblePreviewWithCGImages` share ~80% identical code: bitmap context creation, panel drawing, and title drawing. The only difference is the final output (JPEG `Data` vs `NSImage`).

**Recommendation:** Extract the shared rendering logic into a private `render(into:config:cgImages:backgroundImage:)` method that draws into the provided context. The two public methods would then only differ in context creation and final encoding.

### `UserDefaultsPersistence` Delegates to `TitleStyle`

**File:** `UserDefaultsPersistence.swift:67`

```swift
viewModel.titleStyle.saveToUserDefaults()
```

The persistence layer calls the model's own persistence method, reinforcing the coupling issue noted above.

**Recommendation:** Inline the TitleStyle encoding into `UserDefaultsPersistence` using `JSONEncoder` + `defaults.set(_:forKey:)`.

---

## Testing

### Strengths

- **12 test files** covering ViewModels, Services, and key logic
- **Mock protocols** for `SaliencyAnalysis` and `CollageAssembly`
- **Fixture helpers** in `TestHelpers.swift` for CGImage/NSImage/ImageItem creation
- **`@Suite(.serialized)`** for ViewModel tests to avoid AppKit concurrency issues
- **Edge case coverage** for `moveImages`, `buildMoveMapping`, and saliency errors

### Gaps

- **No tests for `UserDefaultsPersistence`** — the save/load cycle for 13 properties is untested
- **No tests for `ScrollPanManager`** — the debounce timer logic is complex and untested
- **No tests for `FitMath`** — the fit calculation is foundational but untested
- **`SettingsView` is untested** — the `UserDefaultsColorView` NSViewRepresentable has a known gotcha (NSColor equality across color spaces) that would benefit from testing

---

## Concurrency

### `ScrollPanManager` Uses Raw `DispatchQueue.main`

**File:** `ScrollPanManager.swift:46`

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: scrollCommitTimer!)
```

Despite `CollageViewModel` being `@MainActor`, `ScrollPanManager` is a plain class that uses explicit main queue dispatch. If this were ever used off the main actor, it could cause threading issues.

**Recommendation:** Either mark `ScrollPanManager` as `@MainActor` or use `Task { @MainActor in ... }` for the delayed commit.

---

## Conventions & Consistency

### Strengths

- Consistent `OSLog` usage with single subsystem `austin183.indie.CollageMaker`
- All models are value types (structs/enums) with appropriate protocol conformances
- `Identifiable` + `Equatable` on all collection elements
- `Codable` on persistable types with custom encoding for AppKit types
- Accessibility labels throughout the UI

### Nit: `DebugHelpers` Naming

**File:** `LoggingExtensions.swift`

`DebugHelpers` is a struct with only static methods but is named as if it were an extension. `RectFormatter` or `GeometryFormatter` would be more descriptive.

---

## SOLID Principles Assessment

| Principle | Status | Notes |
|-----------|--------|-------|
| **Single Responsibility** | Good | Each class has one clear reason to change. `CollageViewModel` is large but appropriately so as the single source of truth. |
| **Open/Closed** | Good | `LayoutGenerator` extends via `LayoutStyle` enum cases. `CollageAssembly` protocol allows alternative implementations. |
| **Liskov Substitution** | Good | Mock implementations satisfy their protocols faithfully. |
| **Interface Segregation** | Good | Protocols are minimal: `SaliencyAnalysis` (2 methods), `CollageAssembly` (2 methods). |
| **Dependency Inversion** | Good | `CollageViewModel` depends on `SaliencyAnalysis` and `CollageAssembly` protocols, not concretions. `UserDefaultsPersistence` is injected. |

---

## Recommendations Summary

### Must Fix (before next release)
1. Fix `exportQuality` default value (0 → 0.92)
2. Add undo registration for `backgroundImage`

### Should Fix (next sprint)
3. Remove duplicate `ViewModelUserDefaultsKeys` enum
4. Move `TitleStyle` UserDefaults methods into `UserDefaultsPersistence`
5. Persist `panelAssignments` or document why it's intentionally ephemeral

### Nice to Have
6. Deduplicate `CollageAssembler` rendering methods
7. Add tests for `UserDefaultsPersistence`, `ScrollPanManager`, `FitMath`
8. Document or clean up the no-op reassignment in `applyOverlayCrop`
9. Clarify the `SaliencyResult.cropOrigin` portrait swap heuristic
