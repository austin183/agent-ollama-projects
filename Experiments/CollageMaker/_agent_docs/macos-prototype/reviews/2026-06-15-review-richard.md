# Code Review: CollageMaker (Richard's Implementation)
**Date**: 2026-06-15
**Reviewer**: opencode

## Overview
The CollageMaker application is a sophisticated implementation of a photo collage tool. It demonstrates a high level of technical proficiency in macOS graphics frameworks (CoreGraphics, CoreText, Vision) and modern Swift concurrency. The architecture is generally well-organized, following a clear ViewModel-Service-Model separation, with a strong emphasis on testability and performance.

## Architectural Quality

### Strengths
- **Modern Concurrency**: Excellent use of Swift Actors and `TaskGroup` in `SaliencyAnalyzer` and `ImageLibraryManager` to handle expensive I/O and ML tasks without blocking the main thread.
- **Rendering Pipeline**: The combination of `RenderScheduler` and version counters in `PreviewManager` provides a robust solution to the "flicker" and "race" problems common in real-time graphics apps.
- **Extensibility**: The `LayoutStrategy` protocol and factory pattern in `LayoutGenerator` allow for new layout styles to be added without modifying the core logic (Open/Closed Principle).
- **Thread-Safe Graphics**: `TitleRendererCT` correctly solves the AppKit main-thread restriction for `NSAttributedString` by moving rendering to CoreText on background threads.

### Weaknesses
- **Logic Leakage**: There is significant business logic (coordinate math, crop algorithms) leaking into the SwiftUI views, particularly in `PanelCropEditor` and `CollageEditorView`.
- **Orchestrator Bloat**: `CollageViewModel` is becoming a "God Class" by managing everything from undo orchestration to manual versioning and debouncing.
- **Circular Dependencies**: A bidirectional relationship between `ImageCoordinator` and `CollageViewModel` creates architectural fragility.

---

## SOLID Principles Review

### Single Responsibility Principle (SRP)
- $\color{red}{\text{Violation}}$: `PanelCropEditor.swift` and `CollageEditorView.swift` contain complex algorithms for crop resizing and title interaction logic. This belongs in `CropManager` or `TitleManager`.
- $\color{red}{\text{Violation}}$: `CollageAssembler.swift` implements too many roles (Assembly, Panel, Background, Title, Overlay). It should be split into a final `Assembler` and a `ComponentRenderer`.
- $\color{red}{\text{Violation}}$: `SaliencyResult.swift` includes coordinate transformation logic (`cropOrigin`), which should be moved to a service or utility.

### Dependency Inversion Principle (DIP)
- $\color{yellow}{\text{Partial}}$: `CollageAssembler` relies on concrete static methods in `PanelRenderer` (`drawPanels`), making it difficult to mock individual rendering stages.
- $\color{green}{\text{Pass}}$: The use of protocols for `SaliencyAnalysis` and `CollageAssembly` is exemplary and ensures the ViewModel remains decoupled from implementation details.

### Open/Closed Principle (OCP)
- $\color{green}{\text{Pass}}$: The layout system is highly extensible via `LayoutStrategy`. Adding a new layout type requires no changes to the existing `LayoutGenerator` logic.

---

## Separation of Concerns

### Layer Boundaries
The boundary between the **ViewModel** and **Views** is blurred. The views are performing heavy lifting for coordinate projections and clamping. This not only violates SRP but also degrades performance, as these calculations run on every SwiftUI `body` evaluation.

### Coordination
The "Version Counter" pattern used to trigger UI updates for nested mutable collections is a clever workaround for `@Observable` limitations, but it is error-prone. Missing a single increment can lead to stale UI state.

---

## Detailed Findings

### Code Quality & Performance
- **Magic Numbers**: `LayoutGenerator.swift` contains several hardcoded split ratios and probability thresholds (e.g., `0.25`, `0.33`, `0.6`). These should be extracted to a configuration struct.
- **Computational Waste**: `CollageEditorView` computes `panelFrames` via `reduce` in its `body` property. This should be cached in the ViewModel.
- **Memory**: Efficient use of `CGImage.cropping(to:)` prevents unnecessary memory overhead during image processing.

### SwiftUI Best Practices
- **View Complexity**: `CollageEditorView.body` is overloaded. It should be decomposed into smaller sub-views (e.g., `CanvasBackgroundView`, `TitleInteractionOverlay`).
- **Accessibility**: Title resize handles lack accessibility labels and traits, making the interactive elements invisible to VoiceOver users.

### Testing & Robustness
- **Robustness**: The `SaliencyAnalyzer` handles individual image failures gracefully within a `TaskGroup`, preventing a single corrupt file from failing the entire batch.
- **Testability**: High. The use of protocol-based services makes the majority of the business logic easily mockable.

---

## Suggestions for Improvement

### High Priority
1. **Move Logic to Managers**: Relocate `adjustCropDuringDrag`, `handleResize`, and title interaction logic from Views to `CropManager` and `TitleManager`.
2. **Decouple `ImageCoordinator`**: Replace the `viewModel` reference in `ImageCoordinator` with a delegate protocol to break the circular dependency.
3. **Refactor `CollageViewModel`**: Extract undo registration and debouncing logic into a dedicated `UndoCoordinator` to reduce the size and complexity of the ViewModel.

### Medium Priority
1. **Extract Coordinate Utilities**: Create a `CoordinateConverter` utility to centralize the logic for flipping Vision coordinates to CG coordinates.
2. **Decompose `CollageEditorView`**: Break the main editor body into smaller, focused SwiftUI views.
3. **Constantize Layout Heuristics**: Move magic numbers in `LayoutGenerator` to a `MosaicConfig` struct.

### Nitpicks
- Move `SeededPRNG` from `LayoutGenerator` to a general `Math+Utils.swift` file.
- Transition `CollageAssembler` from `@unchecked Sendable` to a fully `Sendable` design.
- Add accessibility labels to title resize handles.

## Final Decision
**$\color{orange}{\text{Request Changes}}$**

The implementation is technically impressive and functionally complete. However, the **leakage of business logic into the UI layer** and the **growing complexity of the ViewModel** are significant architectural debts that will impede long-term maintainability. Once the logic is properly pushed down into the Managers and the circular dependencies are resolved, this will be a gold-standard implementation.
