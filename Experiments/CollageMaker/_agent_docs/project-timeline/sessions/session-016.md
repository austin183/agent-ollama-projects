# Session 16 — 2026-05-15

### Round 4, Phase 1: Panel Editor Crop Preview

**Goal:** Replace the image picker in `PanelCropEditor` with a visual crop preview showing the panel's current image with a dim overlay highlighting the active `sourceRect` region.

**Files Modified:**
- `Views/PanelCropEditor.swift` — Removed `@State assignedImageIndex`, `@State showImagePicker`, `init`, and `effectiveIndex` binding. Removed inline `Picker` (<10 images) and popover `ImagePickerGrid` (>=10 images). Added `CropPreviewView` and `CropOverlay` subviews.

**Implementation Details:**
- `CropPreviewView` — Fixed 140px-tall container with the panel's image scaled via `.aspectRatio(contentMode: .fit)`. When `crop` exists, renders a dim overlay with a clear cutout at the `sourceRect` position.
- Dim overlay uses `Path` with two rects (full container + visible region) filled with `FillStyle(eoFill: true)` — even-odd fill rule creates a hole where the visible region is. White stroke border outlines the visible region for clarity.
- `sourceRectInContainer` — Computes `.aspectRatio(contentMode: .fit)` math to scale `sourceRect` from CGImage pixel coordinates to the SwiftUI container coordinate space.
- `displayImage` — Creates `NSImage(cgImage:size:.zero)` to strip EXIF orientation metadata, ensuring the displayed image matches the raw CGImage pixel coordinates used by `sourceRect`.

**Bugs Discovered and Fixed:**

1. **EXIF coordinate mismatch** — `Image(nsImage:)` applies EXIF orientation corrections (rotation, flip) before display, but `sourceRect` coordinates live in raw CGImage pixel space. The overlay appeared shifted or rotated relative to the image content. Fixed by creating `NSImage(cgImage: image.cgImage, size: .zero)` which strips EXIF metadata, so the displayed image matches the coordinate space of `sourceRect`.

2. **Solid overlay instead of transparent cutout** — Initial implementation used `.ultraThinMaterial` filled rectangle, rendering as a solid gray box rather than a translucent window showing the image through. Fixed by using `Path` with two rects + `FillStyle(eoFill: true)` — the even-odd fill rule punches a hole in the dim overlay.

3. **Image scaling with zoom** — The `CropPreviewView` image was scaling up as zoom decreased (below 100%), making the preview unstable. Fixed by using a fixed 140px container with `.aspectRatio(contentMode: .fit)`, so the image stays constant and only the overlay rectangle changes.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **Not yet re-run** (no test-impacting changes)
- Crop preview: **Working** (image stays fixed, overlay tracks sourceRect with clear cutout)
- Image picker removed: **Done** (panel image assignment now handled by drag-and-drop between panels)
- Missing crop handling: **Working** (shows full image with no overlay when cropMap entry is absent)

**Learnings Documented:**
- `_agent_docs/learnings/crop-preview-overlay-learnings.md`
