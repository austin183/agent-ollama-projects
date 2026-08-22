# Session 1 — 2026-05-10

### Implementation Phases 1–5: Models, Services, ViewModel, Views, App Wiring

**Goal:** Build the complete application from a fresh Xcode project, incorporating all Prototype 1 lessons.

**Files Created:**
- `Models/CanvasConfig.swift` — Shared constants (canvas size, preview size)
- `Models/LayoutStyle.swift` — `uniform`, `hero`, `mosaic` enum
- `Models/ImageItem.swift` — Loaded image wrapper
- `Models/ImagePanel.swift` — Panel struct + `CropInfo` with `panelId: UUID`
- `Models/SaliencyResult.swift` — Center of interest + crop helper
- `Services/SaliencyAnalyzer.swift` — `actor`, `SaliencyAnalysis` protocol, Vision saliency + face detection
- `Services/LayoutGenerator.swift` — Pure struct, supports all 3 layout styles
- `Services/CollageAssembler.swift` — `class`, `CollageAssembly` protocol, CG compositing
- `ViewModel/CropManager.swift` — `@MainActor` class, gesture state machine, `[UUID: CropInfo]` dict
- `ViewModel/CollageViewModel.swift` — `@MainActor` thin orchestrator (~200 lines), DI
- `Views/ImagePickerView.swift` — Drag-and-drop + NSOpenPanel folder browse
- `Views/CollageEditorView.swift` — Preview + per-panel gesture overlays + coordinate conversion
- `Views/PanelCropEditor.swift` — Panel info + Reset Crop button
- `Views/ExportPanel.swift` — Title, quality, background color, export button
- `ContentView.swift` — NavigationSplitView with sidebar, editor, detail
- `CollageMakerApp.swift` — `@StateObject` + `.environmentObject`, `defaultSize`

**Key Architectural Decisions:**
- `CropManager` extracted from the start — no god-class ViewModel
- `[UUID: CropInfo]` dictionary for O(1) crop storage — no `CGRect ==` bugs
- Per-panel gesture overlays via `PanelGestureOverlay` struct — no wrong-panel targeting
- Protocol-based DI (`SaliencyAnalysis`, `CollageAssembly`) — testable with mocks
- `@EnvironmentObject` only — no `@ObservedObject` crashes
- `.onReceive($publisher.dropFirst())` pattern — avoids `.onChange` tracker loss

**Build Issues Encountered and Resolved:**
1. `ObservableObject` missing `import Combine` — added to ViewModel
2. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting caused protocol isolation conflicts — removed from `project.pbxproj`, added explicit `@MainActor` to ViewModel/CropManager
3. `CGImage.imageOrientation` doesn't exist — used `CGImagePropertyOrientation.up` instead
4. `CGBitmapInfo.noneSkipLast` not available — used `[.byteOrder32Big]` only
5. `inout CGContext` can't take `let` — changed to `drawTitle(into:context, ...)`
6. `NSColorPicker` has no `.frame()` — replaced with `NSViewRepresentable` color well
7. SwiftUI `Color` ↔ `NSColor` conversion issues — used `NSColorWell` directly
8. `SimultaneousGesture` API misuse — refactored to separate `.simultaneousGesture()` modifiers
9. `MagnificationGesture.Value` is `CGFloat`, not object with `.magnification` — fixed
10. `UTType` vs string identifiers in `.onDrop()` — used `UTType.identifier` mapping
11. `@StateObject` with non-`ObservableObject` — fixed with `import Combine`
12. `UniformTypeIdentifiers` import missing in multiple files — added where needed

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero warnings (excluding AppIntents metadata)
- Tests: **Not yet written** — pending Session 2
