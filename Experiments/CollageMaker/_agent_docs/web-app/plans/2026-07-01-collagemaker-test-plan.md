# CollageMaker Web Port — Pre-Phase 3 Test Plan

**Date:** 2026-07-01
**Scope:** Tests for all changes from Sessions 3 (Phase 1: Foundation & Core Rendering) and 4 (Phase 2: Panel Editing & Crop Controls)
**Prerequisite:** This plan must be executed before Phase 3 begins to ensure a stable foundation.
**References:** [Implementation Plan](./2026-06-30-collagemaker-web-port-implementation.md), [Session 003 Summary](../project-timeline/sessions/session-003-summary.json), [Session 004 Summary](../project-timeline/sessions/session-004-summary.json)

---

## Test Infrastructure

### Unit Tests
- **Framework:** Mocha + Chai loaded via CDN
- **Execution:** In-browser via `CollageMaker/test/unit-tests.html`
- **Pattern:** Follows `MidiSongBuilder/test/` convention

### E2E / UI Tests
- **Framework:** Playwright (existing repo dependency)
- **Execution:** `CollageMaker/test/e2e/` directory, against `http://localhost:8000`
- **Prerequisite:** Dev server running via `start-server.sh`

---

## Section 1: Layout Math — Pure Function Unit Tests

All layout modules are pure functions with no side effects. These are the highest-value unit tests as they can be validated in complete isolation.

### 1.1 FitMath
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | `fit()` — landscape image in portrait container | source: 1920x1080, container: 400x600 | fitted height = 600, width fits proportionally, centered offset |
| 1.1.2 | `fit()` — portrait image in landscape container | source: 1080x1920, container: 1920x1080 | fitted width = 607.5, height = 1080, centered offset |
| 1.1.3 | `fit()` — square image in rectangular container | source: 1000x1000, container: 1920x1080 | fitted = 1080x1080, offset.x = 420 |
| 1.1.4 | `fit()` — equal aspect ratios | source: 1920x1080, container: 960x540 | fitted = 960x540, offset = {0, 0} |
| 1.1.5 | `fit()` — zero-height source | source: 100x0 | returns zeros, no division-by-zero error |
| 1.1.6 | `fit()` — NaN/Infinity dimensions | source: NaN x 100 | returns zeros, no error |
| 1.1.7 | `sourceRect()` — landscape image, portrait panel | image: 4000x3000, panel: 200x400 | sourceRect centered, preserves panel aspect ratio |
| 1.1.8 | `sourceRect()` — portrait image, landscape panel | image: 1080x1920, panel: 1920x1080 | sourceRect width = image width, height cropped proportionally |
| 1.1.9 | `sourceRect()` — square image, square panel | image: 2000x2000, panel: 500x500 | sourceRect = {x:0, y:0, w:2000, h:2000} (full image) |
| 1.1.10 | `sourceRect()` — extreme aspect ratio (21:9 panoramic) | image: 3780x1800, panel: 500x500 | sourceRect width = 1800, centered |
| 1.1.11 | `sourceRect()` — extreme aspect ratio (9:21 vertical) | image: 1080x2520, panel: 500x500 | sourceRect height = 1080, centered |
| 1.1.12 | `sourceRect()` — zero-height image | image: 100x0 | returns zeros, no error |

### 1.2 SeededPRNG
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.1 | Deterministic sequence — same seed produces same values | seed: 42, call next() 10 times | All 10 values identical across two instances |
| 1.2.2 | Different seeds produce different sequences | seed: 1 vs seed: 2 | First value differs |
| 1.2.3 | Values are 32-bit unsigned integers | seed: 0 | All values in range [0, 2^32-1] |
| 1.2.4 | Seed normalization — negative seed | seed: -1 | State normalized to unsigned (>>> 0) |
| 1.2.5 | Seed normalization — large seed | seed: 2^33 | Truncated to 32-bit |
| 1.2.6 | No zero-stuck state | seed: 0 | Multiple next() calls produce non-zero values |

### 1.3 PolygonClipper
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.3.1 | Clip rectangle fully inside clip rect | subject: 10x10 rect at (5,5), clip: 0,0,20,20 | Returns 4 points unchanged |
| 1.3.2 | Clip rectangle partially outside (top-left) | subject: 10x10 rect at (-5,-5), clip: 0,0,20,20 | Returns clipped polygon with intersection points |
| 1.3.3 | Clip rectangle fully outside | subject: 10x10 rect at (30,30), clip: 0,0,20,20 | Returns empty array |
| 1.3.4 | Clip parallelogram (diagonal slice shape) | 4-point parallelogram extending beyond clip rect | Returns valid clipped polygon |
| 1.3.5 | Clip hexagon | 6-point hexagon | Returns valid clipped polygon |
| 1.3.6 | Empty subject polygon | subject: [] | Returns empty array |
| 1.3.7 | Clip rect with zero width | clip: {x:0, y:0, width:0, height:100} | Handles gracefully, no error |

### 1.4 UniformLayout
| # | Test | numImages | Expected |
|---|------|-----------|----------|
| 1.4.1 | Zero images | 0 | Returns empty array |
| 1.4.2 | Single image | 1 | 1 panel, full canvas (1x1 grid) |
| 1.4.3 | Two images | 2 | 2 panels, 2x1 grid |
| 1.4.4 | Three images | 3 | 3 panels, 3x1 grid |
| 1.4.5 | Four images | 4 | 4 panels, 3x2 grid (3 cols max) |
| 1.4.6 | Nine images | 9 | 9 panels, 3x3 grid |
| 1.4.7 | Ten images | 10 | 10 panels, 3x4 grid |
| 1.4.8 | Twenty images | 20 | 20 panels, 3x7 grid |
| 1.4.9 | Panels fill canvas — no gaps | 6 images, gutter: 0 | Union of panel rects covers full canvas |
| 1.4.10 | Panels with gutter — spacing correct | 4 images, gutter: 10 | Gap between adjacent panels = 10px |
| 1.4.11 | Panels don't overlap | 10 images, gutter: 5 | No two panel rects intersect |
| 1.4.12 | Custom imageOrder respected | imageOrder: [2, 0, 1] | Panel 0 gets image 2, panel 1 gets image 0, panel 2 gets image 1 |
| 1.4.13 | Panel IDs are unique | 10 images | All panel.id values distinct |
| 1.4.14 | Panel geometry type | any count | All panels have `geometry.type === 'rect'` |

