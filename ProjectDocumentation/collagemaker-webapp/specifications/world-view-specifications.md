# CollageMaker Web App — World View Specifications

This document captures the user-facing behaviors and workflows of the CollageMaker application, translated for a web-based perspective. The focus is on **what users can do** rather than technical implementation details.

---

## 1. Image Loading & Management

### Adding Images
- Users can load images via file picker (browse/add button) or drag-and-drop directly onto the canvas/sidebar area.
- Multiple images can be loaded at once.
- When no images are present, the canvas shows a "No Images" state with a prompt to add images.

### Image Library Sidebar
- Loaded images appear in a sidebar as a list with thumbnails and filenames.
- Each image is numbered sequentially (e.g., "#1", "#2").
- Users can search/filter images by filename using a search field at the top of the library.
- Images can be reordered via drag-and-drop within the sidebar list.
- Individual images can be removed via an "X" button or context menu ("Remove").
- A "Clear All" option is available to remove all images from the collage (with undo support).

### Image Selection
- Clicking/tapping an image in the library selects it and opens its panel editor in the detail sidebar.
- The selected image's panel can be interacted with on the main canvas.

---

## 2. Canvas & Layout

### Main Canvas
- The central area displays the collage layout as a preview canvas.
- Users can pan/scroll around the canvas to navigate when the collage exceeds the visible area.
- Pinch or scroll gestures can be used for zooming in/out on the canvas.

### Layout Styles
Users can choose from multiple layout styles:
- **Rectangular grid** — standard panel arrangement
- **Diagonal slices** — panels arranged with diagonal dividing lines (with adjustable slice angle)
- **Hexagonal** — hexagon-shaped panels (with adjustable spacing)
- Other layout patterns as defined by the app

### Layout Configuration Controls
- **Gutter/Spacing**: Adjust the gap between panels (0–20pt range for standard layouts).
- **Slice Angle**: For diagonal slice layouts, adjust the angle of the diagonal divisions (0°–75°).
- **Hex Spacing**: For hexagonal layouts, adjust the spacing between hexagons (0–30pt).

Changes to layout settings trigger a live preview regeneration.

---

## 3. Panel Editing & Cropping

### Selecting Panels
- Click/tap on a panel in the canvas to select it.
- Selected panels are highlighted with a white border.
- The detail sidebar shows the "Panel Editor" for the selected panel.

### Crop Controls (Per Panel)
Each image panel has its own crop/position controls:
- **Drag to move**: Click and drag inside the crop preview to reposition the visible area of the image within the panel.
- **Corner drag to zoom**: Drag the corners/handles of the crop region to resize the visible area proportionally.
- **Position & Size display**: The editor shows the current panel position (X, Y) and size (width x height).

### Reset Crop
- A "Reset Crop" button restores the default crop for the selected image panel.

---

## 4. Title & Text Features

### Adding/Editing Title Text
- Users can add a title to the collage via a text editor in the export/detail sidebar.
- The text editor supports rich text formatting:
  - **Bold** (B button)
  - **Italic** (I button)
  - **Underline** (ABC button)

### Title Styling Controls
- **Font Family**: Select from available system fonts or use the default system font.
- **Font Size**: Adjust size via slider (12pt–120pt).
- **Text Color**: Choose a color using a color picker/well.
- **Background Color**: Choose a background color for the title text box.
- **Title Background Toggle**: Show or hide the title background box.
- **Alignment**: Left, center, or right alignment via segmented control with icons.

### Title Interaction on Canvas
- The title appears as an overlay on the canvas.
- Users can interact with the title (drag to reposition) while live gesturing is active.

---

## 5. Background & Overlay Features

### Background Styles
Users can choose a background style for the collage:
- **Solid Color**: Pick a single background color using a color well.
- **Gradient**: Choose start and end colors, plus an angle (0°–360°) for the gradient direction.
- **Image**: Upload a background image with an opacity slider (0%–100%).

### Overlay / Double Exposure Mask
- Users can choose a "mask image" to use as an overlay effect (double exposure style).
- Mask image is displayed in the sidebar with a thumbnail.
- **Mask Opacity**: Adjust the opacity of the mask overlay (0%–100%).
- Mask images can be removed via an "X" button.

---

## 6. Export Features

### Export as JPEG
- An "Export JPEG" button is available in the detail sidebar and primary toolbar.
- The button is disabled when no images are present or when processing/export is in progress.

### Export Quality
- A quality slider allows users to adjust export quality (50%–100%).
- The current quality percentage is displayed next to the slider.

### Export Flow
- Clicking "Export JPEG" opens a save dialog (or triggers browser download).
- While exporting, the button changes to "Cancel" with a progress indicator.
- Users can cancel an in-progress export.
- After successful export, a success message is displayed briefly ("checkmark circle" icon + text), then auto-dismisses after ~3 seconds.
- If an error occurs, an error message is displayed in red text.

---

## 7. Interaction & Gesture Behaviors

### Canvas Gestures
- **Pan/Scroll**: Navigate around the canvas when content exceeds the viewport.
- **Pinch/Zoom**: Zoom in and out on the canvas (via pinch gesture or scroll).
- **Tap to Select**: Tap a panel to select it; tap empty space to deselect.

### Undo/Redo Support
- Changes to layout, crops, title text, styling, background, and mask images are tracked for undo/redo.
- Gesture-based edits (crop adjustments, title dragging) batch into single undo actions (e.g., "Adjust Crop", "Change Layout").

### Live Preview & Gesturing State
- During interactive edits (dragging crops, adjusting sliders), the app enters a "live gesturing" state.
- Preview updates are debounced to maintain responsiveness while editing.

---

## 8. Saliency Analysis Features (Vision-Based)

### Automatic Focus Crops
- The app can analyze images for visual saliency (areas of high attention/importance).
- Saliency analysis informs default crop positioning to focus on the most visually important parts of each image.

### Saliency Overlay Toggle
- Users can toggle a saliency debug overlay to visualize the saliency analysis results.
- The overlay shows a green circle indicating the focal region and a red center dot.

---

## 9. UI Layout & Navigation

### Three-Panel Layout
The app uses a navigation split view with three main areas:
1. **Left Sidebar**: Image library, layout configuration, status info.
2. **Center Canvas**: Main collage preview and editing area.
3. **Right Detail Panel**: Panel editor (for selected image), export controls, title styling, background settings.

### Collapsible Right Sidebar
- Users can collapse/expand the right detail panel via a sidebar toggle button in the toolbar.

### Toolbar Actions
- **Export Button**: Opens save dialog for exporting the collage as JPEG.
- **Add Images Button**: Opens file picker to add more images.
- **Toggle Sidebar Button**: Shows/hides the right detail panel.

---

## 10. Accessibility & A11y Considerations

From the implementation, the app includes accessibility labels and hints for:
- Image library search field
- Layout style picker and gutter/slice angle sliders
- Panel selection and crop editor controls
- Export button and quality slider
- Title text editor and styling controls
- Background and mask image selectors

These suggest that a web version should similarly support:
- Keyboard navigation for all interactive elements
- Screen reader labels for buttons, sliders, and panels
- Focus indicators for selected panels and active controls
