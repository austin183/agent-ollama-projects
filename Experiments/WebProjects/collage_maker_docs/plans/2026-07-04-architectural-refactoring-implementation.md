# CollageMaker Architectural Refactoring Implementation Plan

## Status (Updated: July 5, 2026)
- **Phase 1** (Memory & Stability): ✅ Complete
- **Phase 2** (God Module Refactoring): ⏸️ On hold - core extensibility improvements completed first
- **Phase 3** (Extensibility Improvements): ✅ Complete
- **Phase 4** (Cleanup & Dead Code Removal): ✅ Complete - implemented on 2026-07-05

---

## Overview

This plan addresses critical architectural concerns in CollageMaker: memory leaks, God Module violation, framework coupling, OCP violations, duplicate logic, and dead code. The refactoring will improve maintainability, performance, and extensibility while maintaining the existing Vue 3 Options API + ES modules architecture.

## Current State Analysis

### Key Issues Identified:

1. **Memory Leaks** (Critical)
   - `ImageLibrary.js` creates HTMLImageElement objects that are stored in state but never cleaned up
   - `generateThumbnail()` creates canvases and data URLs that persist indefinitely
   - Background/overlay images hold references to loaded ImageElements
   - No cleanup lifecycle for these resources

2. **God Module** (High)
   - `createCollageMethods.js` (791 lines) violates Single Responsibility Principle
   - Contains handlers for: file input, image management, layout, crops, background, title, overlay, export, settings
   - Hard to test, maintain, and extend

3. **Framework Coupling** (High/Medium)
   - State managers directly mutate Vue reactive state (`state.images.push()`, `state.panels = []`)
   - Managers should receive a mutable data object but not assume it's Vue-specific
   - Makes unit testing difficult without DOM/Vue context

4. **OCP Violations** (Medium/High)
   - `LayoutGenerator.js` uses switch statement to dispatch layout strategies
   - `ExportManager.js` is hardcoded for JPEG only

5. **Duplicate Logic** (Medium/Low)
   - Canvas clearing: `CanvasRenderer.render()` and `CollageAssembler.render()` both clear canvas
   - Background rendering: `_drawBackground()` in Assembler duplicates basic background logic

6. **Dead Code** (Low)
   - `CollageState.js` is exported but not imported anywhere except barrel exports
   - `ComponentRegistry.js` is imported by `CollageBase.js` but only used for component registry pattern; may be unused

### Key Discoveries:
- `ImageItem.js` uses data URLs for thumbnails (line 55) which cannot be revoked but should be cleaned up
- `CanvasRenderer.dispose()` exists but doesn't clean up image references
- `createCollageLifecycle.beforeUnmount()` partially cleans up but only sets images to null, not disposing underlying resources

## Desired End State

After this refactoring:
1. All image resources are properly disposed when removed or app unmounts
2. Methods are broken into focused, testable units
3. State managers work with plain data objects (no Vue coupling)
4. Layout system is open for extension without modifying switch statement
5. Export system supports multiple formats via strategy pattern
6. No duplicate canvas clearing or background logic
7. Dead code removed or activated

## What We're NOT Doing

- **No framework change**: Continue using Vue 3 Options API
- **No build step addition**: Maintain ES modules from CDN
- **No breaking changes to public API**: Internal refactoring only
- **No new features**: Focus solely on architectural improvements
- **No removal of ComponentRegistry.js yet**: Evaluate its actual usage before deletion

## Implementation Approach

The refactoring follows a phased approach:
1. **Phase 1** fixes critical memory leaks first (prevents issues during subsequent refactoring)
2. **Phase 2** refactors the God Module into smaller, focused modules
3. **Phase 3** improves extensibility and removes duplication
4. **Phase 4** cleans up dead code

Each phase is independently testable and provides incremental value.

---

## Phase 1: Memory & Stability

### Overview
Fix all memory leaks to prevent accumulation of image elements, canvases, and object URLs. This phase must complete before major refactoring to ensure stability.

### Changes Required:

#### 1. ImageLibrary - Add dispose method for single image
**File**: `MyESModules/State/ImageLibrary.js`