### 1.5 HeroLayout
| # | Test | numImages | Expected |
|---|------|-----------|----------|
| 1.5.1 | Zero images | 0 | Returns empty array |
| 1.5.2 | Single image | 1 | Falls back to UniformLayout — full canvas |
| 1.5.3 | Two images | 2 | Hero panel on left (half canvas), 1 side panel on right |
| 1.5.4 | Three images | 3 | Hero + 2 side panels (1 column) |
| 1.5.5 | Five images | 5 | Hero + 4 side panels (2 columns) |
| 1.5.6 | Hero panel dimensions | 3 images | Hero width = canvasWidth/2 - gutter/2, height = full canvas |
| 1.5.7 | Side panels don't overlap | 10 images | No two side panel rects intersect |
| 1.5.8 | Hero panel doesn't overlap side panels | 5 images | Hero rect and all side rects non-overlapping |
| 1.5.9 | Custom imageOrder | imageOrder: [4, 0, 1, 2, 3] | Hero gets image 4, sides get 0-3 |

### 1.6 MosaicLayout
| # | Test | numImages | Expected |
|---|------|-----------|----------|
| 1.6.1 | Zero images | 0 | Returns empty array |
| 1.6.2 | Single image | 1 | Full canvas panel |
| 1.6.3 | Two images | 2 | Two panels, no overlap |
| 1.6.4 | Five images | 5 | 5 panels |
| 1.6.5 | Twenty images | 20 | 20 panels (no truncation at 21) |
| 1.6.6 | Fifty images | 50 | 50 panels |
| 1.6.7 | Deterministic with seed | seed: 42, 10 images | Same panel geometries across runs |
| 1.6.8 | Different seeds produce different layouts | seed: 1 vs seed: 2, 10 images | Panel geometries differ |
| 1.6.9 | Panels don't overlap | 15 images | No two panel rects intersect |
| 1.6.10 | Panels stay within canvas | 10 images | All panel rects within [0,0] to [canvasW, canvasH] |
| 1.6.11 | Last panel fills remaining space | 5 images | Last panel occupies remaining rect exactly |

### 1.7 DiagonalSlicesLayout
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.7.1 | Zero images | 0 | Returns empty array |
| 1.7.2 | Single image | 1 | Full canvas as path geometry (rectangle) |
| 1.7.3 | Two images | 2 | 2 parallelogram panels |
| 1.7.4 | Five images | 5 | 5 parallelogram panels |
| 1.7.5 | Panel geometry type | any count | All panels have `geometry.type === 'path'` |
| 1.7.6 | Default angle (45°) | 5 images, angle: 45 | Parallelograms with 45° shear |
| 1.7.7 | Zero angle | 5 images, angle: 0 | Parallelograms become rectangles (no shear) |
| 1.7.8 | Maximum angle (75°) | 5 images, angle: 75 | Valid parallelograms, no NaN coordinates |
| 1.7.9 | Bounding rects are valid | 5 images | Each panel's boundingRect contains all 4 path points |
| 1.7.10 | Custom imageOrder | [3, 1, 2, 0] | Panel image indices match order |

### 1.8 HexagonalLayout
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.8.1 | Zero images | 0 | Returns empty array |
| 1.8.2 | Single image | 1 | Full canvas as path geometry |
| 1.8.3 | Two images | 2 | 2 hexagon panels |
| 1.8.4 | Seven images | 7 | Center hex + 6 ring hexagons |
| 1.8.5 | Fifteen images | 15 | Center + ring 1 (6) + ring 2 (8 of 12) |
| 1.8.6 | Panel geometry type | any count | All panels have `geometry.type === 'path'` |
| 1.8.7 | Hexagon has 6 vertices | any count | Each panel.geometry.points has length 6 |
| 1.8.8 | Center hex is at canvas center | 7 images | First panel center ≈ {x: 960, y: 540} |
| 1.8.9 | Bounding rects valid | 10 images | Each boundingRect contains all 6 path points |
| 1.8.10 | Spacing parameter affects size | spacing: 0 vs spacing: 20 | Hex radius differs |

### 1.9 LayoutGenerator Dispatch
| # | Test | style | Expected |
|---|------|------|----------|
| 1.9.1 | Dispatches to UniformLayout | 'uniform' | Panel count and geometry match UniformLayout |
| 1.9.2 | Dispatches to HeroLayout | 'hero' | Panel count and geometry match HeroLayout |
| 1.9.3 | Dispatches to MosaicLayout | 'mosaic' | Panel count and geometry match MosaicLayout |
| 1.9.4 | Dispatches to DiagonalSlicesLayout | 'diagonalSlices' | Panel count and geometry match DiagonalSlicesLayout |
| 1.9.5 | Dispatches to HexagonalLayout | 'hexagonal' | Panel count and geometry match HexagonalLayout |
| 1.9.6 | Default style (unknown) | 'unknown' | Falls back to HeroLayout |
| 1.9.7 | Default style (undefined) | undefined | Falls back to HeroLayout |
| 1.9.8 | Default canvas size | no canvasSize | Uses 1920x1080 |
| 1.9.9 | Default gutter | no gutter | Uses 4 |

### 1.10 LayoutStyle Model
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.10.1 | migrateLayoutStyle — valid value | 'hero' | Returns 'hero' |
| 1.10.2 | migrateLayoutStyle — null | null | Returns 'hero' |
| 1.10.3 | migrateLayoutStyle — legacy doubleExposure | 'doubleExposure' | Returns 'uniform' |
| 1.10.4 | migrateLayoutStyle — invalid string | 'stars' | Returns 'hero' |
| 1.10.5 | LAYOUT_STYLE_OPTIONS length | — | Length = 5 |

