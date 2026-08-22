# Fix Saliency Face Centering and Add Diagnostic Tooling

## Problem

When loading images with human faces, the face does not end up centered in the cropped panel as expected. The saliency feature is supposed to use Vision's face detection (`VNDetectFaceRectanglesRequest`) with boosted confidence (floor 0.9) to center crops on faces, but the result is misaligned.

## Unknowns

We cannot yet determine whether the bug is in:
1. **Vision API accuracy** — is the face bounding box correct?
2. **Coordinate conversion** — is the Vision-to-CG transform wrong?
3. **Portrait swap** — is the x/y swap in `SaliencyResult.cropOrigin` over-correcting?
4. **Crop application** — is the `sourceRect` being read incorrectly during rendering?

## Root Cause Candidates

### Portrait Swap in `SaliencyResult.cropOrigin` (`Models/SaliencyResult.swift:26-29`)
The method swaps x/y for portrait images, citing `VNImageRequestHandler` buffer rotation. But the analyzer passes `orientation: .up` which should handle orientation correctly. This swap may be an over-correction that misplaces the crop center on portrait photos (the most common orientation for portraits/faces).

### Duplicate Coordinate Conversion Logic
`SaliencyAnalyzer` does its own inline Vision-to-CG conversion (`SaliencyAnalyzer.swift:56-57`), while `CropManager` has unused utility methods (`visionToCG`, `applyPortraitSwap`, `visionToCGWithPortrait` at `CropManager.swift:648-687`) that were presumably written to address the same problem. The duplication suggests the conversion logic was refactored but not consolidated, leaving room for inconsistency.

### Learnings File Confirms Coordinate History
`_agent_docs/learnings/verify-data-flow-before-coordinate-conversion.md` documents a previous bug where `SaliencyResult.center` was mischaracterized as "normalized" when it was already in pixel coordinates, causing crops to clamp to image edges. This area has a history of coordinate space confusion.

## Proposed Approach

### Phase 1: Diagnostic Tooling (Verify Before Fixing)

Add a debug visualization so we can see what Vision is detecting and where the crop lands:

1. **Saliency debug overlay** — Add a toggle (e.g., in a debug menu or via `#if DEBUG`) that draws on the canvas:
   - A crosshair or circle at the `SaliencyResult.center` point, mapped into the panel's visible region
   - A circle for the `SaliencyResult.radius`
   - The `sourceRect` outline in a distinct color
   - This requires mapping `SaliencyResult.center` (CG pixel space) through the crop/fit chain into the SwiftUI preview coordinate space. The `CoordinateConverter.sourceRectInContainer` method (`CropManager.swift`) already does part of this mapping.

2. **Structured logging** — Enhance `SaliencyAnalyzer` to log per-image diagnostics:
   - Number of faces detected, their bounding boxes (Vision normalized) and converted CG points
   - Number of salient objects, their bounding boxes and confidences
   - The computed weighted centroid and final `SaliencyResult`
   - The `cropOrigin` computed by `SaliencyResult.cropOrigin` for each panel
   - Use existing `logger` and `perfLogger` with the `austin183.indie.CollageMaker` subsystem

3. **Heat map visualization** — Optionally render the saliency heat map from `VNGenerateAttentionBasedSaliencyImageRequest` as a semi-transparent overlay. The request produces a `CGImage` via `saliencyRequest.results?.first.cnImage` which can be converted and drawn. This directly shows what Vision considers "important" in the image.

### Phase 2: Test with Real Images

The existing tests (`SaliencyAnalyzerTests.swift`) use `createTestCGImage` which produces solid-color images — these will never trigger face detection or meaningful saliency. To properly test:

1. **Add test fixture images** — Add a small set of known test images to `CollageMakerTests/Resources/`:
   - One landscape photo with a clearly visible face
   - One portrait photo with a clearly visible face
   - One image with multiple faces
   - One image with no faces (to test saliency-only path)

2. **Add accuracy tests** — Write tests that:
   - Run `SaliencyAnalyzer.analyze` on each fixture
   - Assert that the `center` point falls within a tolerance region around the expected face location
   - Assert that face detection returned at least one result
   - Verify the `cropOrigin` for a given panel size centers on the face
   - These tests would be `@Suite(.serialized)` like the existing tests, and could be `#if DEBUG` gated since they depend on Vision's accuracy

3. **Add portrait swap tests** — Write a focused test that:
   - Creates a synthetic saliency result with a known center (e.g., top-right quadrant)
   - Calls `cropOrigin` with a portrait `imageSize`
   - Verifies the x/y swap produces the expected origin
   - Repeat with a landscape `imageSize` to confirm no swap occurs

### Phase 3: Fix the Bug

Once diagnostics reveal whether the issue is the portrait swap, the coordinate conversion, or something else, apply the targeted fix. Most likely candidates:

- **If portrait swap is the culprit**: Remove or condition the swap in `SaliencyResult.cropOrigin`. The `orientation: .up` parameter should already tell Vision how to interpret the pixel buffer. Verify by checking whether `VNImageRequestHandler` actually rotates the buffer when `orientation` matches the image's natural orientation.

- **If coordinate conversion is wrong**: Consolidate the inline conversion in `SaliencyAnalyzer` with the `CropManager` utility methods, ensuring a single source of truth.

- **If both are issues**: Audit the full chain: Vision bounding box → normalized CG point → pixel CG point → portrait swap → crop origin → clamped origin → rendered sourceRect.

## Files Involved

| File | Role |
|------|------|
| `Models/SaliencyResult.swift` | `cropOrigin` with portrait swap logic |
| `Services/SaliencyAnalyzer.swift` | Vision API calls, coordinate conversion |
| `ViewModel/CropManager.swift` | `computeCropsFromSaliency`, unused coord utilities |
| `ViewModel/ImageCoordinator.swift` | Triggers saliency analysis, wires results to crops |
| `Services/PanelRenderer.swift` | Renders cropped panels using `sourceRect` |
| `Views/PanelCropEditor.swift` | Crop preview — candidate for debug overlay |
| `CollageMakerTests/SaliencyAnalyzerTests.swift` | Existing tests (solid-color images only) |
| `CollageMakerTests/SaliencyResultTests.swift` | Existing `cropOrigin` tests |
| `CollageMakerTests/TestHelpers.swift` | `MockSaliencyAnalyzer`, `createTestCGImage` |

## Success Criteria

- Faces in test images are visually centered within their cropped panels
- Debug overlay confirms saliency center aligns with expected face position
- Test suite includes fixture-based tests that catch regressions
- Coordinate conversion logic is consolidated with no duplication