```javascript
// Add to createImageLibrary return object
disposeImage(index) {
    if (index < 0 || index >= state.images.length) return;
    
    const imageItem = state.images[index];
    if (imageItem && imageItem.image) {
        // Clear image reference - browser will garbage collect
        imageItem.image = null;
    }
    
    // Remove from array
    state.images.splice(index, 1);
    onImagesChanged();
}
```

#### 2. ImageLibrary - Add batch dispose for clearAll
**File**: `MyESModules/State/ImageLibrary.js`

```javascript
// Modify clearAll method
clearAll() {
    // Dispose each image first
    state.images.forEach(img => {
        if (img && img.image) {
            img.image = null;
        }
    });
    
    state.images = [];
    onImagesChanged();
}
```

#### 3. ImageItem - Add dispose helper (optional utility)
**File**: `MyESModules/Models/ImageItem.js`

```javascript
// Add at bottom of file
export function disposeImageItem(item) {
    if (item && item.image) {
        item.image = null;
    }
}
```

#### 4. createCollageLifecycle - Enhance beforeUnmount cleanup
**File**: `MyESModules/App/createCollageLifecycle.js`

```javascript
beforeUnmount() {
    window.removeEventListener('resize', this._handleResize);
    if (this._keyboardHandler) {
        this._keyboardHandler.detach();
    }
    if (this._gestureHandler) {
        this._gestureHandler.detach();
    }
    if (this._cropInteraction) {
        this._cropInteraction.detach();
    }
    if (this.canvasRenderer) {
        this.canvasRenderer.dispose();
    }
    
    // Dispose all images in library
    if (this.imageLibrary) {
        // Clear all images (this will dispose them)
        this.imageLibrary.clearAll();
    }
    
    // Dispose background and overlay images
    if (this.backgroundImage) {
        this.backgroundImage = null;
    }
    if (this.overlayImage) {
        this.overlayImage = null;
    }
}
```

#### 5. Add image disposal to removeImage methods in createCollageMethods
**File**: `MyESModules/App/createCollageMethods.js`

```javascript
// Modify removeImage method (line 63-66)
removeImage(index) {
    // Use disposeImage instead of removeImage for proper cleanup
    this.imageLibrary.disposeImage(index);
    this._regenerateAndRender();
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Unit tests pass for ImageLibrary dispose methods
- [ ] No memory leaks detected in Chrome DevTools Memory tab after adding/removing images
- [ ] `beforeUnmount` cleanup runs without errors

#### Manual Verification:
- [ ] Add 10 images, then remove all - memory usage returns to baseline
- [ ] Refresh page multiple times - no increase in memory
- [ ] Export collage after removing images works correctly

### Risk Mitigation:
- **Risk**: Disposing images might break if references are held elsewhere
  **Mitigation**: Test carefully with DevTools heap snapshots
- **Risk**: clearAll() called while render pending might cause errors
  **Mitigation**: Check for nulls in render functions

### Testing Strategy:

#### Unit Tests (Mocha/Chai):
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | disposeImage removes image and clears reference | imageItem with image | image removed from state.images, image property set to null |
| 1.1.2 | clearAll disposes all images | array of 5 images | all images disposed, state.images empty |
| 1.1.3 | disposeImage out of bounds | index = -1 or >= length | no error, state unchanged |

#### E2E Tests (Playwright):
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.1.e.1 | Memory cleanup on page refresh | 1. Add 10 images<br>2. Remove all<br>3. Refresh page<br>4. Check memory | Memory usage < 50MB after cleanup |

---

## Phase 2: Architecture Refactoring - Decouple State Managers

### Overview
Break down `createCollageMethods.js` (791 lines) into smaller, focused modules. Decouple state managers from direct Vue reactive state mutation to improve testability and follow separation of concerns.

### Changes Required:

#### 1. Create pure action functions for state mutations
**New File**: `MyESModules/State/actions.js` (or split into multiple files)

```javascript
// Example: Image actions
export function addImagesAction(state, images) {
    state.images.push(...images);
}