---

## Section 2: Data Model Unit Tests

### 2.1 PanelGeometry
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.1.1 | createRectGeometry | {x:10, y:20, w:100, h:200} | type='rect', rect matches input |
| 2.1.2 | createPathGeometry | 4 points + boundingRect | type='path', points deep-copied, boundingRect matches |
| 2.1.3 | geometryBoundingRect — rect | rect geometry | Returns geometry.rect |
| 2.1.4 | geometryBoundingRect — path | path geometry | Returns geometry.boundingRect |
| 2.1.5 | isRectGeometry — rect | rect geometry | Returns true |
| 2.1.6 | isRectGeometry — path | path geometry | Returns false |
| 2.1.7 | Points are deep-copied | path with mutable array | Mutating input array doesn't affect geometry |

### 2.2 CropInfo
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.2.1 | createCropInfo | valid panelId, sourceRect, destination | All fields present, sourceRect deep-copied |
| 2.2.2 | createDefaultCrop | image: 4000x3000, panel: 500x500 | sourceRect from FitMath.sourceRect, destination from panel bounds |
| 2.2.3 | cloneCropInfo | existing crop | New object, same values, mutations to clone don't affect original |

### 2.3 ImageItem
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.3.1 | createImageItem — unique ID | two items created | IDs are different |
| 2.3.2 | createImageItem — fields | image, filename, dimensions | All fields present |
| 2.3.3 | generateThumbnail — landscape image | 800x600 image | Thumbnail width = 64, height = 48 |
| 2.3.4 | generateThumbnail — portrait image | 600x800 image | Thumbnail height = 48, width = 64 |
| 2.3.5 | generateThumbnail — returns data URL | any image | String starts with 'data:image/jpeg' |

### 2.4 ImagePanel
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.4.1 | createImagePanel — unique ID | two panels created | IDs are different |
| 2.4.2 | createImagePanel — fields | imageIndex: 3, geometry: rect | All fields present |

### 2.5 SizeConstants
| # | Test | Expected |
|---|------|----------|
| 2.5.1 | defaultCanvasWidth | 1920 |
| 2.5.2 | defaultCanvasHeight | 1080 |
| 2.5.3 | defaultPreviewWidth | 960 |
| 2.5.4 | defaultPreviewHeight | 540 |
| 2.5.5 | canvasAspect | 16/9 = 1.777... |
| 2.5.6 | canvasToPreviewScale | 0.5 |

---

## Section 3: State Manager Unit Tests

### 3.1 UndoManager
| # | Test | Expected |
|---|------|----------|
| 3.1.1 | Initial state — canUndo | false |
| 3.1.2 | Initial state — canRedo | false |
| 3.1.3 | Push one command, canUndo | true |
| 3.1.4 | Undo one command | Returns true, state reverted |
| 3.1.5 | Undo empty stack | Returns false |
| 3.1.6 | Redo after undo | Returns true, state restored |
| 3.1.7 | Redo empty stack | Returns false |
| 3.1.8 | New push clears redo stack | After undo, push new -> canRedo = false |
| 3.1.9 | Max 60 undo levels | Push 65 commands -> getUndoCount() = 60 |
| 3.1.10 | Oldest commands dropped first | Push 65, undo all -> executes most recent 60 |
| 3.1.11 | beginBatch + endBatch groups changes | One undo reverts entire batch |
| 3.1.12 | Batch undo captures pre-state | Undo restores state before batch started |
| 3.1.13 | Batch redo captures post-state | Redo re-applies batch changes |
| 3.1.14 | Nested batch guard | beginBatch without endBatch, then endBatch -> no crash |
| 3.1.15 | Clear removes all history | clear() -> canUndo = false, canRedo = false |
| 3.1.16 | getUndoCount accuracy | Push 3 -> count = 3 |
| 3.1.17 | getRedoCount accuracy | Push 3, undo 2 -> redoCount = 2 |
| 3.1.18 | Command label preserved | Push with label -> accessible for UI |
| 3.1.19 | Redo doesn't corrupt history | Undo, redo, undo -> still works |
| 3.1.20 | Multiple undo/redo cycles | 10 undo/redo alternations -> state correct each time |

### 3.2 CropManager
| # | Test | Expected |
|---|------|----------|
| 3.2.1 | adjustCrop — pan within bounds | Delta keeps crop inside image | sourceRect updated, clamped to [0, imageW - cropW] |
| 3.2.2 | adjustCrop — pan beyond left edge | Delta would make x < 0 | x clamped to 0 |
| 3.2.3 | adjustCrop — pan beyond right edge | Delta would make x + w > imageW | x clamped to imageW - w |
| 3.2.4 | adjustCrop — pan beyond top edge | Delta would make y < 0 | y clamped to 0 |
| 3.2.5 | adjustCrop — pan beyond bottom edge | Delta would make y + h > imageH | y clamped to imageH - h |
| 3.2.6 | adjustCrop — no crop for panel | panelId not in crops Map | No-op, no error |
| 3.2.7 | adjustCrop — no image for panel | panelAssignments missing | No-op, no error |
| 3.2.8 | zoomCrop — zoom in (factor > 1) | factor: 1.2 | sourceRect shrinks, center preserved |
| 3.2.9 | zoomCrop — zoom out (factor < 1) | factor: 0.8 | sourceRect grows, center preserved |
| 3.2.10 | zoomCrop — can't exceed image size | factor: 0.01 (huge zoom out) | sourceRect clamped to image dimensions |
| 3.2.11 | zoomCrop — minimum 1px | factor: 1000 (huge zoom in) | sourceRect min dimension = 1px |
| 3.2.12 | resetCrop — restores default | After manual adjustments | sourceRect matches FitMath.sourceRect for current panel |
| 3.2.13 | setSourceRect — clamps to bounds | x: -100, y: -100 | Clamped to valid range |
| 3.2.14 | setSourceRect — clamps dimensions | w: imageW + 100 | Clamped to imageW |
| 3.2.15 | setSourceRect — minimum 1px | w: 0, h: 0 | Clamped to 1px |
| 3.2.16 | getCrop — existing panel | Valid panelId | Returns crop object |
| 3.2.17 | getCrop — non-existing panel | Invalid panelId | Returns null |
| 3.2.18 | getPanelImage — valid panel | Valid panelId | Returns ImageItem |
| 3.2.19 | getPanelImage — invalid panel | Invalid panelId | Returns null |
| 3.2.20 | onCropChanged callback fires | Any crop mutation | Callback invoked |

