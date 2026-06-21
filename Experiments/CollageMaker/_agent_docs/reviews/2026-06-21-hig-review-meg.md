# HIG Review: CollageMaker (2026-06-21)

This review evaluates the CollageMaker macOS application against the Human Interface Guidelines (HIG) and project-specific desktop conventions defined in `.opencode/skills/building-macos-apps/references/conventions/`.

## Overall Assessment
The application strongly adheres to macOS desktop patterns, particularly in its use of `NavigationSplitView`, `UndoManager` integration, and Command menu exposure. It feels like a native desktop app rather than a ported mobile app.

## Detailed Analysis

### 1. Desktop Conventions & Layout
- **Scene Architecture**: Correctly uses `WindowGroup` for the main editor and a dedicated `Settings` scene.
- **Navigation**: The `NavigationSplitView` (Sidebar $\rightarrow$ Editor $\rightarrow$ Inspector) is the appropriate choice for this workflow.
- **Sidebar Appearance**: The sidebar uses a standard `Form` layout. 

### 2. Commands & Keyboard Shortcuts
- **Standardization**: Implements expected shortcuts like `Cmd-O` (Open/Add) and `Cmd-S` (Save/Export).
- **Custom Shortcuts**: Layout switching (`Cmd-1/2/3`) and Saliency toggling (`Cmd-Shift-H`) are intuitive and correctly exposed in the menu bar via `CollageCommands`.
  - **Missing Layout Options**
    - Diagonal Slices
    - Hexagonal
- **Discoverability**: Actions are available both in the toolbar/inspector and the main menu.

### 3. Alerts & Feedback
- **Destructive Actions**: The "Clear All" workflow correctly uses a confirmation alert with a destructive role and a leading "Cancel" button.
- **Progress Indication**: 
  - **Finding**: While `isProcessing` is used to disable buttons, there is no visible `ProgressView` (spinner or bar) when heavy operations (like saliency analysis or export) are running. HIG recommends indeterminate indicators for background processing.
  - **Severity**: Medium (User Experience)

### 4. Accessibility
- **Semantic Markup**: Toolbar buttons are well-annotated with `.accessibilityLabel` and `.accessibilityHint`.
- **State Indication**: Selected panels use `.accessibilityAddTraits([.isSelected])`, allowing VoiceOver users to identify the active element.
- **Contrast**: Uses system-adaptive colors (`.tint`, `.secondary`), ensuring compatibility with "Increase Contrast" settings.

### 5. Context Menus
- **Implementation**: Panels feature a concise context menu with "Reset Crop" and "Remove Image".
- **Destructive Placement**: The "Remove Image" action is correctly placed at the bottom with a `.destructive` role.

### 6. Undo and Redo
- **Integration**: High-quality `UndoManager` implementation.
- **Action Naming**: Uses descriptive names (e.g., "Remove Image", "Change Layout") instead of generic "Undo".
- **Gesture Batching**: Correctly implements `beginUndoGrouping()` and `endUndoGrouping()` for continuous adjustments (pinch/pan), preventing the undo stack from being flooded with intermediate frames.

## Summary of Recommendations

| Issue | Recommendation | Severity |
|---|---|---|
| Lack of Progress Feedback | Add a `ProgressView` (circular/indeterminate) when `viewModel.isProcessing` is true. | Medium |
| Accessibility: Reduce Motion | Explicitly guard any future animations with `accessibilityReduceMotion` environment value. | Low |
