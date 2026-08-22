# Code Review: CollageMaker (2026-06-12)

## Executive Summary
The CollageMaker project exhibits a strong foundation with a well-defined service layer and effective use of modern Swift concurrency and SwiftUI patterns. However, the application has evolved into a state where the `CollageViewModel` has become a "God Object," centralizing too much responsibility. Additionally, significant business logic has leaked into the `CollageEditorView`, violating the separation of concerns between presentation and logic.

## 1. Architectural Analysis

### SOLID Principles & Design
- **Single Responsibility Principle (SRP)**:
    - **Services**: High adherence. `LayoutGenerator`, `SaliencyAnalyzer`, and `CollageAssembler` are focused and cohesive.
    - **ViewModel**: Major violation. `CollageViewModel` manages state, undo history, caching, throttling, and service orchestration.
    - **Views**: Violation. `CollageEditorView` handles coordinate transforms, hit testing, and gesture state.
- **Open/Closed Principle (OCP)**: The `LayoutStrategy` pattern in `LayoutGenerator` is an excellent example of OCP, allowing new layouts to be added without modifying core logic.
- **Dependency Inversion Principle (DIP)**: Strong use of protocols for core services (`SaliencyAnalysis`, `CollageAssembly`), ensuring high testability and flexibility.

### Data Flow & State
- **Flow**: Generally unidirectional (`View` $\rightarrow$ `ViewModel` $\rightarrow$ `Manager` $\rightarrow$ `Service`), which is maintainable.
- **State Management**: Use of version counters to trigger `@Observable` updates for collections is a necessary and effective workaround for SwiftUI's limitations.

---

## 2. Detailed Findings

### A. ViewModel Bloat & SRP (`CollageViewModel.swift`)
- **Leaked Responsibilities**:
    - **Title Layout**: Low-level CoreText measurements and coordinate math (lines 36-86) should be moved to a `TitleLayoutManager` or `TitleMetrics` service.
    - **Assembly Mapping**: The translation layer in `buildAssemblyConfig()` (lines 825-866) should be moved to a factory or `AssemblyConfig` static method.
    - **Throttling**: Timing logic for UI updates (lines 122, 752) should reside in `PreviewManager` or a `RenderCoordinator`.
- **Interface Bloat**:
    - **Crop Delegation**: Methods for panning and cropping (lines 666-821) are simple pass-throughs to `CropManager`.
    - **Boilerplate**: Repetitive methods for `TitleStyle` properties (lines 1003-1051).

### B. Undo Management
- **Repetitive Logic**: Highly redundant `didSet` blocks (lines 135-203, 254-301) for undo registration.
- **Missing Coverage**: `assignImage(panelId:imageIndex:)` (lines 588-592) modifies state without registering an undo action.
- **Inconsistency**: Mixed use of immediate and debounced undo registration across style properties.

### C. View Logic Leak (`CollageEditorView.swift`)
- **Business Logic in UI**:
    - **Coordinate Transforms**: Canvas-to-preview frame calculations are performed directly in `body` (lines 36-41).
    - **Complex Gestures**: Title resize and drag logic (lines 164-241) and image swap logic (lines 243-285) belong in the ViewModel.
    - **Geometric Testing**: `panelAt` hit testing (line 336) should be moved to `CropManager` or the ViewModel.
- **Performance**: `panelFrames` and `panelGeometries` are recalculated on every `body` evaluation (lines 36-41).

### D. Concurrency & Safety
- **Unstructured Tasks**: `addImages`, `removeImage`, and `moveImages` launch detached tasks without handles, potentially leading to redundant saliency analysis.
- **Threading**: `Debouncer` closures modifying `@MainActor` properties may cause issues if the debouncer runs on a background queue.
- **Sendability**: `CollageAssembler` uses `@unchecked Sendable` (line 79); it should be converted to an `actor`.

---

## 3. Actionable Recommendations

### High Priority (Immediate Fixes)
1. **Decompose `CollageViewModel`**: Split the ViewModel into feature-specific managers (e.g., `LayoutViewModel`, `TitleViewModel`) coordinated by a leaner main ViewModel.
2. **Clean `CollageEditorView`**: Move all coordinate math, hit testing, and gesture state updates from the View to the ViewModel.
3. **Fix Undo Gaps**: Add undo registration to `assignImage` and implement a generic `update` helper to remove repetitive `didSet` blocks.
4. **Manage Analysis Tasks**: Store `Task` handles for saliency analysis to allow cancellation of stale requests.

### Medium Priority (Refactoring)
1. **Move Title Layout Logic**: Relocate `TitleBoundsCache` and related metrics to a dedicated `TitleRenderingService`.
2. **Actor Transition**: Convert `CollageAssembler` to an `actor` to remove `@unchecked Sendable`.
3. **Cache View Frames**: Store `panelFrames` in the ViewModel and update only on layout/canvas changes.
4. **Standardize Undo Timing**: Align undo registration strategies across all style properties.

## 4. Conclusion
The project is in a "growth pain" phase where a once-simple ViewModel has become a bottleneck for maintainability. By aggressively decomposing the ViewModel and purging business logic from the View layer, the codebase will return to a state of high maintainability and scalability.