### 3.3 LayoutManager
| # | Test | Expected |
|---|------|----------|
| 3.3.1 | regenerate — zero images | state.images = [] | panels = [], crops = empty Map, panelAssignments = empty Map |
| 3.3.2 | regenerate — with images | 5 images | panels generated, crops computed, assignments built |
| 3.3.3 | regenerate — increments layoutVersion | Before/after | layoutVersion increases by 1 |
| 3.3.4 | setLayoutStyle — triggers regenerate | Change from 'hero' to 'uniform' | New panels match UniformLayout |
| 3.3.5 | setGutter — triggers regenerate | Change gutter to 10 | Panels regenerated with new spacing |
| 3.3.6 | setSliceAngle — only regenerates for diagonalSlices | Style = 'hero', change angle | No regeneration |
| 3.3.7 | setSliceAngle — regenerates for diagonalSlices | Style = 'diagonalSlices', change angle | Panels regenerated |
| 3.3.8 | setHexSpacing — only regenerates for hexagonal | Style = 'hero', change spacing | No regeneration |
| 3.3.9 | setHexSpacing — regenerates for hexagonal | Style = 'hexagonal', change spacing | Panels regenerated |
| 3.3.10 | Panel assignments match image order | 5 images | Each panel assigned correct image index |

### 3.4 ImageLibrary
| # | Test | Expected |
|---|------|----------|
| 3.4.1 | addImages — filters non-image files | File with type 'text/plain' | File rejected, not added |
| 3.4.2 | addImages — adds valid image files | JPEG, PNG files | Files loaded and added to state.images |
| 3.4.3 | addImages — handles load failure | Corrupted image file | Failed image skipped, console.warn logged, valid images still added |
| 3.4.4 | addImages — all fail | 3 corrupted files | Nothing added, no crash |
| 3.4.5 | removeImage — valid index | Index 2 of 5 | Image removed, 4 remain, indices shift |
| 3.4.6 | removeImage — negative index | Index -1 | No-op |
| 3.4.7 | removeImage — out of range | Index 10 of 5 | No-op |
| 3.4.8 | clearAll | 5 images | state.images = [] |
| 3.4.9 | onImagesChanged callback fires | Any mutation | Callback invoked |

### 3.5 SaliencyFallback
| # | Test | Expected |
|---|------|----------|
| 3.5.1 | defaultCenterCrop | image: 4000x3000, panel: 500x500 | Same result as FitMath.sourceRect |
| 3.5.2 | saliencyCrop — ignores focusPoint | Any focusPoint | Same result as defaultCenterCrop |

---

## Section 4: Rendering Unit Tests

### 4.1 CanvasRenderer
| # | Test | Expected |
|---|------|----------|
| 4.1.1 | init — canvas found | Valid canvasId | Returns true, ctx set |
| 4.1.2 | init — canvas not found | Invalid canvasId | Returns false, console.error logged |
| 4.1.3 | resize — sets dimensions | width: 960, height: 540 | canvas.width/height set with DPR scaling |
| 4.1.4 | resize — DPR handling | DPR = 2 | Internal canvas = 1920x1080, CSS = 960x540 |
| 4.1.5 | scheduleRender — batches multiple calls | 5 scheduleRender calls in same frame | Only 1 render executes |
| 4.1.6 | scheduleRender — executes drawFn | Custom drawFn | drawFn called with ctx, width, height |
| 4.1.7 | render — clears canvas | Pre-existing content | Canvas cleared before drawFn |
| 4.1.8 | render — white background | No drawFn | Canvas filled white |
| 4.1.9 | dispose — cancels pending | Pending render scheduled | raf cancelled, no render fires |
| 4.1.10 | dispose — nulls references | After dispose | getCanvas() = null, getContext() = null |
| 4.1.11 | cancelPending | Pending render | Render cancelled |

### 4.2 PanelRenderer
| # | Test | Expected |
|---|------|----------|
| 4.2.1 | drawPanels — rect geometry | Rect panel, valid image/crop | Image drawn within rect clip |
| 4.2.2 | drawPanels — path geometry | Path panel, valid image/crop | Image drawn within path clip |
| 4.2.3 | drawPanels — skips missing image | imageIndex >= images.length | No draw call, no error |
| 4.2.4 | drawPanels — skips missing crop | panelId not in crops | No draw call, no error |
| 4.2.5 | drawPanels — skips unloaded image | imageItem.image = null | No draw call, no error |
| 4.2.6 | drawSelectionBorder — rect | Rect panel | White stroke rect with shadow |
| 4.2.7 | drawSelectionBorder — path | Path panel | White stroke path with shadow |
| 4.2.8 | drawHoverBorder | Any panel | Blue semi-transparent stroke |
| 4.2.9 | _drawImage — clamps source rect | sourceRect extends beyond image | Clamped, no error, offset applied |
| 4.2.10 | _drawImage — zero clamped dimensions | sourceRect fully outside image | Early return, no draw |