export function removeImageAction(state, index) {
    if (index >= 0 && index < state.images.length) {
        state.images.splice(index, 1);
    }
}

// Layout actions
export function regenerateLayoutAction(state, panels, crops, panelAssignments) {
    state.panels = panels;
    state.crops = crops;
    state.panelAssignments = panelAssignments;
    state.layoutVersion++;
}

// Crop actions
export function setCropAction(state, panelId, crop) {
    state.crops.set(panelId, crop);
}
```

#### 2. Refactor state managers to use actions (not direct mutation)
**File**: `MyESModules/State/LayoutManager.js`

```javascript
import { regenerateLayoutAction } from './actions.js';

export function createLayoutManager(state, assembler) {
    return {
        regenerate() {
            // ... compute panels, crops, assignments ...
            
            // Instead of directly mutating state:
            // state.panels = ...
            regenerateLayoutAction(state, panels, crops, panelAssignments);
        },
        
        setLayoutStyle(style) {
            state.layoutStyle = style;
            this.regenerate();
        },
        
        // ... other methods remain similar
    };
}
```

Apply same pattern to `CropManager.js`, `BackgroundManager.js`, `TitleManager.js`.

#### 3. Break down createCollageMethods.js into smaller modules
**New Files**:
- `MyESModules/App/createFileHandlers.js` - file input, drag-drop handling
- `MyESModules/App/createImagePanelHandlers.js` - image selection, removal
- `MyESModules/App/createLayoutHandlers.js` - layout style, gutter, angle changes
- `MyESModules/App/createCropHandlers.js` - crop adjustments, reset
- `MyESModules/App/createBackgroundHandlers.js` - background controls
- `MyESModules/App/createTitleHandlers.js` - title editing, formatting
- `MyESModules/App/createOverlayHandlers.js` - overlay controls
- `MyESModules/App/createExportHandlers.js` - export functionality
- `MyESModules/App/createSettingsHandlers.js` - settings persistence

**Example**: `createFileHandlers.js`

```javascript
export function createFileHandlers(imageLibrary, onRegenerate) {
    return {
        triggerFilePicker() {
            const input = document.getElementById('fileInput');
            if (input) {
                input.value = '';
                input.click();
            }
        },
        
        handleFileInputChange(event) {
            const files = event.target.files;
            if (files && files.length > 0) {
                imageLibrary.addImages(files).then(() => {
                    onRegenerate();
                });
            }
        }
    };
}
```

#### 4. Update createCollageApp to compose smaller method modules
**File**: `MyESModules/App/createCollageApp.js` (or `createCollageMethods.js` as composition point)

```javascript
// Instead of importing one huge methods module:
import { createFileHandlers } from './createFileHandlers.js';
import { createImagePanelHandlers } from './createImagePanelHandlers.js';
// ... other handlers

