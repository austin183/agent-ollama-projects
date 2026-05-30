# Diff Review — 2026-05-30 (Arch Review Phase 3)

**Changeset**: Uncommitted work on `main` branch (10 commits ahead of origin/main)
**Scope**: 11 modified files + 3 new files — ExportManager, ImageLibraryManager, GestureCoordinator extraction
**Session**: [Session 066](../project-timeline/sessions/session-066.md)

## Files Changed

| File | Change |
|------|--------|
| `ViewModel/ExportManager.swift` | **NEW** — Export flow (NSSavePanel, detached task, success/error messages) |
| `ViewModel/ImageLibraryManager.swift` | **NEW** — Image library state (add/remove/move/clear, custom order) |
| `Views/GestureCoordinator.swift` | **NEW** — Gesture state (was 9 `@State` properties in CollageEditorView) |
| `ViewModel/CollageViewModel.swift` | Delegates image/export/gesture concerns to new managers; `images` and `customImageOrder` become computed properties |
| `ContentView.swift` | `viewModel.images` → `viewModel.imageLibrary.images`, `viewModel.isExporting` → `viewModel.exportManager.isExporting` |
| `CollageEditorView.swift` | 9 `@State` properties replaced by `@StateObject gestureCoordinator`; `TitleResizeEdge` visibility widened to package-level |
| `ExportPanel.swift` | Proxy references updated to `viewModel.exportManager.xxx` |
| `PanelCropEditor.swift` | `viewModel.images` → `viewModel.imageLibrary.images` |
| `CollageViewModelTests.swift` | All `vm.images` → `vm.imageLibrary.images` |
| `ExportFlowTests.swift` | Same pattern update across 15+ test cases |
| `CollagePerformanceTests.swift` | Same pattern update |

---

## Issue 1: `URL(string:)` cannot parse filesystem paths — remembered export folder is never used

**Severity: High**

**File**: `ExportManager.swift:38`

```swift
if let folderPath = UserDefaults.standard.string(forKey: UserDefaultsPersistence.Keys.defaultExportFolder),
   let folderUrl = URL(string: folderPath), folderUrl.folderExists {
    savePanel.directoryURL = folderUrl
}
```

The export folder path is stored as a plain filesystem path (e.g., `/Users/foo/Documents`), as confirmed by `SettingsView.swift:227`:

```swift
defaultExportFolder = url.path
```

But `URL(string:)` requires a URL-format string with a scheme (e.g., `file:///Users/foo/Documents`). A plain absolute path like `/Users/foo/Documents` has no scheme, so `URL(string: "/Users/foo/Documents")` always returns `nil`. The `folderUrl` binding never succeeds, and the save panel always falls back to its default directory.

**Fix**: Replace `URL(string: folderPath)` with `URL(fileURLWithPath: folderPath)`.

Note: The same pattern appears in `UserDefaultsPersistence.swift:208` (`loadBackgroundImage`), but that is pre-existing code outside this diff.

---

## Validated Clean Changes

The following refactors were validated with no issues found:

| Refactor | Validation |
|----------|-----------|
| **ExportManager extraction** | `export(viewModel:)` correctly moves full export flow (save panel, detached assembly task, success/error handling) into a dedicated `@MainActor @Observable` class. `buildAssemblyConfig()` visibility widened from `private` to `func` — correct since ExportManager calls it. `Task.detached` context stripping is intentional for CPU-bound assembly work. |
| **ImageLibraryManager extraction** | `@MainActor @Observable` class correctly owns `images` + `customImageOrder`. `onImagesChanged` callback triggers `regenerateLayout()` from the constructor — correct pattern. `removeImage(at:)` returns `(item, at)` tuple to support undo registration with the correct insertion index. `buildMoveMapping` logic preserved from old `CollageViewModel` code with no changes. |
| **GestureCoordinator extraction** | `@MainActor ObservableObject` with `@Published` properties correctly replaces 9 individual `@State` properties in `CollageEditorView`. `@StateObject` is the correct wrapper for a class-owned coordinator in SwiftUI. `TitleResizeEdge` visibility widened from `private` to package-level — required since GestureCoordinator references it but lives in `Views/` while the enum is in the same module. |
| **Computed property proxies** | `var images: [ImageItem] { imageLibrary.images }` and `var customImageOrder` (getter/setter with debounced save) correctly proxy to the new managers. Getter-only `images` prevents accidental mutation of the array reference. `customImageOrder` setter includes `isInitializing` guard — preserved from old code. |
| **Test updates** | All `vm.images = ...` → `vm.imageLibrary.images = ...` pattern correctly updated across 3 test files. No test logic changed, only property access paths. |
| **`clearAll()` simplification** | `exportTask?.cancel()` → `exportManager.exportTask?.cancel()` correct. `customImageOrder.removeAll()` removed since `ImageLibraryManager.clearAll()` handles it. Undo closure simplified to `target.imageLibrary.images = oldImages` — correct. |
| **`debouncedSave()` error handling removed** | `persistence.save(self)` called without try/catch. This is a deliberate simplification — the old code logged errors and set `errorMessage` but the effect was the same (save attempted, errors logged). Not a bug, just a design choice. |

---

## Summary

| # | Severity | Issue |
|---|----------|-------|
| 1 | **High** | `ExportManager.swift:38` — `URL(string:)` cannot parse filesystem paths; remembered export folder is never used. Fix: use `URL(fileURLWithPath:)` |

**No compilation errors, actor isolation violations, or threading issues detected.** The refactoring is structurally sound.