### 4.3 CollageAssembler
| # | Test | Expected |
|---|------|----------|
| 4.3.1 | render — background color hex | backgroundColor: '#ff0000' | Canvas filled red |
| 4.3.2 | render — background color RGB object | backgroundColor: {r:0, g:255, b:0} | Canvas filled green |
| 4.3.3 | render — background color null | backgroundColor: null | Canvas filled white (default) |
| 4.3.4 | render — panels drawn | 3 panels, images, crops | All 3 panels rendered |
| 4.3.5 | render — selection highlight | selectedPanelId set | Selection border drawn on correct panel |
| 4.3.6 | render — hover highlight | hoveredPanelId set, not selected | Hover border drawn |
| 4.3.7 | render — selection over hover | Both selected and hovered (different) | Selection drawn on top of hover |
| 4.3.8 | computeDefaultCrops | 5 panels, 5 images | Map with 5 entries, each with valid sourceRect |
| 4.3.9 | computeDefaultCrops — skips missing images | 5 panels, 3 images | Map with 3 entries |

---

## Section 5: Interaction Unit Tests

### 5.1 GestureHandler
| # | Test | Expected |
|---|------|----------|
| 5.1.1 | hitTestPanel — rect panel center | Point at panel center | Returns panel ID |
| 5.1.2 | hitTestPanel — rect panel outside | Point outside panel | Returns null |
| 5.1.3 | hitTestPanel — rect panel edge | Point on panel edge | Returns panel ID (inclusive) |
| 5.1.4 | hitTestPanel — polygon panel center | Point inside parallelogram | Returns panel ID |
| 5.1.5 | hitTestPanel — polygon panel outside | Point outside parallelogram | Returns null |
| 5.1.6 | hitTestPanel — multiple panels, overlap | Overlapping panels | Returns top-most (last in array) |
| 5.1.7 | hitTestPanel — no panels | Empty panels array | Returns null |
| 5.1.8 | hitTestPanel — letterbox scaling | Canvas CSS < logical canvas | Coordinates scaled correctly |
| 5.1.9 | _pointInPolygon — convex polygon | Point inside convex polygon | Returns true |
| 5.1.10 | _pointInPolygon — point on edge | Point on polygon edge | Handles correctly |
| 5.1.11 | _pointInPolygon — fewer than 3 points | 2-point "polygon" | Returns false |
| 5.1.12 | _pointInPolygon — null points | null | Returns false |
| 5.1.13 | screenToCanvas — coordinate conversion | Known clientX/Y | Correct canvas-relative coords |
| 5.1.14 | attach/detach — idempotent | attach() twice | Handler attached only once |
| 5.1.15 | attach/detach — cleanup | attach(), detach() | Event listeners removed |

### 5.2 CropInteraction
| # | Test | Expected |
|---|------|----------|
| 5.2.1 | hitTestCorner — on corner handle | Cursor on BR corner | Returns 'br' |
| 5.2.2 | hitTestCorner — between corners | Cursor between handles | Returns null |
| 5.2.3 | hitTestCorner — no crop | No crop for panel | Returns null |
| 5.2.4 | screenToImageCoords — conversion | Known screen position | Correct image-space coords |
| 5.2.5 | setPanelId — updates target | New panelId | Detaches old, attaches new |
| 5.2.6 | setPanelId — null clears | null | Detaches handler |
| 5.2.7 | Corner cursor styles | Each corner | Correct CSS cursor value |

### 5.3 FileDropHandler
| # | Test | Expected |
|---|------|----------|
| 5.3.1 | filterImageFiles — mixed types | JPEG + PNG + TXT | Returns only JPEG + PNG |
| 5.3.2 | filterImageFiles — all images | 3 image files | Returns all 3 |
| 5.3.3 | filterImageFiles — no images | 3 text files | Returns empty array |
| 5.3.4 | filterImageFiles — empty input | Empty FileList | Returns empty array |
| 5.3.5 | setupGlobalDrop — dragenter adds class | Drag enter event | body gets 'drag-over' class |
| 5.3.6 | setupGlobalDrop — dragleave removes class | Matching dragleave | body loses 'drag-over' class |
| 5.3.7 | setupGlobalDrop — counter prevents premature remove | Nested dragenter/dragleave | Class only removed when counter = 0 |

---

## Section 6: Integration Tests

### 6.1 Layout + Crop Pipeline
| # | Test | Expected |
|---|------|----------|
| 6.1.1 | Full pipeline — 5 images, hero layout | LayoutGenerator.generate + assembler.computeDefaultCrops | 5 panels, 5 crops, all sourceRects valid |
| 6.1.2 | Full pipeline — 10 images, mosaic layout | Same | 10 panels, 10 crops |
| 6.1.3 | Full pipeline — 5 images, diagonal slices | Path geometries, crops valid | All crops have valid sourceRects for path panels |
| 6.1.4 | Layout change resets all crops | Regenerate after layout change | All crops reset to defaults (LayoutManager.regenerate replaces crops Map) |
| 6.1.5 | Image count change | 5 -> 3 images | 3 panels, 3 crops, assignments correct |

### 6.2 Canvas + Assembler Integration
| # | Test | Expected |
|---|------|----------|
| 6.2.1 | Renderer + assembler — full render | CanvasRenderer.scheduleRender + assembler.render | Canvas has content, no errors |
| 6.2.2 | DPR rendering | DPR = 2 | Canvas sharp, not blurry |
| 6.2.3 | Scale transform for preview | Preview canvas 960x540, logical 1920x1080 | Content scaled 0.5x, panels positioned correctly |

### 6.3 Undo + Crop Integration
| # | Test | Expected |
|---|------|----------|
| 6.3.1 | Crop adjustment + undo | Adjust crop, undo() | Crop restored to pre-adjustment state |
| 6.3.2 | Crop adjustment + undo + redo | Adjust, undo, redo | Crop restored to post-adjustment state |
| 6.3.3 | Batch crop drag + undo | Simulate drag session with beginBatch/endBatch | Single undo reverts entire drag |
| 6.3.4 | Reset crop + undo | Reset crop, undo() | Crop restored to pre-reset state |

### 6.4 ImageLibrary + Layout Integration
| # | Test | Expected |
|---|------|----------|
| 6.4.1 | Add images triggers layout | addImages(3 files) + regenerate | 3 panels generated |
| 6.4.2 | Remove image triggers layout | removeImage(1) + regenerate | Remaining panels regenerated |
| 6.4.3 | Clear all triggers layout | clearAll + regenerate | Empty panels, empty crops |

