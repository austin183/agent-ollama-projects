# Visual Validation Automation Plan

Goal: Convert the manual visual validation walkthrough (`visual-validation-walkthrough.md`) into automated unit tests and fitness functions across five phased additions.

**Guiding principle**: Each phase is a self-contained test file or suite that can be written, reviewed, and landed independently.

---

## Phase 1 — Undo Gauntlet & Recovery

**Walkthrough coverage**: Phase 6 (Destruction & Recovery Cycle)
**Priority**: Highest — undo regressions are the hardest to catch manually.
**New test file**: `CollageViewModelUndoTests.swift`

### Tests

1. `undoMultiStepSequence` — Full gauntlet:
   - Add 3 images → change layout style → pan first image → set title → change background color → remove last image
   - Undo 5 times in reverse
   - Assert state after each undo matches the snapshot taken before that action
   - Key assertions: panel count, layout style, crop source rects, title string, background color, image count

2. `undoClearAllRestoresFullState`:
   - Build a complex collage (images, title, custom crops, background)
   - Call `clearAll()`
   - Assert everything is empty
   - Undo the clear
   - Assert all state is restored (images, panels, crops, title, background)

3. `undoAfterLayoutStyleChange`:
   - Set up collage, change style from uniform → hero
   - Assert panel frames changed
   - Undo
   - Assert panel frames match original uniform layout

4. `undoAfterGutterChange`:
   - Set up collage, change gutter 0 → 20
   - Assert panel sizes changed
   - Undo
   - Assert panel sizes match original

5. `undoAfterCropPan`:
   - Pan an image crop
   - Assert source rect changed
   - Undo
   - Assert source rect matches pre-pan value

6. `undoAfterTitleChange`:
   - Set title text
   - Undo
   - Assert title is empty again

7. `undoAfterImageRemoval`:
   - Remove an image from a populated collage
   - Assert panel count decreased
   - Undo
   - Assert image and panel count are restored

### Implementation notes
- Use `TestAssembler` with `trackCalls = true`
- Use `makeViewModel` factory from `CollageViewModelTests`
- Snapshots should be taken before each action: panel frames, crop map, title, background config, image count
- Run `@MainActor @Suite(.serialized)` to avoid concurrency issues

---

## Phase 2 — Export-Preview Consistency

**Walkthrough coverage**: Phase 7 (Export & Final Quality)
**Priority**: High — export mismatch is a silent failure that users only discover after saving.
**New test file**: `ExportConsistencyTests.swift`

### Tests

1. `exportMatchesPreviewAtFullResolution`:
   - Set up a collage with 3 images, title, gradient background
   - Render a preview at full canvas size (`SizeConstants.defaultCanvasSize`)
   - Assemble an export at quality 1.0
   - Decode export data back to an NSImage
   - Compare pixel data of preview vs export image
   - Assert they match within tolerance (JPEG quality 1.0 should be near-lossless)

2. `exportQualityAffectsFileSize`:
   - Assemble the same collage at quality 0.1 and 1.0
   - Assert quality 1.0 produces a larger file than 0.1
   - Sanity: this catches regressions where the quality parameter is ignored

3. `exportWithTitleAndBackground`:
   - Set up collage with title text and gradient background
   - Export and decode
   - Verify the output image has non-background pixels in the title region (simple pixel sampling at known coordinates)

4. `exportWithDiagonalSlicesLayout`:
   - Generate a diagonal slices layout
   - Export and verify we get valid JPEG data
   - Verify the image dimensions match canvas size

5. `exportWithHexagonalLayout`:
   - Generate a hexagonal layout
   - Export and verify valid output

### Implementation notes
- Use `CollageAssembler` directly (not the mock) for pixel-level tests
- Helper to decode `Data` → `NSImage` → `CGImage` → pixel buffer
- Pixel comparison should use a small tolerance (e.g., mean absolute error < 5 per channel) for JPEG artifacts
- Consider using `#TimeLimit` or bounding test duration since real assembly is slower

---

## Phase 3 — Large Batch Stress Tests

**Walkthrough coverage**: Phase 1 (Asset Ingestion, large batch 20+)
**Priority**: Medium — catches edge cases in layout math and memory.
**New test file**: `CollageStressTests.swift`

### Tests

1. `layoutWithThirtyImages`:
   - Create 30 images of varying sizes (mix of portrait/landscape)
   - Regenerate layout
   - Assert 30 panels are generated
   - Assert all panel IDs are unique
   - Assert all panels have valid crops

2. `layoutWithFiftyImages`:
   - Same as above with 50 images
   - Assert no nil crops or crashes

3. `layoutStyleRotationWithLargeBatch`:
   - Create 25 images
   - Cycle through all layout styles: uniform → hero → mosaic → diagonalSlices → hexagonal
   - Assert panel count stays at 25 for each style
   - Assert all panels have non-zero area

