# Apple Sample Code Relevant to CollageMaker

**Date:** 2026-05-11
**Source:** https://developer.apple.com/documentation/SampleCode
**Purpose:** Identify Apple sample projects with patterns, techniques, and practices that would benefit CollageMaker's UI and image processing capabilities.

---

## Tier 1: Direct Relevance (Study First)

These samples address the exact gaps identified in our UI patterns review: user control, drag-and-drop reordering, desktop patterns, and image manipulation.

### SwiftUI Desktop Patterns

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Building a great Mac app with SwiftUI** | [Link](https://developer.apple.com/documentation/SwiftUI/building-a-great-mac-app-with-swiftui) | **Critical** - macOS-specific SwiftUI patterns: window management, menu bar, dock, sidebar, toolbar, commands, keyboard shortcuts, multi-window. Directly addresses our missing `.commands` and `.toolbar` patterns. |
| **Landmarks: Building an app with Liquid Glass** | [Link](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass) | **Critical** - Full macOS SwiftUI app with NavigationSplitView, sidebar, detail, toolbar, inspector, and Liquid Glass effects. Reference implementation for three-column layout. |
| **Landmarks: Extending horizontal scrolling under a sidebar or inspector** | [Link](https://developer.apple.com/documentation/SwiftUI/Landmarks-Extending-horizontal-scrolling-under-a-sidebar-or-inspector) | **High** - `.toolbarBackground` and `.toolbarBackgroundVisibility` for extending content under sidebar/inspector. Useful for canvas preview under sidebar. |
| **Landmarks: Refining the system provided Liquid Glass effect in toolbars** | [Link](https://developer.apple.com/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars) | **Medium** - Toolbar appearance customization. Relevant if we add toolbar items. |
| **Landmarks: Applying a background extension effect** | [Link](https://developer.apple.com/documentation/SwiftUI/Landmarks-Applying-a-background-extension-effect) | **Medium** - `.background` extension beyond view bounds. Could apply to canvas bleed effects. |
| **Adopting drag and drop using SwiftUI** | [Link](https://developer.apple.com/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI) | **Critical** - SwiftUI `onDrag`/`onDrop` patterns. Essential for implementing image reordering in sidebar and drag-to-panel assignment on canvas. |
| **Bringing robust navigation structure to your SwiftUI app** | [Link](https://developer.apple.com/documentation/SwiftUI/Bringing-robust-navigation-structure-to-your-swiftui-app) | **High** - Navigation patterns, selection state, and routing. Relevant for panel selection and detail panel management. |
| **Food Truck: Building a SwiftUI multiplatform app** | [Link](https://developer.apple.com/documentation/SwiftUI/food-truck-building-a-swiftui-multiplatform-app) | **High** - Full-featured SwiftUI app with maps, lists, detail views, and state management. Good reference for view composition patterns. |
| **Managing model data in your app** | [Link](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app) | **High** - `@Observable` macro patterns, CRUD operations, and data flow. Relevant for migrating from `@ObservableObject`. |
| **Migrating from the Observable Object protocol to the Observable macro** | [Link](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) | **High** - Step-by-step migration guide. Directly applicable to `CollageViewModel`. |
| **Composing custom layouts with SwiftUI** | [Link](https://developer.apple.com/documentation/SwiftUI/composing-custom-layouts-with-swiftui) | **Medium** - Custom `Layout` protocol. Relevant if we build custom panel layout UI. |
| **Creating visual effects with SwiftUI** | [Link](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI) | **Medium** - Blur, color invert, and other visual modifiers. Useful for background blur effects. |
| **Add rich graphics to your SwiftUI app** | [Link](https://developer.apple.com/documentation/SwiftUI/add-rich-graphics-to-your-swiftui-app) | **Medium** - Drawing with SwiftUI shapes and paths. Relevant for custom resize handles on panels. |
| **Customizing window styles and state-restoration behavior in macOS** | [Link](https://developer.apple.com/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS) | **Medium** - Window style customization and state restoration. Relevant for `@AppStorage` migration. |
| **Bringing multiple windows to your SwiftUI app** | [Link](https://developer.apple.com/documentation/SwiftUI/bringing-multiple-windows-to-your-swiftui-app) | **Low** - Multi-window patterns. Not needed now but useful for future "compare layouts" feature. |

### Image Processing (Accelerate / vImage)

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Calculating the dominant colors in an image** | [Link](https://developer.apple.com/documentation/Accelerate/calculating-the-dominant-colors-in-an-image) | **High** - Extract dominant colors from an image using vImage histogram. Enables "auto-match background color to image" feature. |
| **Blurring an image** | [Link](https://developer.apple.com/documentation/Accelerate/blurring-an-image) | **High** - Box blur and Gaussian blur with vImage. Enables blurred background image mode. |
| **Applying tone curve adjustments to images** | [Link](https://developer.apple.com/documentation/Accelerate/applying-tone-curve-adjustments-to-images) | **Medium** - Per-channel tone curves. Could power per-panel image adjustments. |
| **Adjusting the brightness and contrast of an image** | [Link](https://developer.apple.com/documentation/Accelerate/adjusting-the-brightness-and-contrast-of-an-image) | **Medium** - Level adjustments with vImage. Per-panel brightness/contrast controls. |
| **Adjusting the hue of an image** | [Link](https://developer.apple.com/documentation/Accelerate/adjusting-the-hue-of-an-image) | **Low** - Hue rotation. Nice-to-have for creative control. |
| **Applying transformations to selected colors in an image** | [Link](https://developer.apple.com/documentation/Accelerate/applying-transformations-to-selected-colors-in-an-image) | **Low** - Color range selection and transformation. Advanced color grading. |
| **Adding a bokeh effect to images** | [Link](https://developer.apple.com/documentation/Accelerate/adding-a-bokeh-effect-to-images) | **Low** - Depth-of-field blur. Artistic panel effect. |
| **Integrating vImage pixel buffers into a Core Image workflow** | [Link](https://developer.apple.com/documentation/Accelerate/integrating-vimage-pixel-buffers-into-a-core-image-workflow) | **Medium** - Bridging vImage and CoreImage. Useful for combining fast pixel operations with CI filters. |
| **Cropping to the subject in a chroma-keyed image** | [Link](https://developer.apple.com/documentation/Accelerate/cropping-to-the-subject-in-a-chroma-keyed-image) | **Low** - Subject isolation. Related to smart cropping but different approach. |

### Vision Framework

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Highlighting Areas of Interest in an Image Using Saliency** | [Link](https://developer.apple.com/documentation/Vision/highlighting-areas-of-interest-in-an-image-using-saliency) | **Critical** - Reference implementation of saliency analysis. Our `SaliencyAnalyzer` should be compared against this for correctness and completeness. |
| **Segmenting and colorizing individuals from a surrounding scene** | [Link](https://developer.apple.com/documentation/Vision/segmenting-and-colorizing-individuals-from-a-surrounding-scene) | **High** - People segmentation with `VNGeneratePersonSegmentationRequest`. Enables "remove background" or "isolate subject" panel effect. |
| **Analyzing a selfie and visualizing its content** | [Link](https://developer.apple.com/documentation/Vision/analyzing-a-selfie-and-visualizing-its-content) | **Medium** - Combined face detection, saliency, and object detection. Pattern for multi-request Vision pipelines. |
| **Applying visual effects to foreground subjects** | [Link](https://developer.apple.com/documentation/Vision/applying-visual-effects-to-foreground-subjects) | **Medium** - Foreground/background separation for effects. Related to segmentation. |
| **Detecting Objects in Still Images** | [Link](https://developer.apple.com/documentation/Vision/detecting-objects-in-still-images) | **Low** - Rectangle, face, barcode, text detection. General Vision patterns. |
| **Generating high-quality thumbnails from videos** | [Link](https://developer.apple.com/documentation/Vision/generating-thumbnails-from-video) | **Low** - Image aesthetics scoring. Not directly applicable but interesting pattern. |

### PhotoKit

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Bringing Photos picker to your SwiftUI app** | [Link](https://developer.apple.com/documentation/PhotoKit/bringing-photos-picker-to-your-swiftui-app) | **High** - `PhotosPicker` SwiftUI component. Better alternative to our custom `NSOpenPanel` browse flow. Integrates with user's photo library. |
| **Implementing an inline Photos picker** | [Link](https://developer.apple.com/documentation/PhotoKit/implementing-an-inline-photos-picker) | **Medium** - Inline photo browsing within the app. Could replace our sidebar empty state. |

---

## Tier 2: Supporting Patterns (Study Next)

These samples provide patterns that would improve specific aspects of the app.

### AppKit Integration

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Integrating a Toolbar and Touch Bar into Your App** | [Link](https://developer.apple.com/documentation/AppKit/integrating-a-toolbar-and-touch-bar-into-your-app) | **Medium** - `NSToolbar` patterns. Reference for AppKit toolbar if SwiftUI `.toolbar` is insufficient. |
| **Navigating Hierarchical Data Using Outline and Split Views** | [Link](https://developer.apple.com/documentation/AppKit/navigating-hierarchical-data-using-outline-and-split-views) | **Low** - `NSSplitView` and `NSOutlineView`. Not directly applicable but good reference for split behavior. |
| **Supporting Collection View Drag and Drop Through File Promises** | [Link](https://developer.apple.com/documentation/AppKit/supporting-collection-view-drag-and-drop-through-file-promises) | **Medium** - Drag-and-drop reordering in `NSCollectionView`. Reference if SwiftUI drag-and-drop proves insufficient for image reordering. |
| **Supporting Table View Drag and Drop Through File Promises** | [Link](https://developer.apple.com/documentation/AppKit/supporting-table-view-drag-and-drop-through-file-promises) | **Low** - Similar to above but for `NSTableView`. |

### Core Image

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Generating an animation with a Core Image Render Destination** | [Link](https://developer.apple.com/documentation/CoreImage/generating-an-animation-with-a-core-image-render-destination) | **Low** - `CIRenderDestination` for efficient rendering. Not directly applicable but good pattern for batch rendering. |

### UIKit (iOS patterns, some applicable)

| Sample | URL | Relevance |
|--------|-----|-----------|
| **Adopting drag and drop in a table view** | [Link](https://developer.apple.com/documentation/UIKit/adopting-drag-and-drop-in-a-table-view) | **Low** - iOS drag-and-drop reordering. Reference patterns for SwiftUI adaptation. |
| **Adding menus and shortcuts to the menu bar and user interface** | [Link](https://developer.apple.com/documentation/UIKit/adding-menus-and-shortcuts-to-the-menu-bar-and-user-interface) | **Low** - Context menus and keyboard shortcuts. SwiftUI `.commands` is preferred. |
| **Adding context menus in your app** | [Link](https://developer.apple.com/documentation/UIKit/adding-context-menus-in-your-app) | **Low** - Context menu patterns. SwiftUI `.contextMenu` is the macOS equivalent. |

---

## Tier 3: Future Considerations (Nice to Have)

These samples are interesting but not immediately actionable.

| Sample | URL | Potential Use |
|--------|-----|---------------|
| **Creating visual effects with SwiftUI** | [Link](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI) | Panel transition effects, loading states |
| **Controlling the timing and movements of your animations** | [Link](https://developer.apple.com/documentation/SwiftUI/Controlling-the-timing-and-movements-of-your-animations) | Smooth panel reordering animations |
| **Using Core ML for semantic image segmentation** | [Link](https://developer.apple.com/documentation/CoreML/using-core-ml-for-semantic-image-segmentation) | Smart background removal for panels |
| **Detecting human body poses in an image** | [Link](https://developer.apple.com/documentation/CoreML/detecting-human-body-poses-in-an-image) | Smart cropping for portraits |
| **Classifying Images with Vision and Core ML** | [Link](https://developer.apple.com/documentation/CoreML/classifying-images-with-vision-and-core-ml) | Auto-categorize images for smart layout suggestions |
| **Selecting a selfie based on capture quality** | [Link](https://developer.apple.com/documentation/Vision/selecting-a-selfie-based-on-capture-quality) | Suggest best image for hero slot |
| **Creating a data visualization dashboard with Swift Charts** | [Link](https://developer.apple.com/documentation/Charts/creating-a-data-visualization-dashboard-with-swift-charts) | Layout preview thumbnails as mini-charts |
| **Highlighting app features with TipKit** | [Link](https://developer.apple.com/documentation/TipKit/HighlightingAppFeaturesWithTipKit) | Onboarding tips for new collage features |

---

## Recommended Research Order

Based on the gaps identified in our UI patterns review, here is the recommended order for studying these samples:

### Week 1: Desktop UI Patterns
1. **Building a great Mac app with SwiftUI** - Understand the full macOS app structure
2. **Landmarks: Building an app with Liquid Glass** - Study the three-column NavigationSplitView implementation
3. **Adopting drag and drop using SwiftUI** - Learn `onDrag`/`onDrop` for image reordering

### Week 2: State Management Migration
4. **Managing model data in your app** - Learn `@Observable` patterns
5. **Migrating from Observable Object to Observable macro** - Plan CollageViewModel migration
6. **Bringing robust navigation structure to your SwiftUI app** - Selection and routing patterns

### Week 3: Image Processing Enhancements
7. **Calculating the dominant colors in an image** - Implement auto-background color
8. **Blurring an image** - Implement blurred background image mode
9. **Highlighting Areas of Interest Using Saliency** - Audit our SaliencyAnalyzer against reference

### Week 4: Photo Integration & Polish
10. **Bringing Photos picker to your SwiftUI app** - Replace NSOpenPanel with PhotosPicker
11. **Segmenting and colorizing individuals** - Explore subject isolation for panels
12. **Landmarks: Extending horizontal scrolling** - Canvas preview under sidebar

---

## Key Takeaways by Feature Area

### For Image Reordering (P0 from UI review)
- Study: **Adopting drag and drop using SwiftUI**
- Pattern: `onDrag` produces `NSItemProvider`, `onDrop` receives and processes
- Alternative: SwiftUI's `onMove` modifier for list reordering (simpler than drag-and-drop)

### For Per-Panel Image Assignment (P0 from UI review)
- Study: **Bringing robust navigation structure to your SwiftUI app**
- Pattern: Selection-driven detail panel with explicit data bindings
- Implementation: Picker or thumbnail grid in `PanelCropEditor`

### For Commands/Menus (P0 from UI review)
- Study: **Building a great Mac app with SwiftUI**
- Pattern: `.commands` modifier with `CommandGroup` and `CommandMenu`
- Implementation: File menu (Add Images, Export, Clear), Layout menu (style switcher)

### For Background Image Support (P1 from UI review)
- Study: **Blurring an image** (Accelerate) + **Calculating dominant colors** (Accelerate)
- Pattern: vImage convolution for blur, histogram for color extraction
- Implementation: SegmentControl for background type, conditional controls

### For Photos Integration (P1 from UI review)
- Study: **Bringing Photos picker to your SwiftUI app**
- Pattern: `PhotosPicker` with `.photoSelection` binding
- Implementation: Replace `NSOpenPanel` browse button with `PhotosPicker`

### For `@Observable` Migration (P3 from UI review)
- Study: **Migrating from Observable Object to Observable macro** + **Managing model data**
- Pattern: `@Observable` class, `@State` in views, remove `@Published`
- Implementation: Straightforward migration of `CollageViewModel`