---

## Section 7: Memory Management & Leak Tests

### 7.1 Event Listener Cleanup
| # | Test | Expected |
|---|------|----------|
| 7.1.1 | GestureHandler detach removes listeners | attach(), detach() | No reference cycles remain, GC can collect |
| 7.1.2 | CropInteraction detach removes listeners | Same pattern | Cleaned up |
| 7.1.3 | CanvasRenderer dispose cancels raf | scheduleRender(), dispose() | No pending animation frame |
| 7.1.4 | Vue beforeUnmount cleanup | Simulate component unmount | keyboard handler removed, resize handler removed, gesture handler detached, crop interaction detached, renderer disposed |
| 7.1.5 | Global drop handlers — single registration | setupGlobalDrop called once | Only one set of dragenter/dragleave/dragover/drop listeners |

### 7.2 Image Memory
| # | Test | Expected |
|---|------|----------|
| 7.2.1 | Image removal releases references | removeImage(), check state.images | Removed image not in array, no reference in crops |
| 7.2.2 | Clear all releases all images | clearAll() | state.images = [], no image references held |
| 7.2.3 | Undo stack doesn't hold image references | Crop undo commands reference sourceRect data only, not ImageItem | Undo commands use coordinates, not image objects |

### 7.3 Undo Stack Bounds
| # | Test | Expected |
|---|------|----------|
| 7.3.1 | 60-level cap enforced | 100 undo pushes | Stack length = 60 |
| 7.3.2 | Redo stack cleared on new action | Undo, then new push | Redo stack = 0 |

---

## Section 8: Edge Cases & Error Handling

### 8.1 Image Loading Edge Cases
| # | Test | Expected |
|---|------|----------|
| 8.1.1 | Drop non-image files | TXT, PDF files dropped | Filtered out, no crash, no images added |
| 8.1.2 | Drop corrupted image file | Invalid JPEG data | Load fails, console.warn, other images load |
| 8.1.3 | Drop very large image (4K) | 4000x3000 image | Loads, renders correctly at preview scale |
| 8.1.4 | Drop very small image | 10x10 image | Loads, renders (may be pixelated but no crash) |
| 8.1.5 | Drop zero files | Empty FileList | No-op |
| 8.1.6 | Load images with extreme aspect ratios | 21:9 panoramic + 9:21 vertical mixed | All render correctly with proper crop rects |
| 8.1.7 | Duplicate image files | Same file dropped twice | Both loaded as separate entries |
| 8.1.8 | Mixed image formats | JPEG + PNG + WebP + GIF | All formats supported by browser load correctly |

### 8.2 Layout Edge Cases
| # | Test | Expected |
|---|------|----------|
| 8.2.1 | Zero images + layout switch | Empty library, change layout style | No crash, empty panels |
| 8.2.2 | One image + all 5 layouts | 1 image, cycle through styles | Each produces valid single panel |
| 8.2.3 | Many images (50) + mosaic | 50 images | 50 panels, no truncation |
| 8.2.4 | Rapid layout changes | 20 layout changes in 1 second | No state corruption, final layout correct |
| 8.2.5 | Gutter at maximum (20) | gutter: 20 | Panels spaced correctly, no negative dimensions |
| 8.2.6 | Gutter at zero | gutter: 0 | Panels adjacent, no gaps |
| 8.2.7 | Diagonal slices at angle 0 | angle: 0 | Panels become vertical strips |
| 8.2.8 | Diagonal slices at angle 75 | angle: 75 | Valid parallelograms, no NaN |

### 8.3 Crop Edge Cases
| # | Test | Expected |
|---|------|----------|
| 8.3.1 | Crop on panel with no assigned image | panelAssignments missing entry | No-op, no error |
| 8.3.2 | Crop after layout change | Adjust crop, switch layout | New layout uses default crops (expected behavior) |
| 8.3.3 | Crop resize to minimum | Drag corner to collapse | Minimum 10px dimension enforced |
| 8.3.4 | Crop resize — corner flip prevention | Drag past opposite edge | Clamped, no flip |
| 8.3.5 | Crop drag — pointer leaves window | Start drag, move outside browser | Pointer capture handles, no stuck state |

### 8.4 Selection Edge Cases
| # | Test | Expected |
|---|------|----------|
| 8.4.1 | Select panel, then clear all | Select panel, clearAll images | selectedPanelId should be reset to null |
| 8.4.2 | Select non-existent panel | Click on empty canvas area | selectedPanelId = null |
| 8.4.3 | Hover then leave canvas | Mouse enter panel, leave canvas | hoveredPanelId = null |
| 8.4.4 | Selection persists across layout change | Select panel, change layout | Selection may be stale — verify UI handles gracefully |

---

## Section 9: Performance Tests

### 9.1 Rendering Performance
| # | Test | Method | Threshold |
|---|------|--------|-----------|
| 9.1.1 | Render 10 panels (rect) | Measure frame time | < 16ms per frame |
| 9.1.2 | Render 30 panels (path — diagonal) | Measure frame time | < 16ms per frame |
| 9.1.3 | Render 30 panels (path — hex) | Measure frame time | < 16ms per frame |
| 9.1.4 | Rapid layout changes (10 in 1s) | Count actual renders | Debounced to ~1-2 renders |
| 9.1.5 | scheduleRender batching | 100 scheduleRender calls | 1 actual render |

### 9.2 Image Loading Performance
| # | Test | Method | Threshold |
|---|------|--------|-----------|
| 9.2.1 | Load 10 images (1MB each) | Measure total time | < 5 seconds |
| 9.2.2 | Thumbnail generation | 10 images | No main thread blocking > 100ms |

---

## Section 10: Cross-Browser Compatibility Tests

