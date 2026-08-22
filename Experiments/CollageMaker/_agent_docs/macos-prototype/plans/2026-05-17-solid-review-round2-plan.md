# CollageMaker SOLID Review Round 2 — Implementation Plan

**Date:** 2026-05-17
**Source:** `_agent_docs/reviews/collagemaker-solid-review.md`
**Scope:** CollageMaker macOS SwiftUI application, 8 source files, 6 test files

---

## Overview

Address all 10 findings from the SOLID architecture review. The plan is organized into 4 phases by dependency order. Phase 0 captures the deferred canvas-size configurability as a change request. Phases 1-3 address the 10 review findings. Phase 4 (deferred) is tracked in `_agent_docs/change-requests/round-7.md`.

## Review Findings Matrix

| # | Issue | Principle | Severity | Phase |
|---|-------|-----------|----------|-------|
| 2 | UserDefaults tightly coupled into ViewModel | DIP | Medium | 1 |
| 3 | `TitleStyle` persists itself | SRP | Low-Med | 1 |
| 1 | `CollageViewModel` approaching God class | SRP | Medium | 2 |
| 4 | `addImages` blocks main actor | Performance | Medium | 2 |
| 5 | No cancellation of stale saliency tasks | Correctness | Low | 3a |
| 6 | Mosaic layout uses randomness | OCP/Testing | Low | 3b |
| 8 | Tests pollute production namespace | Testability | Low | 3c |
| 9 | `ImagePickerGrid` unused | Dead code | Info | 3d |
| 7 | `CollageAssembly` protocol too broad | ISP | Low | Deferred |
| 10 | Hardcoded canvas size | Extensibility | Info | Deferred → `round-7.md` |

---

## Phase 0 — Deferred Change Request

**Output:** `_agent_docs/change-requests/round-7.md`

Write a change request document for configurable canvas size. Defers implementation to a future round.

---

## Phase 1 — SettingsStorage Abstraction

**Addresses:** Issue #2 (UserDefaults DIP), Issue #3 (TitleStyle SRP)

### 1.1 Create `SettingsStorage` protocol

**New file:** `Services/SettingsStorage.swift`

```swift
import AppKit

protocol SettingsStorage {
    func save<T: Codable>(_ value: T, key: String)
    func load<T: Codable>(_ type: T.Type, key: String) -> T?
    func save(_ color: NSColor, key: String)
    func loadColor(key: String) -> NSColor?
}
```

### 1.2 Create `UserDefaultsSettingsStorage`

Same file, concrete implementation wrapping `UserDefaults.standard`:
- `save<T: Codable>` → JSON encode, write to UserDefaults
- `load<T: Codable>` → read from UserDefaults, JSON decode
- `save(_ color:)` → `NSKeyedArchiver`, write to UserDefaults
- `loadColor(key:)` → `NSKeyedUnarchiver`, read from UserDefaults

### 1.3 Create `InMemorySettingsStorage`

Same file, test double backed by `[String: Any]` dictionary. No persistence, clean state per test.

### 1.4 Refactor `CollageViewModel` to inject `SettingsStorage`

**Modified file:** `ViewModel/CollageViewModel.swift`

- Add `private let settingsStorage: SettingsStorage` property
- Add to designated init: `init(saliencyAnalyzer:, assembler:, settingsStorage:)`
- Update convenience init to pass `UserDefaultsSettingsStorage()`
- Replace all `UserDefaults.standard` reads in property initializers with `settingsStorage.load(...)`
- Replace all `UserDefaults.standard` writes in `didSet` observers with `settingsStorage.save(...)`
- Remove `saveColor`/`loadColor` private helpers — delegate to `settingsStorage`
- Remove `UserDefaultsKeys` private enum — keys live at call sites or move to a shared constants file

Properties to migrate (12 `UserDefaults` access points):
- `layoutStyle` — rawValue save/load
- `title` — string save/load
- `titleStyle` — Codable save/load (see 1.5)
- `gutter` — double save/load
- `backgroundColor` — NSColor save/load
- `exportQuality` — double save/load
- `backgroundStyle` — rawValue save/load
- `gradientStartColor` — NSColor save/load
- `gradientEndColor` — NSColor save/load
- `gradientAngle` — double save/load
- `backgroundOpacity` — double save/load
- `customImageOrder` — `[Int]` Codable save/load

### 1.5 Clean `TitleStyle`

**Modified file:** `Models/TitleStyle.swift`

- Remove `extension TitleStyle { static func fromUserDefaults() ... func saveToUserDefaults() ... }`
- Remove `private enum UserDefaultsKeys`
- ViewModel handles load/save via `SettingsStorage` in the `titleStyle` property initializer and `didSet`

### 1.6 Update `CollageMakerApp.swift`

**Modified file:** `CollageMakerApp.swift`

- No change needed — `CollageViewModel()` convenience init wire

### 1.7 Update tests

**Modified file:** `CollageViewModelTests.swift`

- Update all `CollageViewModel(saliencyAnalyzer:, assembler:)` calls to include `settingsStorage: InMemorySettingsStorage()`
- Verify tests pass with clean in-memory state

---

## Phase 2 — ImageLoader Service Extraction

**Addresses:** Issue #1 (God class SRP), Issue #4 (main actor block)

