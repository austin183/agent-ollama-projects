# Architectural Review Fixes — Implementation Plan

**Date:** 2026-05-26
**Source:** `_agent_docs/reviews/2026-05-26-full-architectural-review.md`
**Scope:** Must Fix (2) + Should Fix (3) = 5 items

---

## 1. Fix `exportQuality` Default Value (0 → 0.92)

**Files:** `CollageViewModel.swift:116`, `UserDefaultsPersistence.swift:97`

### CollageViewModel.swift
Change line 116:
```swift
// BEFORE
var exportQuality: Double = 0 {

// AFTER
var exportQuality: Double = 0.92 {
```

### UserDefaultsPersistence.swift
Change line 97 to use a default-aware load (matching the `loadBackgroundOpacity` pattern):
```swift
// BEFORE
let exportQuality = defaults.double(forKey: Keys.exportQuality)

// AFTER
let exportQuality: Double
if defaults.object(forKey: Keys.exportQuality) != nil {
    exportQuality = defaults.double(forKey: Keys.exportQuality)
} else {
    exportQuality = 0.92
}
```

---

## 2. Add Undo Registration for `backgroundImage`

**File:** `CollageViewModel.swift:175-184`

```swift
// BEFORE
var backgroundImage: NSImage? {
    didSet {
        guard !isInitializing else { return }
        if backgroundImage == nil {
            backgroundImagePath = nil
        }
        debouncedSave()
        updatePreview()
    }
}

// AFTER
var backgroundImage: NSImage? {
    didSet {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.backgroundImage = oldValue
        }
        undoManager.setActionName("Change Background Image")
        if backgroundImage == nil {
            backgroundImagePath = nil
        }
        debouncedSave()
        updatePreview()
    }
}
```

---

## 3. Remove Duplicate `ViewModelUserDefaultsKeys` Enum

**Files:** `CollageViewModel.swift:12-26`, `AGENTS.md:59`

### CollageViewModel.swift
Delete lines 12-26 entirely (the `ViewModelUserDefaultsKeys` enum block).

### AGENTS.md
Update line 59:
```
// BEFORE
- **UserDefaults keys** are centralized in `ViewModelUserDefaultsKeys` inside `CollageViewModel.swift`

// AFTER
- **UserDefaults keys** are centralized in `UserDefaultsPersistence.Keys`
```

---

## 4. Move `TitleStyle` UserDefaults Methods into `UserDefaultsPersistence`

**Files:** `TitleStyle.swift:35-48`, `UserDefaultsPersistence.swift:67`, `UserDefaultsPersistence.swift:94`

### TitleStyle.swift
Delete the extension block at lines 35-48 (`fromUserDefaults()` and `saveToUserDefaults()`).

### UserDefaultsPersistence.swift — Save
Change line 67:
```swift
// BEFORE
viewModel.titleStyle.saveToUserDefaults()

// AFTER
if let data = try? JSONEncoder().encode(viewModel.titleStyle) {
    defaults.set(data, forKey: Keys.titleStyle)
}
```

### UserDefaultsPersistence.swift — Load
Change line 94:
```swift
// BEFORE
let titleStyle = TitleStyle.fromUserDefaults()

// AFTER
let titleStyle: TitleStyle
if let data = defaults.data(forKey: Keys.titleStyle),
   let decoded = try? JSONDecoder().decode(TitleStyle.self, from: data) {
    titleStyle = decoded
} else {
    titleStyle = .default
}
```

---

## 5. Document `panelAssignments` as Intentionally Ephemeral

**File:** `CollageViewModel.swift:198`

```swift
// BEFORE
var panelAssignments: [UUID: Int] = [:]

// AFTER
/// Maps panel UUIDs to image indices for custom assignments.
/// Intentionally NOT persisted — panel UUIDs change on every layout
/// regeneration. The canonical persisted source is `customImageOrder`,
/// which is used to rebuild panelAssignments in `regenerateLayout()`.
var panelAssignments: [UUID: Int] = [:]
```

---

## Verification

After applying all changes:
1. Build: `bash script/build_and_run.sh --verify`
2. Tests: `xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests`