### 10.1 Canvas 2D
| # | Test | Browsers | Expected |
|---|------|----------|----------|
| 10.1.1 | Path clipping | Chrome, Firefox, Safari | All render clipped panels correctly |
| 10.1.2 | drawImage with source rect | All browsers | Cropped images render identically |
| 10.1.3 | Shadow rendering (selection border) | All browsers | Shadow appears on selection border |
| 10.1.4 | DPR scaling | Retina Mac, Windows HiDPI | Sharp rendering, no blur |

### 10.2 Pointer Events
| # | Test | Browsers | Expected |
|---|------|----------|----------|
| 10.2.1 | Pointer capture | Chrome, Firefox, Safari | Crop drag works with pointer capture |
| 10.2.2 | Pointer events vs mouse events | All browsers | Panel selection works |
| 10.2.3 | Touch input on mobile Safari | iOS Safari | Panel selection and crop interaction work |

### 10.3 Drag and Drop
| # | Test | Browsers | Expected |
|---|------|----------|----------|
| 10.3.1 | File drag-and-drop | Chrome, Firefox, Safari | Files accepted and loaded |
| 10.3.2 | Drag counter | All browsers | drag-over class managed correctly |

---

## Section 11: Keyboard & Accessibility Tests

### 11.1 Keyboard Shortcuts
| # | Test | Expected |
|---|------|----------|
| 11.1.1 | Cmd+Z (undo) | Undo executed |
| 11.1.2 | Ctrl+Z (undo — Windows/Linux) | Undo executed |
| 11.1.3 | Cmd+Shift+Z (redo) | Redo executed |
| 11.1.4 | Ctrl+Shift+Z (redo — Windows/Linux) | Redo executed |
| 11.1.5 | Cmd+Shift+z (lowercase z — redo) | Redo executed (case-insensitive key check) |
| 11.1.6 | Escape — deselect panel | Panel deselected, selection border removed |
| 11.1.7 | Escape — no panel selected | No-op, no error |
| 11.1.8 | Keyboard shortcut with focus on slider | Focus on gutter slider, Cmd+Z | Shortcut still works (not intercepted) |
| 11.1.9 | Keyboard shortcut with focus on search | Focus on search input, Cmd+Z | May conflict with browser undo — document behavior |

### 11.2 Accessibility
| # | Test | Expected |
|---|------|----------|
| 11.2.1 | Canvas has ARIA label | previewCanvas element | Has role="img" and aria-label |
| 11.2.2 | Crop preview canvas has ARIA label | cropPreviewCanvas element | Has role="img" and aria-label |
| 11.2.3 | Buttons have accessible names | All toolbar buttons | Text content or aria-label present |
| 11.2.4 | Sliders have labels | Gutter, slice angle, hex spacing sliders | Associated `<label>` elements |
| 11.2.5 | Color inputs have labels | Background color picker | Associated label |
| 11.2.6 | Tab navigation | Tab through all controls | All interactive elements reachable |
| 11.2.7 | Focus visible states | Keyboard focus | Visible focus indicator on all controls |

---

## Section 12: E2E / UI Workflow Tests (Playwright)

### 12.1 App Loading
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.1.1 | Page loads without errors | Navigate to index.html | No console errors, Vue app mounted |
| 12.1.2 | Toolbar visible | Page load | Title, Add Images, Undo/Redo, Clear All buttons present |
| 12.1.3 | Empty state | Page load | "No images yet" in sidebar, "No Images Loaded" on canvas |
| 12.1.4 | Theme toggle | Click theme button | Theme switches, icon updates |

### 12.2 Image Loading
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.2.1 | Add images via button | Click "Add Images", select 3 files | 3 thumbnails in sidebar, collage on canvas |
| 12.2.2 | Add images via drag-and-drop | Drag 3 files onto canvas | 3 thumbnails in sidebar, collage on canvas |
| 12.2.3 | Drag-and-drop visual feedback | Drag files over page | Canvas shows dashed outline |
| 12.2.4 | Non-image files rejected | Drop TXT file | No images added, no crash |
| 12.2.5 | Mixed files | Drop 2 images + 1 TXT | Only 2 images added |

### 12.3 Layout
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.3.1 | Default layout is Hero | Load 3 images | Hero layout displayed |
| 12.3.2 | Switch to Uniform | Select "Uniform" from dropdown | Grid layout displayed |
| 12.3.3 | Switch to Mosaic | Select "Mosaic" | Mosaic layout displayed |
| 12.3.4 | Switch to Diagonal Slices | Select "Diagonal Slices" | Diagonal layout, angle slider visible |
| 12.3.5 | Switch to Hexagonal | Select "Hexagonal" | Hex layout, spacing slider visible |
| 12.3.6 | Cycle through all layouts | Select each of 5 styles | Canvas updates for each, no errors |
| 12.3.7 | Gutter adjustment | Drag gutter slider | Panel spacing changes in real-time |
| 12.3.8 | Slice angle adjustment | Drag angle slider (diagonal mode) | Panel angles change |
| 12.3.9 | Hex spacing adjustment | Drag spacing slider (hex mode) | Hex spacing changes |
| 12.3.10 | Slider visibility | Switch between layouts | Angle slider only in diagonal, spacing only in hex |

### 12.4 Panel Selection
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.4.1 | Click panel to select | Click on canvas panel | White selection border, crop preview appears |
| 12.4.2 | Click empty area to deselect | Click on canvas background | Selection border removed |
| 12.4.3 | Hover shows highlight | Mouse over panel | Blue hover border appears |
| 12.4.4 | Hover leaves | Mouse away from panel | Hover border removed |
| 12.4.5 | Polygon panel selection | Click hexagon/diagonal panel | Panel selected correctly |