export function createCollageApp({
    createApp,
    dataConfig,
    methodsConfig,
    lifecycleConfig,
    servicesConfig
}) {
    // Merge all handler objects
    const allMethods = {
        ...createFileHandlers(base.imageLibrary, () => {
            base.layoutManager.regenerate();
            base.canvasRenderer.scheduleRender(/* render */);
        }),
        ...createImagePanelHandlers(base.imageLibrary, base.layoutManager, base.canvasRenderer),
        ...createLayoutHandlers(base.layoutManager, base.canvasRenderer),
        // ... other handlers
    };

    // ... rest of app setup remains same
}
```

#### 5. Update createCollageLifecycle to provide dependencies to handlers
**File**: `MyESModules/App/createCollageLifecycle.js`

```javascript
mounted() {
    // ... existing initialization code ...
    
    // Provide base object to lifecycle so handlers can access services
    base.imageLibrary = imageLibrary;
    base.layoutManager = layoutManager;
    // ... other services
}
```

### Success Criteria:

#### Automated Verification:
- [ ] All unit tests for individual handler modules pass
- [ ] State action functions testable without Vue context (pure functions with state param)
- [ ] `createCollageMethods.js` reduced from 791 lines to < 100 lines (composition only)

#### Manual Verification:
- [ ] All UI interactions work identically after refactoring
- [ ] No console errors when using all features
- [ ] Settings persistence still works

### Risk Mitigation:
- **Risk**: Breaking changes in handler interfaces
  **Mitigation**: Keep original method signatures in composition layer
- **Risk**: Handlers losing access to Vue `this` context
  **Mitigation**: Pass necessary dependencies as parameters (dependency injection)

### Testing Strategy:

#### Unit Tests for Actions:
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.1.1 | addImagesAction mutates state correctly | state with images=[], newImages=[img1, img2] | state.images = [img1, img2] |
| 2.1.2 | removeImageAction removes at index | state.images=[a,b,c], index=1 | state.images=[a,c] |
| 2.1.3 | regenerateLayoutAction updates all fields | state with old panels, new panels array | state.panels = new panels, layoutVersion incremented |

#### Unit Tests for Handlers:
| # | Test | Setup | Expected |
|---|------|-------|----------|
| 2.2.1 | triggerFilePicker calls input.click() | mock DOM element with id=fileInput | click() called once |
| 2.2.2 | handleFileInputChange adds images | mock event with files array | imageLibrary.addImages called |

#### E2E Tests:
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.2.e.1 | All features work post-refactor | 1. Add images<br>2. Change layout style<br>3. Adjust crop<br>4. Change background<br>5. Edit title<br>6. Export | All actions succeed, UI updates correctly |

---

## Phase 3: Extensibility Improvements

### Overview
Make the system more extensible by following Open/Closed Principle and removing duplicate logic. This phase adds flexibility for future enhancements.

### Changes Required:

#### 1. Refactor LayoutGenerator to use strategy pattern (OCP compliance)
**File**: `MyESModules/Layout/LayoutGenerator.js`

```javascript
import { LayoutStyle } from '../Models/LayoutStyle.js';
import { generateUniformLayout } from './UniformLayout.js';
import { generateHeroLayout } from './HeroLayout.js';
import { generateMosaicLayout } from './MosaicLayout.js';
import { generateDiagonalSlicesLayout } from './DiagonalSlicesLayout.js';
import { generateHexagonalLayout } from './HexagonalLayout.js';

// Map of layout styles to generator functions
const LAYOUT_GENERATORS = {
    [LayoutStyle.UNIFORM]: generateUniformLayout,
    [LayoutStyle.HERO]: generateHeroLayout,
    [LayoutStyle.MOSAIC]: generateMosaicLayout,
    [LayoutStyle.DIAGONAL_SLICES]: generateDiagonalSlicesLayout,
    [LayoutStyle.HEXAGONAL]: generateHexagonalLayout
};