4. `gutterStressTest`:
   - Create 10 images
   - Rapidly change gutter from 0 → 50 in increments of 5
   - Assert layout regenerates without error at each step
   - Assert panel sizes monotonically decrease as gutter increases

5. `addImagesOneByOne`:
   - Start with empty collage
   - Add images one at a time up to 20
   - After each add, verify panel count == image count
   - Verify no nil crops

### Implementation notes
- Use `TestAssembler` (no real rendering) — these are logic stress tests, not rendering stress tests
- Images can be small (100x100) colored CGImages via `createTestImageItem`
- Use `#TimeLimit(.seconds(30))` on the 50-image test

---

## Phase 4 — Layout Style Round-Trip

**Walkthrough coverage**: Phase 2 (Structural Manipulation, layout rotation)
**Priority**: Medium — ensures layout transitions are reversible and consistent.
**New test file**: `LayoutRoundTripTests.swift`

### Tests

1. `roundTripAllStyles`:
   - Create 6 images
   - For each layout style, regenerate and record panel count + total canvas coverage
   - After cycling through all styles, verify panel count is always N (image count)
   - Assert no style produces 0 panels or nil crops

2. `roundTripPreservesImageOrder`:
   - Create 5 images with a custom order `[4, 2, 0, 3, 1]`
   - Cycle through all layout styles
   - After each transition, verify the effective image assignment order is preserved

3. `diagonalAngleRoundTrip`:
   - Create 4 images with diagonal slices layout
   - Set angle to 0 → 30 → 45 → 60 → 75 → back to 45
   - Assert panels are generated at each angle
   - Assert final state at 45° matches the intermediate 45° state

4. `hexagonalSpacingRoundTrip`:
   - Create 7 images with hexagonal layout
   - Change spacing: 2 → 8 → 20 → back to 8
   - Assert panels are generated at each spacing
   - Assert non-overlapping invariant holds at each step

5. `singleImageAllStyles`:
   - Create 1 image
   - Apply each layout style
   - Assert the single panel always covers the full canvas

### Implementation notes
- These are pure logic tests using `LayoutGenerator` and `LayoutManager`
- No assembler or rendering needed
- Can run non-`@MainActor` where possible for speed

---

## Phase 5 — Export Quality & Background Fitness Functions

**Walkthrough coverage**: Phase 4 (Aesthetic & Background), Phase 7 (Quality Shift)
**Priority**: Lower — these are lightweight invariants that catch subtle regressions.
**New test file**: `FitnessFunctionTests.swift`

### Tests

1. `backgroundOpacityZeroHidesBackground`:
   - Render a preview with solid red background at opacity 0
   - Sample center pixel of the background region (outside panels)
   - Assert pixel is transparent or canvas default (not red)

2. `backgroundOpacityOneShowsBackground`:
   - Render with solid blue background at opacity 1.0
   - Sample background region
   - Assert pixel is approximately blue

3. `gradientAngleChangesOutput`:
   - Render with gradient at angle 0 and 90
   - Assert the two outputs produce different pixel data

4. `exportQualityMonotonicity`:
   - Assemble at qualities: 0.1, 0.3, 0.5, 0.7, 0.9, 1.0
   - Assert file sizes are monotonically non-decreasing

5. `panelCountMatchesImageCount`:
   - For image counts 1 through 20, verify panel count always equals image count
   - This is a simple invariant that should never break

6. `noPanelOverlapsInUniformLayout`:
   - Generate uniform layouts for 2-16 images
   - Assert no two panel frames intersect (accounting for gutter)

7. `canvasCoverageInvariant`:
   - For each layout style and image count 1-10, verify that the union of all panel bounding boxes covers at least 95% of the canvas area

### Implementation notes
- Tests 1-3 use `CollageAssembler` directly for pixel sampling
- Tests 4-7 are pure logic / file size checks, no pixel comparison needed
- Canvas coverage test should compute the union of rects and compare area to canvas area

---

## Execution Order & Dependencies

| Phase | Depends on | Est. complexity |
|---|---|---|
| 1. Undo Gauntlet | None (uses existing mocks) | Medium — many assertions |
| 2. Export Consistency | None (uses real assembler) | Medium — pixel comparison helper needed |
| 3. Large Batch Stress | None | Low — straightforward loops |
| 4. Layout Round-Trip | None | Low — pure functions |
| 5. Fitness Functions | Phase 2 helper (pixel sampling) | Low — small, focused tests |

Recommended implementation order: 3 → 4 → 5 → 1 → 2. Start with the simplest (pure logic) to establish patterns, then build up to the integration-heavy undo gauntlet and pixel-level export consistency.