### 12.5 Crop Editing
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.5.1 | Crop preview appears | Select panel | Crop preview canvas shows image with crop overlay |
| 12.5.2 | Crop drag | Drag crop region in preview | Crop region moves, main canvas updates |
| 12.5.3 | Crop corner resize — BR | Drag bottom-right corner | Crop zooms in, aspect ratio preserved |
| 12.5.4 | Crop corner resize — TL | Drag top-left corner | Crop zooms in, aspect ratio preserved |
| 12.5.5 | Crop corner resize — TR | Drag top-right corner | Crop zooms in, aspect ratio preserved |
| 12.5.6 | Crop corner resize — BL | Drag bottom-left corner | Crop zooms in, aspect ratio preserved |
| 12.5.7 | Reset crop | Click "Reset Crop" | Crop returns to default centered position |
| 12.5.8 | Crop info display | Select panel | X, Y, W, H values shown |
| 12.5.9 | Crop placeholder | No panel selected, images loaded | "Select a panel" message shown |

### 12.6 Undo/Redo
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.6.1 | Undo crop adjustment | Adjust crop, click Undo | Crop reverted |
| 12.6.2 | Redo crop adjustment | Undo, click Redo | Crop restored |
| 12.6.3 | Undo layout change | Change layout, undo | Layout reverted |
| 12.6.4 | Undo gutter change | Change gutter, undo | Gutter reverted |
| 12.6.5 | Undo reset crop | Reset crop, undo | Crop restored to pre-reset |
| 12.6.6 | Keyboard undo | Cmd+Z | Same as button undo |
| 12.6.7 | Keyboard redo | Cmd+Shift+Z | Same as button redo |
| 12.6.8 | Undo button disabled initially | Fresh page | Undo button disabled |
| 12.6.9 | Redo button disabled initially | Fresh page | Redo button disabled |
| 12.6.10 | New action clears redo | Undo, then new crop | Redo button disabled |

### 12.7 Image Library Management
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.7.1 | Remove individual image | Click X on image | Image removed, layout regenerated |
| 12.7.2 | Clear all images | Click "Clear All" | All removed, empty state shown |
| 12.7.3 | Search filter | Type in search box | Only matching images shown |
| 12.7.4 | Search clear | Clear search box | All images shown |
| 12.7.5 | Image count display | Add/remove images | Count in sidebar header updates |
| 12.7.6 | Image selection in sidebar | Click image in sidebar | Image highlighted |

### 12.8 Real-World Workflows
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 12.8.1 | "Messy" workflow | Drop 15 images -> mosaic -> crop one -> switch to diagonal -> adjust gutter rapidly -> remove image #2 -> undo -> redo -> select different image -> press Escape | No crashes, state consistent, all operations complete |
| 12.8.2 | Theme toggle during crop | Active crop drag, toggle theme | Crop preview renders, no visual artifacts |
| 12.8.3 | Search with active crop | Crop active, search in sidebar | Crop state preserved, search filters library |
| 12.8.4 | Layout change during crop | Crop active on panel, switch layout | Layout changes, crop preview may reset (documented behavior) |
| 12.8.5 | Rapid image addition | Drop 20 images quickly | All load, layout generates, no crash |
| 12.8.6 | Undo after remove image | Add 5, remove #2, undo | Image #2 restored, layout correct |

---

## Section 13: State Consistency Tests

### 13.1 Cross-Operation Consistency
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 13.1.1 | Crop after layout change | Adjust crop on panel A, switch layout | New layout uses default crops (crop data lost — document this) |
| 13.1.2 | Selection after clear | Select panel, clear all | selectedPanelId = null, no stale references |
| 13.1.3 | Undo after remove image | Add 5, crop #3, remove #2, undo | #2 restored, layout regenerated with correct indices |
| 13.1.4 | Mixed undo/redo | Crop A -> change gutter -> remove B -> undo -> redo -> undo | State correct at each step |
| 13.1.5 | Crop state survives render | Adjust crop, multiple renders | Crop values stable |
| 13.1.6 | Panel assignments after image removal | Remove middle image | Assignments updated for remaining panels |

---

## Section 14: Reliability & Async Tests

### 14.1 Async Operations
| # | Test | Expected |
|---|------|----------|
| 14.1.1 | Partial image load failure | 10 files, 1 corrupted | 9 images loaded, 1 logged as warning |
| 14.1.2 | All images fail to load | 3 corrupted files | Nothing added, no crash |
| 14.1.3 | FileReader error handling | Invalid file read | Promise resolves to null, no uncaught rejection |
| 14.1.4 | Background tab resume | Tab hidden for 5 min, then activated | Canvas renders correctly on resume |
| 14.1.5 | Window resize during render | Resize window during crop drag | Crop preview resizes, no crash |

---

## Priority Ordering

### P0 — Must Pass Before Phase 3
All Section 1 (Layout Math) tests — these are the foundation that Phase 3 builds on.
All Section 3.1 (UndoManager) tests — undo is critical for Phase 3 features.
All Section 8 (Edge Cases) tests — prevent crashes from user input.
Tests 12.8.1-12.8.6 (Real-World Workflows) — validate end-to-end stability.

### P1 — Should Pass
All Section 2 (Data Models) tests.
All Section 3.2-3.5 (State Managers) tests.
All Section 4 (Rendering) tests.
All Section 5 (Interaction) tests.
All Section 6 (Integration) tests.
All Section 12 (E2E) tests.

### P2 — Nice to Have
Section 7 (Memory Management) tests.
Section 9 (Performance) tests.
Section 10 (Cross-Browser) tests.
Section 11 (Accessibility) tests.
Section 13 (State Consistency) tests.
Section 14 (Reliability) tests.

---

## Known Behaviors to Document (Not Bugs)

1. **Crop data lost on layout change**: When the user switches layout styles, all crop adjustments are reset to defaults. This is by design — `LayoutManager.regenerate()` replaces the entire crops Map. Phase 3 should consider whether crop persistence across layout changes is desired.

2. **Selection may be stale after layout change**: The `selectedPanelId` references a panel ID that may no longer exist after regeneration. The UI should handle this gracefully (crop placeholder shown).

3. **No image reordering**: The current implementation does not support drag-and-drop reordering within the image library sidebar. This is planned for Phase 3.

4. **No canvas pan/zoom**: Canvas scaling is CSS-based (`contain`). Dedicated pan/zoom gestures are deferred.