export const LayoutGenerator = {
    generate({
        numImages,
        canvasSize = { width: 1920, height: 1080 },
        gutter = 4,
        style = LayoutStyle.HERO,
        imageOrder = null,
        mosaicSeed = null,
        sliceAngle = 45,
        hexSpacing = 8
    }) {
        const base = { numImages, canvasSize, gutter, imageOrder };
        
        const generator = LAYOUT_GENERATORS[style];
        if (!generator) {
            console.warn(`Unknown layout style: ${style}, defaulting to HERO`);
            return generateHeroLayout(base);
        }
        
        switch (style) {
            case LayoutStyle.MOSAIC:
                return generator({ ...base, mosaicSeed });
            case LayoutStyle.DIAGONAL_SLICES:
                return generator({ ...base, angle: sliceAngle });
            case LayoutStyle.HEXAGONAL:
                return generator({ ...base, spacing: hexSpacing });
            default:
                return generator(base);
        }
    },
    
    // New method to register custom layout generators
    registerLayoutStyle(styleName, generatorFn) {
        LAYOUT_GENERATORS[styleName] = generatorFn;
    }
};
```

#### 2. Refactor ExportManager to support multiple formats via strategy pattern
**New File**: `MyESModules/Export/formats/jpegExporter.js`

```javascript
export function exportToJpeg(assembler, state, quality = 0.92) {
    return new Promise((resolve, reject) => {
        try {
            const canvas = document.createElement('canvas');
            canvas.width = 1920;
            canvas.height = 1080;
            const ctx = canvas.getContext('2d');
            if (!ctx) {
                reject('Failed to get canvas 2D context');
                return;
            }

            // Render collage
            assembler.render(ctx, {
                panels: state.panels,
                images: state.images,
                crops: state.crops,
                panelAssignments: state.panelAssignments,
                backgroundColor: state.backgroundColor,
                canvasSize: { width: 1920, height: 1080 },
                selectedPanelId: null,
                hoveredPanelId: null,
                backgroundState: state.backgroundState,
                overlayState: state.overlayState,
                titleStyle: state.titleStyle,
                titleRuns: state.titleRuns
            });

            // Export as JPEG
            canvas.toBlob((blob) => {
                if (!blob) {
                    reject('Failed to generate JPEG blob');
                    return;
                }

                const url = URL.createObjectURL(blob);
                let a = null;
                try {
                    a = document.createElement('a');
                    a.href = url;
                    a.download = 'collage.jpg';
                    document.body.appendChild(a);
                    a.click();
                } finally {
                    if (a && document.body.contains(a)) {
                        document.body.removeChild(a);
                    }
                    URL.revokeObjectURL(url);
                }
                resolve('success');
            }, 'image/jpeg', quality);

        } catch (e) {
            reject('Export failed: ' + e.message);
        }
    });
}
```

**New File**: `MyESModules/Export/formats/pngExporter.js`

```javascript
export function exportToPng(assembler, state) {
    return new Promise((resolve, reject) => {
        try {
            const canvas = document.createElement('canvas');
            canvas.width = 1920;
            canvas.height = 1080;
            const ctx = canvas.getContext('2d');
            if (!ctx) {
                reject('Failed to get canvas 2D context');
                return;
            }

            assembler.render(ctx, { /* same params */ });

            canvas.toBlob((blob) => {
                if (!blob) {
                    reject('Failed to generate PNG blob');
                    return;
                }

                const url = URL.createObjectURL(blob);
                let a = null;
                try {
                    a = document.createElement('a');
                    a.href = url;
                    a.download = 'collage.png';
                    document.body.appendChild(a);
                    a.click();
                } finally {
                    if (a && document.body.contains(a)) {
                        document.body.removeChild(a);
                    }
                    URL.revokeObjectURL(url);
                }
                resolve('success');
            }, 'image/png');

        } catch (e) {
            reject('Export failed: ' + e.message);
        }
    });
}
```

**New File**: `MyESModules/Export/ExportManager.js`

```javascript
import { exportToJpeg } from './formats/jpegExporter.js';
import { exportToPng } from './formats/pngExporter.js';

// Registry of export formats
const EXPORT_FORMATS = {
    jpeg: exportToJpeg,
    png: exportToPng
};

export const ExportManager = {
    registerFormat(formatName, exporterFn) {
        EXPORT_FORMATS[formatName] = exporterFn;
    },
    
    async export(assembler, state, format = 'jpeg', quality = 0.92) {
        const exporter = EXPORT_FORMATS[format];
        if (!exporter) {
            throw new Error(`Unsupported export format: ${format}`);
        }
        
        return exporter(assembler, state, quality);
    }
};
```

**Modify**: `MyESModules/App/createCollageMethods.js` (now small composition file)

```javascript
// Replace exportCollage method in createCollageMethods.js
async exportCollage() {
    if (this.isExporting) return;
    this.isExporting = true;
    this.exportStatus = 'Exporting...';

    try {
        const state = { /* build state object */ };
        
        // Use ExportManager instead of direct JPEG call
        await this.ExportManager.export(
            this._assembler, 
            state, 
            this.exportFormat || 'jpeg', 
            this.exportQuality
        );
        
        this.exportStatus = 'Exported successfully!';
        setTimeout(() => { this.exportStatus = ''; }, 3000);
    } catch (e) {
        console.error('Export failed:', e);
        this.exportStatus = 'Export failed: ' + e;
        setTimeout(() => { this.exportStatus = ''; }, 6000);
    } finally {
        this.isExporting = false;
    }
}
```

#### 3. Consolidate duplicate canvas clearing logic
**File**: `MyESModules/Rendering/CanvasRenderer.js`

```javascript
render(drawFn) {
    if (!ctx || !canvas) return;

    const width = canvas.width / (window.devicePixelRatio || 1);
    const height = canvas.height / (window.devicePixelRatio || 1);

    // Clear canvas - centralized clearing logic
    this.clear(width, height);

    // Execute custom draw function
    if (drawFn && typeof drawFn === 'function') {
        drawFn(ctx, width, height);
    }
}