### 2.1 Create `ImageLoading` protocol

**New file:** `Services/ImageLoader.swift`

```swift
protocol ImageLoading {
    func loadImages(from urls: [URL]) async -> [ImageItem]
}
```

### 2.2 Create `ImageLoader` service

Same file. Move image loading logic from `CollageViewModel.addImages`:
- Image data read, `NSImage` creation, `CGImage` extraction
- Thumbnail generation (context creation, draw, resize)
- `ImageItem` construction
- Convert `DispatchQueue`/`DispatchGroup`/`NSLock` pattern to `withTaskGroup` async/await

### 2.3 Inject into `CollageViewModel`

**Modified file:** `ViewModel/CollageViewModel.swift`

- Add `private let imageLoader: ImageLoading` property
- Add to designated init
- Convenience init passes `ImageLoader()`
- Replace `addImages` body with `let items = await imageLoader.loadImages(from: urls)`
- Mark `addImages` as `async`

### 2.4 Update `browseImages` callback

Same file. Change:
```swift
// Before
self?.addImages(from: panel.urls)

// After
Task { [weak self] in
    await self?.addImages(from: panel.urls)
}
```

### 2.5 Update tests

**Modified file:** `CollageViewModelTests.swift`

- Add `MockImageLoader` with configurable return value
- Update all VM constructions to include mock image loader
- Target: `CollageViewModel` reduced from 655 → ~400 lines

---

## Phase 3a — Saliency Task Cancellation

**Addresses:** Issue #5 (stale saliency tasks)

### 3a.1 Track saliency task

**Modified file:** `ViewModel/CollageViewModel.swift`

```swift
private var saliencyTask: Task<Void, Never>?
```

### 3a.2 Cancel before starting new analysis

In `analyzeSaliency()`:
```swift
func analyzeSaliency() async {
    saliencyTask?.cancel()
    saliencyTask = Task { ... }
}
```

Also cancel in `clearAll()`.

### 3a.3 Update callers

In `addImages`, `removeImage`, `moveImages` — no change needed. They fire `Task { await analyzeSaliency() }`, which will self-cancel inside `analyzeSaliency`.

---

## Phase 3b — Mosaic Reshuffle Button

**Addresses:** Issue #6 (mosaic randomness)

### 3b.1 Add reshuffle method to `CollageViewModel`

**Modified file:** `ViewModel/CollageViewModel.swift`

```swift
func reshuffleMosaic() {
    guard layoutStyle == .mosaic else { return }
    regenerateLayout()
}
```

No changes to `LayoutGenerator` — randomness stays in `generateMosaic`, but is now user-triggered.

### 3b.2 Add UI button

**Modified file:** `ContentView.swift` (or wherever layout controls live)

Add a "Reshuffle" button, visible only when `layoutStyle == .mosaic`, bound to `viewModel.reshuffleMosaic()`.

---

## Phase 3c — Fix Test Pollution

**Addresses:** Issue #8 (tests pollute production namespace)

### 3c.1 Add test accessor to `CollageViewModel`

**Modified file:** `ViewModel/CollageViewModel.swift`

```swift
#if DEBUG
var testCropManager: CropManager { cropManager }
#endif
```

### 3c.2 Remove extension from test file

**Modified file:** `CollageViewModelTests.swift`

- Delete `extension CollageViewModel` block (lines 172-208)
- In `saliencyErrorSetsErrorMessage` test (line 134), replace `vm.cropManager_computeInitialCrops()` with:
  ```swift
  vm.testCropManager.computeInitialCrops(panels: vm.panels, images: vm.images)
  vm.cropMap = vm.testCropManager.cropMap
  ```

---

## Phase 3d — Remove Dead Code

**Addresses:** Issue #9 (ImagePickerGrid unused)

### 3d.1 Delete file

**Deleted file:** `Views/ImagePickerGrid.swift`

### 3d.2 Remove from Xcode project

Remove file reference from `CollageMaker.xcodeproj/project.pbxproj`.

---

## Verification

After each phase:
1. Build succeeds with zero warnings
2. All 65+ existing tests pass
3. No new force unwraps or `as!` casts introduced

After all phases:
1. `CollageViewModel` target: ~400 lines (from 655)
2. `UserDefaults.standard` appears 0 times in `CollageViewModel.swift`
3. `UserDefaults.standard` appears 0 times in `TitleStyle.swift`
4. `dispatchGroup.wait()` appears 0 times in codebase
5. `ImagePickerGrid` appears 0 times in codebase
6. `extension CollageViewModel` does not exist in test target

---

## Files Summary

### New files
- `Services/SettingsStorage.swift` — Protocol + `UserDefaultsSettingsStorage` + `InMemorySettingsStorage`
- `Services/ImageLoader.swift` — `ImageLoading` protocol + `ImageLoader` service

### Modified files
- `ViewModel/CollageViewModel.swift` — Settings injection, ImageLoader injection, saliency cancellation, reshuffle, test accessor
- `Models/TitleStyle.swift` — Remove persistence methods
- `Views/ContentView.swift` — Reshuffle button
- `CollageMakerTests/CollageViewModelTests.swift` — Mock updates, remove test extension
- `_agent_docs/change-requests/round-7.md` — Canvas size change request

### Deleted files
- `Views/ImagePickerGrid.swift`

### Defer