clear(width, height) {
    // Clear canvas
    ctx.clearRect(0, 0, width, height);
    
    // Fill white background
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
}
```

**File**: `MyESModules/Rendering/CollageAssembler.js` - Remove `_drawBackground` and redundant clearing

```javascript
render(ctx, { panels, images, crops, panelAssignments, backgroundColor, canvasSize, selectedPanelId, hoveredPanelId, backgroundState, overlayState, titleStyle, titleRuns, showDebugOverlay, focusPoints }) {
    const w = canvasSize.width;
    const h = canvasSize.height;

    // NOTE: Canvas should be cleared by the renderer before calling this method
    // If backgroundState is provided, render it; otherwise use legacy fallback
    if (backgroundState) {
        renderBackground(ctx, w, h, backgroundState);
    } else {
        // Only render background color if no backgroundState provided
        // but canvas is already cleared
        this._drawBackgroundOnly(ctx, canvasSize, backgroundColor);
    }

    // ... rest of rendering code remains
}

// Rename _drawBackground to _drawBackgroundOnly to clarify it's just the background drawing part
_drawBackgroundOnly(ctx, canvasSize, color) {
    if (typeof color === 'string') {
        ctx.fillStyle = color;
    } else if (color && color.r !== undefined) {
        ctx.fillStyle = `rgb(${color.r}, ${color.g}, ${color.b})`;
    } else {
        ctx.fillStyle = '#ffffff';
    }
    ctx.fillRect(0, 0, canvasSize.width, canvasSize.height);
}
```

### Success Criteria:

#### Automated Verification:
- [ ] `LayoutGenerator.generate()` works with new layout styles without modification
- [ ] `ExportManager.export()` can export to JPEG and PNG
- [ ] New format can be registered via `registerFormat()`

#### Manual Verification:
- [ ] Adding a new layout style requires only adding a new generator file and registering it
- [ ] Export dialog allows choosing between JPEG and PNG
- [ ] Canvas rendering performance unchanged

### Risk Mitigation:
- **Risk**: Breaking existing code that imports from `LayoutGenerator` directly
  **Mitigation**: Keep the same public API, just refactor internal implementation
- **Risk**: Export format registration not properly initialized
  **Mitigation**: Ensure default formats are registered at app startup

### Testing Strategy:

#### Unit Tests for LayoutGenerator:
| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.1 | generate with unknown style defaults to HERO | style = 'unknown' | returns same as generateHeroLayout() |
| 3.1.2 | registerLayoutStyle adds custom generator | register 'custom', genFn | generate({style:'custom'}) calls genFn |

#### Unit Tests for ExportManager:
| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.2.1 | export with jpeg format works | format='jpeg' | returns Promise resolved with 'success' |
| 3.2.2 | export with png format works | format='png' | returns Promise resolved with 'success' |
| 3.2.3 | export with unsupported format rejects | format='gif' | Promise rejected with error |

---

## Phase 4: Cleanup & Dead Code Removal

### Overview
Remove dead code and evaluate the usefulness of `ComponentRegistry.js`. This phase should happen after all other refactoring is complete and tested.

### Changes Required:

#### 1. Remove CollageState.js if truly unused
**Action**: Delete `MyESModules/State/CollageState.js`

First, verify it's not used anywhere:
```bash
grep -r "createCollageState" MyESModules --include="*.js" | grep -v "export {"
```

If only exported from index.js and not imported anywhere else, delete the file.

**File**: `MyESModules/index.js` - Remove export
```javascript
// Remove this line:
// export { createCollageState } from './State/CollageState.js';
```

#### 2. Evaluate ComponentRegistry.js
**Action**: Check if `getComponentRegistry()` is actually used in CollageBase and elsewhere.

If the component registry pattern is not actively used (no services registered beyond initial setup), consider:
- Option A: Remove `ComponentRegistry.js` entirely
- Option B: Activate it by using it for dependency injection across components

**Current usage**: `CollageBase.js` imports and creates one instance, but never uses `registerService` or `getService`.

If unused, remove:

**File**: `MyESModules/App/CollageBase.js` - Remove import and usage
```javascript
// Remove these lines:
// import { getComponentRegistry } from '../Utils/ComponentRegistry.js';
// const componentRegistry = getComponentRegistry();
```

Then delete `ComponentRegistry.js`.

Alternatively, if we want to keep it for future use, add a deprecation comment.

#### 3. Consolidate background rendering (if duplicate logic remains)
**File**: `MyESModules/Rendering/BackgroundRenderer.js` - Ensure it's comprehensive

If there's still duplication between `CollageAssembler._drawBackgroundOnly()` and `BackgroundRenderer`, consider removing the former and always using `BackgroundRenderer`.

### Success Criteria:

#### Automated Verification:
- [ ] All tests pass after dead code removal
- [ ] No import errors in any module

#### Manual Verification:
- [ ] App starts without errors
- [ ] All features still work

### Risk Mitigation:
- **Risk**: Accidentally removing code that is actually used
  **Mitigation**: Use grep to confirm no imports before deletion
- **Risk**: Breaking tests that depend on dead code exports
  **Mitigation**: Run full test suite after removal

### Testing Strategy:

#### Automated Verification:
- [ ] Run `node scripts/run-tests.js` - all tests pass
- [ ] Import all modules in browser console without errors

---

## Migration Notes

1. **State Changes**: All state managers now receive a plain data object instead of assuming Vue reactive state. This is backward compatible if the object has the same properties.

2. **Handler Composition**: `createCollageMethods.js` becomes a composition layer that merges smaller handler modules. Existing UI code continues to work because the method signatures remain the same.

3. **Export Format**: The app defaults to JPEG export to maintain backward compatibility. PNG export is added as an optional feature (can be exposed via UI later).

4. **Memory Cleanup**: The cleanup in `beforeUnmount` calls `imageLibrary.clearAll()` which now properly disposes images. This doesn't change behavior for users but prevents memory leaks.

5. **ComponentRegistry**: If removed, any code that might have used it in the future will need to use direct dependency injection (which is already the pattern we're adopting).

## References

- Original issue analysis: World-review architectural concerns
- Writing-plans skill template: Structured implementation plan format
- Building-web-apps skill: Vue 3 Options API, ES modules, Canvas 2D patterns
- Existing test patterns: Mocha/Chai unit tests in `MyComponents/`

## Critical Files for Implementation

1. **MyESModules/State/ImageLibrary.js** - Core memory leak fix and dispose methods
2. **MyESModules/App/createCollageMethods.js** - Break down from 791 lines to composition layer
3. **MyESModules/Rendering/CollageAssembler.js** - Remove duplicate canvas clearing logic
4. **MyESModules/Layout/LayoutGenerator.js** - Refactor to strategy pattern for OCP compliance
5. **MyESModules/Export/ExportManager.js** - Add extensible format support

## Relevant Skill References

- `references/vue-options-api.md` — Vue 3 Options API factory decomposition patterns
- `references/canvas-2d.md` — Canvas 2D rendering, DPR scaling, cleanup considerations
- `references/es-modules.md` — ES module conventions and barrel exports
- `references/testing.md` — Mocha/Chai and Playwright patterns for testing refactored code
- `references/midiestro-pattern.md` — The proven Midiestro3D pattern for modular architecture

---

**Next Steps**: This plan should be reviewed and approved before implementation begins. Each phase can be worked on incrementally with testing at each step.
