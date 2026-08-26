# Title Enhancements, Sidebar Reorganization, and Home Link Implementation Plan

## Overview

This plan covers three feature specifications for CollageMaker:

1. **Enhanced Title Features** — Movable title box, resizable width, opacity controls, and alignment within configured width
2. **Move Layout to Left Sidebar** — Relocate Layout section from right to left sidebar, make Image Library collapsible
3. **Link to Home** — Add a navigation link in the toolbar to return to the project home page

These features enhance the title editing experience, improve sidebar organization, and add basic navigation. They are ordered by implementation priority: Spec 3 (trivial) first, then Spec 2 (UI restructuring), then Spec 1 (renderer + interaction logic).

## Current State Analysis

### Title System (Spec 1)
- **TitleRenderer.js** renders title at fixed bottom position (`height - MARGIN`) with alignment computed from canvas width. No position, width, or opacity fields exist in the data model.
- **TitleStyle.js** (`createTitleStyle()`) defines: `fontFamily`, `fontSize`, `fontColor`, `backgroundColor`, `alignment`, `showBackground`. Missing: position, width, opacity.
- **TitleManager.js** manages text runs and style setters. Missing: position/width/opacity setters.
- **No interaction handler** exists for title manipulation on canvas. The existing `GestureHandler.js` only handles hover, and `PanelSwap.js` handles panel drag-and-drop.
- **CollageAssembler.js** calls `renderTitle(ctx, w, h, titleStyle, titleRuns)` at step 8 (last in pipeline).

### Sidebar Layout (Spec 2)
- **Left sidebar** (`#sidebar-left`): Static `<h3>` header + search input + image list. Not collapsible.
- **Right sidebar** (`#sidebar-right`): Collapsible sections via `sidebarSections` array in `createCollageData.js`. Layout is section index 1.
- **Collapsible section pattern**: `sidebar-section-header` button with chevron, `sidebar-section-content` with `v-show`. Works via `toggleSection(sectionId)` method.

### Toolbar (Spec 3)
- **Toolbar** (`#toolbar`): Contains `<h2 class="app-title">CollageMaker</h2>` followed by action buttons. No navigation links.

### Key Discoveries
- `createTitleStyle()` in `MyESModules/Models/TitleStyle.js:17` — factory returns defaults; adding new fields here propagates to all instances
- `createCollageData.js:44` — `titleStyle: createTitleStyle()` — no manual field listing needed
- `PanelSwap.js:257` — interaction handler pattern: factory function with `attach()`, `detach()`, pointer capture, drag threshold, global pointerup cleanup
- `TitleRenderer.js:6` — `MARGIN = 40`, `PADDING = 12` constants control title positioning
- `CollageAssembler.js:96-98` — title is last render step, so `globalAlpha` leakage is low risk but must still be guarded with `save()`/`restore()`
- `createSettingsHandlers.js:18-36` — `_saveSettings` manually enumerates fields; new title fields need to be added here
- `createCollageLifecycle.js:295-318` — `_applySavedSettings` also manually enumerates fields for loading

## Desired End State

### Spec 1: Enhanced Title Features
- Title renders at user-configured position (`titleBoxX`, `titleBoxY`) with fallback to default bottom-margin position
- Title background width is user-configurable (`titleBoxWidth`) with text alignment computed within that width
- Font and background colors support opacity (`fontOpacity`, `bgOpacity`) rendered via `globalAlpha`
- Canvas interaction: click-drag moves title, edge-drag resizes width, hover shows outline and cursor feedback
- All title changes persist across sessions via localStorage
- All title changes are undoable via existing undo system

### Spec 2: Layout in Left Sidebar
- Left sidebar has two collapsible sections: "Image Library" (default expanded) and "Layout" (default collapsed)
- Right sidebar has five collapsible sections: Crop, Background, Overlay, Title, Export (Layout removed)
- Collapsible section behavior (chevron, ARIA, expand/collapse) is consistent across both sidebars
- All existing layout controls (style selector, gutter, slice angle, hex spacing/size) function identically

### Spec 3: Home Link
- A home icon link appears after "CollageMaker" in the toolbar
- Link targets `../index.html` with `target="_blank"` and `rel="noopener"`
- Hover state provides visual feedback (color change, background highlight)

## What We're NOT Doing

- **Title text wrapping** — If title box width is narrower than text, text will overflow (not wrap or truncate)
- **Keyboard nudging** — Arrow key position adjustment for title is out of scope
- **Multi-touch title interaction** — Single-finger pointer events only; no pinch-to-move title
- **Section state persistence** — Collapsible section states (expanded/collapsed) are NOT persisted to localStorage
- **Right sidebar grouping** — No visual grouping headers (e.g., "Design Settings") added to right sidebar
- **Title rotation, shadow, or stroke** — Only position, width, and opacity are enhanced
- **Mobile-specific sidebar behavior** — Responsive sidebar collapse is out of scope

## Implementation Approach

Features are implemented in dependency order: Spec 3 first (zero dependencies), Spec 2 second (UI-only, no logic changes), Spec 1 last (renderer + interaction logic, highest complexity).

Spec 1 is further split into sub-phases: opacity (isolated renderer change), then width/alignment (positioning math), then position (pass-through), then interaction (new module), then persistence (final polish).

---

## Phase 1: Home Link (Spec 3)

### Overview
Add a home icon link after the "CollageMaker" title in the toolbar. Purely additive HTML/CSS change with no JavaScript or state modifications.

### Changes Required:

#### 1. HTML Template
**File**: `index.html` (line 23)

Wrap the `<h2>` in a flex container and add the link:

```html
<div id="toolbar" class="collage-toolbar">
    <div class="app-title-group">
        <h2 class="app-title">CollageMaker</h2>
        <a href="../index.html" target="_blank" rel="noopener" class="home-link" title="Go to home page" aria-label="Go to home page">
            <span class="material-icons" style="font-size: 18px; vertical-align: middle;">home</span>
        </a>
    </div>
    <div class="toolbar-actions">
```

#### 2. CSS Styles
**File**: `Style.css` (append after `.app-title` block, ~line 32)

```css
.app-title-group {
    display: flex;
    align-items: center;
    gap: var(--space-2);
}

.home-link {
    color: var(--color-text-secondary);
    text-decoration: none;
    display: flex;
    align-items: center;
    padding: var(--space-1);
    border-radius: var(--radius-small);
    transition: color var(--transition-fast), background-color var(--transition-fast);
}

.home-link:hover {
    color: var(--color-primary);
    background-color: var(--color-surface-variant);
}
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | The CollageMaker app is loaded | The user looks at the toolbar | A home icon link is visible immediately after "CollageMaker" |
| 1.1.2 | The user hovers over the home link | The cursor is over the link | The link color changes to primary and background highlights |
| 1.1.3 | The user clicks the home link | The click completes | A new browser tab opens to `../index.html` and the CollageMaker tab remains open |
| 1.1.4 | The CollageMaker app is loaded | The user inspects the link attributes | `target="_blank"` and `rel="noopener"` are present |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.1.e.1 | Home link is visible | Navigate to CollageMaker, locate `.home-link` | Element is visible |
| 1.1.e.2 | Home link has correct attributes | Get `href`, `target`, `rel` attributes | `href="../index.html"`, `target="_blank"`, `rel="noopener"` |
| 1.1.e.3 | Home link opens new tab | Click `.home-link` | A new page context is created pointing to home page |

### Success Criteria:

#### Automated Verification:
- [ ] E2E test confirms `.home-link` is visible
- [ ] E2E test confirms `href`, `target`, `rel` attributes are correct
- [ ] No existing tests regress

#### Manual Verification:
- [ ] Home icon is visible and styled consistently with toolbar
- [ ] Hover state provides clear visual feedback
- [ ] Click opens new tab without disrupting current collage session
- [ ] Link is accessible (keyboard focusable, ARIA label present)

---

## Phase 2: Move Layout to Left Sidebar (Spec 2)

### Overview
Restructure the left sidebar to use the same collapsible section pattern as the right sidebar. Move Layout controls from right to left sidebar. This is a UI-only change — no handler logic, state management, or rendering changes.

### Changes Required:

#### 1. Data Model
**File**: `MyESModules/App/createCollageData.js` (lines 81-96)

Remove `layout` from `sidebarSections` and `expandedSections`. Add `leftSidebarSections` and `expandedLeftSections`:

```javascript
// Left sidebar sections (NEW)
leftSidebarSections: [
    { id: 'library', label: 'Image Library' },
    { id: 'layout', label: 'Layout' }
],
expandedLeftSections: {
    library: true,
    layout: false
},

// Right sidebar sections (layout REMOVED)
sidebarSections: [
    { id: 'crop', label: 'Crop' },
    { id: 'background', label: 'Background' },
    { id: 'overlay', label: 'Overlay' },
    { id: 'title', label: 'Title' },
    { id: 'export', label: 'Export' }
],
expandedSections: {
    crop: false,
    background: false,
    overlay: false,
    title: false,
    export: false
},
```

#### 2. Left Sidebar HTML
**File**: `index.html` (lines 51-74)

Replace the static left sidebar with collapsible sections:

```html
<div id="sidebar-left" class="sidebar sidebar-left">
    <div class="sidebar-scroll-container">
        <div class="sidebar-section" v-for="section in leftSidebarSections" :key="'left-' + section.id">
            <button class="sidebar-section-header" @click="toggleLeftSection(section.id)" :aria-expanded="expandedLeftSections[section.id]" :aria-controls="'left-section-content-' + section.id">
                <span class="section-chevron" :class="{ expanded: expandedLeftSections[section.id] }">▶</span>
                <span>{{ section.label }}
                    <span v-if="section.id === 'library'" class="section-count">({{ images.length }})</span>
                </span>
            </button>
            <div class="sidebar-section-content" :id="'left-section-content-' + section.id" v-show="expandedLeftSections[section.id]">
                <!-- Image Library Section -->
                <template v-if="section.id === 'library'">
                    <div class="library-search">
                        <input type="text" v-model="searchQuery" placeholder="Search by filename..." class="pure-input-rounded">
                    </div>
                    <div class="image-library">
                        <div v-if="filteredImages.length === 0" class="empty-library">
                            <span class="material-icons" style="font-size: 48px; opacity: 0.4;">image</span>
                            <p>No images yet</p>
                            <p class="hint">Drag &amp; drop images here or click "Add Images"</p>
                        </div>
                        <div v-for="(image, index) in filteredImages" :key="image.id"
                             class="image-item"
                             :class="{ selected: selectedImageId === image.id }"
                             @click="selectImage(index)">
                            <div class="image-number">{{ index + 1 }}</div>
                            <img :src="image.thumbnail" :alt="image.filename" class="image-thumb">
                            <div class="image-name" :title="image.filename">{{ truncateFilename(image.filename) }}</div>
                            <button class="remove-btn" @click.stop="removeImage(index)" title="Remove">
                                <span class="material-icons">close</span>
                            </button>
                        </div>
                    </div>
                </template>

                <!-- Layout Section (moved from right sidebar) -->
                <template v-if="section.id === 'layout'">
                    <div class="detail-section">
                        <label for="layoutStyleSelect">Layout Style</label>
                        <select id="layoutStyleSelect" v-model="layoutStyle" class="pure-input-rounded" @change="onLayoutStyleChange">
                            <option v-for="style in layoutStyles" :key="style.value" :value="style.value">{{ style.label }}</option>
                        </select>
                    </div>
                    <div class="detail-section" v-show="layoutStyle !== 'hexagonal'">
                        <label for="gutterSlider">Gutter: {{ gutter }}px</label>
                        <input type="range" id="gutterSlider" v-model.number="gutter" min="0" max="20" step="1" class="fullRange" @input="onGutterChange">
                    </div>
                    <div class="detail-section" v-if="layoutStyle === 'diagonalSlices'">
                        <label for="sliceAngleSlider">Slice Angle: {{ sliceAngle }}&deg;</label>
                        <input type="range" id="sliceAngleSlider" v-model.number="sliceAngle" min="-75" max="75" step="1" class="fullRange" @input="onSliceAngleChange">
                    </div>
                    <div class="detail-section" v-if="layoutStyle === 'hexagonal'">
                        <label for="hexSpacingSlider">Hex Spacing: {{ hexSpacing }}px</label>
                        <input type="range" id="hexSpacingSlider" v-model.number="hexSpacing" min="0" max="30" step="1" class="fullRange" @input="onHexSpacingChange">
                    </div>
                    <div class="detail-section" v-if="layoutStyle === 'hexagonal'">
                        <label for="hexSizeSlider">Hexagon Size: {{ Math.round(hexSizeMultiplier * 100) }}%</label>
                        <input type="range" id="hexSizeSlider" v-model.number="hexSizeMultiplier" min="0.5" max="2" step="0.05" class="fullRange" @input="onHexSizeMultiplierChange">
                    </div>
                    <div class="layout-shortcut-hint">
                        Shortcuts: Alt+1 Uniform · Alt+2 Hero · Alt+3 Mosaic · Alt+4 Slices · Alt+5 Hex
                    </div>
                </template>
            </div>
        </div>
    </div>
</div>
```

#### 3. Right Sidebar HTML
**File**: `index.html` (lines 102-135)

Remove the Layout template block from the right sidebar's `v-for` loop. The remaining sections (Crop, Background, Overlay, Title, Export) stay unchanged.

#### 4. Methods
**File**: `MyESModules/App/createCollageMethods.js` (after `toggleSection`, ~line 293)

Add left sidebar toggle method:

```javascript
toggleLeftSection(sectionId) {
    this.expandedLeftSections[sectionId] = !this.expandedLeftSections[sectionId];
},
```

#### 5. CSS
**File**: `Style.css` (append)

```css
/* Section count badge (e.g., "Image Library (3)") */
.section-count {
    font-weight: 400;
    font-size: var(--font-size-sm);
    opacity: 0.7;
}

/* Library search inside collapsible section */
.sidebar-section-content .library-search {
    padding: 0 var(--space-4) var(--space-3);
}
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | The app loads with no images | The user looks at the left sidebar | "Image Library (0)" header is visible and expanded, "Layout" header is visible and collapsed |
| 2.1.2 | The user clicks the "Layout" chevron in the left sidebar | The click completes | The Layout section expands showing layout style, gutter, and other controls |
| 2.1.3 | The user clicks the "Image Library" chevron in the left sidebar | The click completes | The Image Library section collapses, showing only the header button |
| 2.1.4 | The user changes layout style from the left sidebar | The select changes | The canvas regenerates panels with the new layout (same as before) |
| 2.1.5 | The app loads | The user looks at the right sidebar | Layout section is NOT present; Crop, Background, Overlay, Title, Export are present |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `expandedLeftSections.library` is `true` | `toggleLeftSection('library')` is called | `expandedLeftSections.library` becomes `false` |
| 2.2.2 | `expandedLeftSections.layout` is `false` | `toggleLeftSection('layout')` is called | `expandedLeftSections.layout` becomes `true` |
| 2.2.3 | `leftSidebarSections` has 2 entries | The left sidebar renders | Two collapsible sections are rendered with correct labels |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.1.e.1 | Layout controls are in left sidebar | Navigate, expand Layout section in left sidebar | Layout style select, gutter slider are visible in left sidebar |
| 2.1.e.2 | Layout controls are NOT in right sidebar | Navigate, expand all right sidebar sections | No layout controls appear in right sidebar |
| 2.1.e.3 | Image Library is collapsible | Click Image Library chevron | Section collapses; click again to expand |
| 2.1.e.4 | Layout style change still works | Select different layout from left sidebar | Canvas re-renders with new layout |
| 2.1.e.5 | Image library functions normally | Add images, select, remove | All operations work identically to before |

### Success Criteria:

#### Automated Verification:
- [ ] All existing unit tests pass (no logic changes)
- [ ] E2E tests confirm layout controls are in left sidebar
- [ ] E2E tests confirm layout controls are absent from right sidebar
- [ ] E2E tests confirm collapsible behavior works

#### Manual Verification:
- [ ] Left sidebar sections collapse/expand smoothly
- [ ] Image Library default-expanded, Layout default-collapsed on load
- [ ] Layout controls function identically (style change, gutter, slice angle, hex spacing/size)
- [ ] Keyboard navigation works (Tab through section headers, Enter/Space to toggle)
- [ ] Right sidebar has no layout section
- [ ] No visual regressions in sidebar styling

---

## Phase 3: Title Opacity Controls (Spec 1 - Sub-feature)

### Overview
Add opacity sliders for font color and background color in the Title section. This is an isolated renderer change — no interaction layer, no positioning changes. Validates the `globalAlpha` rendering pipeline before more complex changes.

### Changes Required:

#### 1. Data Model
**File**: `MyESModules/Models/TitleStyle.js` (line 17-26)

Add `fontOpacity` and `bgOpacity` to `createTitleStyle()`:

```javascript
export function createTitleStyle(options = {}) {
    return {
        fontFamily: options.fontFamily || 'Arial',
        fontSize: options.fontSize ?? 36,
        fontColor: options.fontColor || '#FFFFFF',
        backgroundColor: options.backgroundColor || '#000000',
        alignment: options.alignment || 'center',
        showBackground: options.showBackground ?? false,
        fontOpacity: options.fontOpacity ?? 1.0,
        bgOpacity: options.bgOpacity ?? 1.0
    };
}
```

#### 2. TitleManager
**File**: `MyESModules/State/TitleManager.js` (after `showBackground` method, ~line 365)

Add opacity setters:

```javascript
setFontOpacity(opacity) {
    state.titleStyle.fontOpacity = Math.max(0, Math.min(1, opacity));
    notify();
},
setBgOpacity(opacity) {
    state.titleStyle.bgOpacity = Math.max(0, Math.min(1, opacity));
    notify();
}
```

#### 3. TitleRenderer
**File**: `MyESModules/Rendering/TitleRenderer.js` (lines 17-92)

Refactor `render()` to apply opacity via `globalAlpha` with proper `save()`/`restore()`:

```javascript
export function render(ctx, width, height, titleStyle, titleRuns) {
    if (!titleRuns || titleRuns.length === 0) return;

    const fontSize = titleStyle.fontSize || 36;
    const fontFamily = titleStyle.fontFamily || 'Arial';
    const fontColor = titleStyle.fontColor || '#FFFFFF';
    const fontOpacity = titleStyle.fontOpacity ?? 1.0;
    const alignment = titleStyle.alignment || 'center';
    const showBackground = titleStyle.showBackground ?? false;
    const backgroundColor = titleStyle.backgroundColor || '#000000';
    const bgOpacity = titleStyle.bgOpacity ?? 1.0;

    // ... existing measurement code (lines 27-42) ...

    const y = height - MARGIN;
    let startX;
    switch (alignment) {
        case 'left': startX = MARGIN; break;
        case 'right': startX = width - MARGIN - totalWidth; break;
        case 'center': default: startX = (width - totalWidth) / 2; break;
    }

    // Draw background with opacity
    if (showBackground) {
        ctx.save();
        ctx.globalAlpha = bgOpacity;
        ctx.fillStyle = backgroundColor;
        ctx.fillRect(startX - PADDING, y - fontSize - PADDING, totalWidth + PADDING * 2, fontSize + PADDING * 2);
        ctx.restore();
    }

    // Draw text with opacity
    ctx.save();
    ctx.globalAlpha = fontOpacity;
    ctx.textBaseline = 'alphabetic';
    let cursorX = startX;
    for (const mr of measuredRuns) {
        ctx.font = mr.font;
        ctx.fillStyle = fontColor;
        ctx.fillText(mr.text, cursorX, y);
        if (mr.underline) {
            ctx.fillRect(cursorX, y + 2, mr.width, 2);
        }
        cursorX += mr.width;
    }
    ctx.restore();
}
```

#### 4. Title Handlers
**File**: `MyESModules/App/createTitleHandlers.js` (after `onTitleShowBackgroundChange`, ~line 166)

Add opacity change handlers:

```javascript
onTitleFontOpacityChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setFontOpacity(this.titleStyle.fontOpacity);
    }
    onRenderScheduled(this);
},
onTitleBgOpacityChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setBgOpacity(this.titleStyle.bgOpacity);
    }
    onRenderScheduled(this);
}
```

#### 5. Vue Methods
**File**: `MyESModules/App/createCollageMethods.js` (after `onTitleShowBackgroundChange`, ~line 244)

Add opacity method wrappers:

```javascript
onTitleFontOpacityChange() {
    titleHandlers.onTitleFontOpacityChange.call(this);
},
onTitleBgOpacityChange() {
    titleHandlers.onTitleBgOpacityChange.call(this);
},
```

#### 6. Sidebar UI
**File**: `index.html` (in Title section template, after Font Color picker ~line 171, after Background Color picker ~line 177)

Add opacity sliders:

```html
<!-- After Font Color picker -->
<div class="detail-section">
    <label for="titleFontOpacitySlider">Font Opacity: {{ Math.round(titleStyle.fontOpacity * 100) }}%</label>
    <input type="range" id="titleFontOpacitySlider" v-model.number="titleStyle.fontOpacity" min="0" max="1" step="0.01" class="fullRange" @input="onTitleFontOpacityChange">
</div>

<!-- After Background Color picker -->
<div class="detail-section">
    <label for="titleBgOpacitySlider">Bg Opacity: {{ Math.round(titleStyle.bgOpacity * 100) }}%</label>
    <input type="range" id="titleBgOpacitySlider" v-model.number="titleStyle.bgOpacity" min="0" max="1" step="0.01" class="fullRange" @input="onTitleBgOpacityChange">
</div>
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Title text is rendered with default opacity (100%) | The user drags the Font Opacity slider to 50% | The title text renders at 50% opacity (semi-transparent over the collage) |
| 3.1.2 | Title background is visible with default opacity (100%) | The user drags the Bg Opacity slider to 0% | The title background becomes fully transparent; text remains visible |
| 3.1.3 | Font Opacity is at 50% | The user changes the font color | The new color renders at 50% opacity |
| 3.1.4 | Bg Opacity is at 30% | The user changes the background color | The new color renders at 30% opacity |
| 3.1.5 | Both opacities are at 0% | The user looks at the canvas | Neither the title text nor background is visible |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | `titleStyle.fontOpacity` is `0.5` | TitleRenderer.render is called | `ctx.globalAlpha` is set to `0.5` before drawing text, restored after |
| 3.2.2 | `titleStyle.bgOpacity` is `0.3` and `showBackground` is true | TitleRenderer.render is called | Background rect is drawn with `globalAlpha = 0.3` |
| 3.2.3 | `titleStyle.bgOpacity` is `0.0` and `showBackground` is true | TitleRenderer.render is called | Background rect is drawn with `globalAlpha = 0.0` (invisible but still drawn) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.3.1 | `createTitleStyle()` is called with no options | The returned object is inspected | `fontOpacity` is `1.0`, `bgOpacity` is `1.0` |
| 3.3.2 | `createTitleStyle({ fontOpacity: 0.5 })` is called | The returned object is inspected | `fontOpacity` is `0.5`, `bgOpacity` is `1.0` |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.1 | TitleManager.setFontOpacity clamps to [0, 1] | `setFontOpacity(-0.5)` | `titleStyle.fontOpacity` is `0` |
| 3.4.2 | TitleManager.setFontOpacity clamps to [0, 1] | `setFontOpacity(1.5)` | `titleStyle.fontOpacity` is `1` |
| 3.4.3 | TitleManager.setBgOpacity sets value | `setBgOpacity(0.7)` | `titleStyle.bgOpacity` is `0.7` |
| 3.4.4 | TitleRenderer applies font opacity | `fontOpacity: 0.5`, titleRuns with text | `globalAlpha` set to `0.5` before `fillText`, restored after |
| 3.4.5 | TitleRenderer applies bg opacity | `bgOpacity: 0.3`, `showBackground: true` | `globalAlpha` set to `0.3` before `fillRect`, restored after |
| 3.4.6 | TitleRenderer does not leak alpha | `fontOpacity: 0.5` | After render, `globalAlpha` is back to `1.0` (verified via context spy) |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.1.e.1 | Font opacity slider changes rendering | Load images, set title text, drag font opacity to 50% | Title text appears semi-transparent on canvas |
| 3.1.e.2 | Background opacity slider changes rendering | Enable background, drag bg opacity to 0% | Background becomes transparent, text still visible |

### Success Criteria:

#### Automated Verification:
- [ ] Unit tests for opacity setters (clamping, state mutation)
- [ ] Unit tests for TitleRenderer opacity rendering (globalAlpha save/restore)
- [ ] Existing TitleRenderer tests still pass
- [ ] All existing tests pass (no regressions)

#### Manual Verification:
- [ ] Font opacity slider smoothly changes text transparency
- [ ] Background opacity slider smoothly changes background transparency
- [ ] Opacity at 0% makes element invisible but doesn't break rendering
- [ ] Opacity at 100% looks identical to pre-change behavior
- [ ] No alpha leakage to subsequent render pipeline stages

---

## Phase 4: Title Width and Alignment Within Width (Spec 1 - Sub-feature)

### Overview
Add `titleBoxWidth` to the data model. When set, text alignment (left/center/right) is computed within the configured width rather than the canvas width. Extract `computeBounds` as a pure function for use by both renderer and interaction handler.

### Changes Required:

#### 1. Data Model
**File**: `MyESModules/Models/TitleStyle.js`

Add `titleBoxWidth` to `createTitleStyle()`:

```javascript
titleBoxWidth: options.titleBoxWidth ?? null  // null = auto-fit to text content
```

#### 2. TitleManager
**File**: `MyESModules/State/TitleManager.js`

Add width setter:

```javascript
setWidth(width) {
    state.titleStyle.titleBoxWidth = width > 0 ? width : null;
    notify();
}
```

#### 3. TitleRenderer — Extract `computeBounds`
**File**: `MyESModules/Rendering/TitleRenderer.js`

Add pure function (exported for hit testing by interaction handler):

```javascript
/**
 * Computes the bounding box of the title text.
 * Pure function — no side effects, no canvas context needed.
 * @param {Object} titleStyle
 * @param {Array} titleRuns
 * @param {number} width - Canvas width (for right-alignment fallback)
 * @param {number} height - Canvas height
 * @returns {{ x: number, y: number, width: number, height: number, baselineY: number, textWidth: number }}
 */
export function computeBounds(titleStyle, titleRuns, width, height) {
    const fontSize = titleStyle.fontSize || 36;
    const textHeight = fontSize + PADDING * 2;
    const baselineY = height - MARGIN;

    // For measuring, we need a temporary canvas context
    // This is called from render() which has ctx, and from interaction handler
    // Use an offscreen canvas for measurement
    const offscreen = document.createElement('canvas');
    const offCtx = offscreen.getContext('2d');

    let totalWidth = 0;
    for (const run of titleRuns) {
        const fontParts = [];
        if (run.italic) fontParts.push('italic');
        if (run.bold) fontParts.push('bold');
        fontParts.push(fontSize + 'px');
        fontParts.push(titleStyle.fontFamily || 'Arial');
        offCtx.font = fontParts.join(' ');
        totalWidth += offCtx.measureText(run.text).width;
    }

    const boxWidth = titleStyle.titleBoxWidth ?? (totalWidth + PADDING * 2);
    const contentWidth = totalWidth;

    // Compute startX based on alignment within box width
    let startX;
    const alignment = titleStyle.alignment || 'center';
    switch (alignment) {
        case 'left':
            startX = 0; // Relative to box left edge
            break;
        case 'right':
            startX = boxWidth - contentWidth;
            break;
        case 'center':
        default:
            startX = (boxWidth - contentWidth) / 2;
            break;
    }

    return {
        x: 0, // Will be overridden by position logic in render()
        y: baselineY - fontSize - PADDING,
        width: boxWidth,
        height: textHeight,
        baselineY: baselineY,
        textWidth: totalWidth,
        contentStartX: startX, // Offset from box left edge to first character
        boxWidth: boxWidth
    };
}
```

Refactor `render()` to use `computeBounds` and honor `titleBoxWidth`:

```javascript
export function render(ctx, width, height, titleStyle, titleRuns, interactionState) {
    if (!titleRuns || titleRuns.length === 0) return;

    const fontSize = titleStyle.fontSize || 36;
    const fontFamily = titleStyle.fontFamily || 'Arial';
    const fontColor = titleStyle.fontColor || '#FFFFFF';
    const fontOpacity = titleStyle.fontOpacity ?? 1.0;
    const alignment = titleStyle.alignment || 'center';
    const showBackground = titleStyle.showBackground ?? false;
    const backgroundColor = titleStyle.backgroundColor || '#000000';
    const bgOpacity = titleStyle.bgOpacity ?? 1.0;

    // Measure runs
    const measuredRuns = [];
    let totalWidth = 0;
    for (const run of titleRuns) {
        const fontParts = [];
        if (run.italic) fontParts.push('italic');
        if (run.bold) fontParts.push('bold');
        fontParts.push(fontSize + 'px');
        fontParts.push(fontFamily);
        const fontStr = fontParts.join(' ');
        ctx.font = fontStr;
        const w = ctx.measureText(run.text).width;
        measuredRuns.push({ text: run.text, bold: run.bold, italic: run.italic, underline: run.underline, width: w, font: fontStr });
        totalWidth += w;
    }

    // Compute position
    const baselineY = titleStyle.titleBoxY !== null && titleStyle.titleBoxY !== undefined
        ? titleStyle.titleBoxY
        : height - MARGIN;

    const boxWidth = titleStyle.titleBoxWidth ?? (totalWidth + PADDING * 2);

    // Compute text start offset within box (alignment within width)
    let textOffset;
    switch (alignment) {
        case 'left': textOffset = 0; break;
        case 'right': textOffset = boxWidth - totalWidth; break;
        case 'center': default: textOffset = (boxWidth - totalWidth) / 2; break;
    }
    // Clamp textOffset so text doesn't go negative
    textOffset = Math.max(0, textOffset);

    const boxX = titleStyle.titleBoxX !== null && titleStyle.titleBoxX !== undefined
        ? titleStyle.titleBoxX
        : MARGIN; // Default: left-aligned to margin when no custom position

    // When no custom position is set, center the box horizontally
    let effectiveBoxX = boxX;
    if (titleStyle.titleBoxX === null || titleStyle.titleBoxX === undefined) {
        // Default: center the title box in the canvas
        effectiveBoxX = (width - boxWidth) / 2;
    }

    const boxLeft = effectiveBoxX;
    const textStartX = boxLeft + textOffset;

    // Draw background
    if (showBackground) {
        ctx.save();
        ctx.globalAlpha = bgOpacity;
        ctx.fillStyle = backgroundColor;
        ctx.fillRect(boxLeft, baselineY - fontSize - PADDING, boxWidth, fontSize + PADDING * 2);
        ctx.restore();
    }

    // Draw text
    ctx.save();
    ctx.globalAlpha = fontOpacity;
    ctx.textBaseline = 'alphabetic';
    let cursorX = textStartX;
    for (const mr of measuredRuns) {
        ctx.font = mr.font;
        ctx.fillStyle = fontColor;
        ctx.fillText(mr.text, cursorX, baselineY);
        if (mr.underline) {
            ctx.fillRect(cursorX, baselineY + 2, mr.width, 2);
        }
        cursorX += mr.width;
    }
    ctx.restore();

    // Draw interaction outline (if hovering or dragging)
    if (interactionState && (interactionState.hoverTarget || interactionState.interactionMode)) {
        drawInteractionOutline(ctx, boxLeft, baselineY - fontSize - PADDING, boxWidth, fontSize + PADDING * 2, interactionState);
    }
}
```

Add `drawInteractionOutline` helper:

```javascript
function drawInteractionOutline(ctx, x, y, w, h, state) {
    ctx.save();
    ctx.strokeStyle = state.interactionMode ? '#3b82f6' : 'rgba(59, 130, 246, 0.5)';
    ctx.lineWidth = state.interactionMode ? 2 : 1;
    ctx.setLineDash(state.interactionMode ? [] : [4, 4]);
    ctx.strokeRect(x - 2, y - 2, w + 4, h + 4);
    ctx.restore();
}
```

#### 4. CollageAssembler
**File**: `MyESModules/Rendering/CollageAssembler.js` (line 96-98)

Pass interaction state to title renderer:

```javascript
if (titleStyle && titleRuns) {
    renderTitle(ctx, w, h, titleStyle, titleRuns, {
        hoverTarget: options.titleHoverTarget,
        interactionMode: options.titleInteractionMode
    });
}
```

#### 5. Render Methods
**File**: `MyESModules/App/createRenderMethods.js` (in `_scheduleRender`, ~line 52)

Pass title interaction state:

```javascript
asm.render(ctx, {
    // ... existing ...
    titleHoverTarget: vm.titleHoverTarget || null,
    titleInteractionMode: vm.titleInteractionMode || null
});
```

#### 6. Title Handlers
**File**: `MyESModules/App/createTitleHandlers.js`

Add width change handler:

```javascript
onTitleWidthChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setWidth(this.titleStyle.titleBoxWidth);
    }
    onRenderScheduled(this);
}
```

#### 7. Vue Methods
**File**: `MyESModules/App/createCollageMethods.js`

Add width method wrapper.

#### 8. Sidebar UI
**File**: `index.html` (in Title section, after alignment controls)

Add width slider:

```html
<div class="detail-section">
    <label for="titleWidthSlider">Width: {{ titleStyle.titleBoxWidth ? Math.round(titleStyle.titleBoxWidth) : 'Auto' }}</label>
    <input type="range" id="titleWidthSlider" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920" step="1" class="fullRange" @input="onTitleWidthChange">
</div>
```

#### 9. Data Model — Interaction State
**File**: `MyESModules/App/createCollageData.js` (after titleSelectionEnd, ~line 46)

Add interaction state fields:

```javascript
titleHoverTarget: null,       // 'body', 'left-edge', 'right-edge', null
titleInteractionMode: null    // 'drag', 'resize-left', 'resize-right', null
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | Title has text "Hello World" with center alignment and auto width | The user sets width to 400px | The text centers within a 400px-wide background box |
| 4.1.2 | Title has width 400px and center alignment | The user changes alignment to left | The text aligns to the left edge of the 400px box |
| 4.1.3 | Title has width 400px and center alignment | The user changes alignment to right | The text aligns to the right edge of the 400px box |
| 4.1.4 | Title has width 200px and text is wider than 200px | The user looks at the canvas | Text overflows the box (no wrapping or truncation) |
| 4.1.5 | Title has auto width (default) | The user looks at the canvas | Title renders identically to pre-change behavior (centered, auto-fit) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.3.1 | `computeBounds` with `titleBoxWidth: null`, center alignment, text width 200 | Bounds are computed | `boxWidth` is `200 + PADDING*2`, `contentStartX` is `0` (centered within auto box) |
| 4.3.2 | `computeBounds` with `titleBoxWidth: 500`, left alignment, text width 200 | Bounds are computed | `boxWidth` is `500`, `contentStartX` is `0` |
| 4.3.3 | `computeBounds` with `titleBoxWidth: 500`, center alignment, text width 200 | Bounds are computed | `boxWidth` is `500`, `contentStartX` is `150` |
| 4.3.4 | `computeBounds` with `titleBoxWidth: 500`, right alignment, text width 200 | Bounds are computed | `boxWidth` is `500`, `contentStartX` is `300` |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.4.1 | TitleManager.setWidth sets value | `setWidth(400)` | `titleStyle.titleBoxWidth` is `400` |
| 4.4.2 | TitleManager.setWidth nulls invalid | `setWidth(0)` | `titleStyle.titleBoxWidth` is `null` |
| 4.4.3 | TitleManager.setWidth nulls negative | `setWidth(-10)` | `titleStyle.titleBoxWidth` is `null` |
| 4.4.4 | TitleRenderer alignment within width | `titleBoxWidth: 400`, alignment: 'left', text width 100 | Text starts at `boxLeft + 0` |
| 4.4.5 | TitleRenderer alignment within width | `titleBoxWidth: 400`, alignment: 'center', text width 100 | Text starts at `boxLeft + 150` |
| 4.4.6 | TitleRenderer alignment within width | `titleBoxWidth: 400`, alignment: 'right', text width 100 | Text starts at `boxLeft + 300` |
| 4.4.7 | TitleRenderer default (no custom width) | `titleBoxWidth: null`, text width 100 | Renders identically to pre-change behavior |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4.1.e.1 | Width slider changes title box width | Set title text, drag width slider | Background box width changes, text re-aligns |
| 4.1.e.2 | Alignment works within custom width | Set width to 600, change alignment | Text position changes relative to box edges |

### Success Criteria:

#### Automated Verification:
- [ ] `computeBounds` pure function tests pass (all alignment × width combinations)
- [ ] TitleManager width setter tests pass
- [ ] TitleRenderer tests updated for width/alignment within box
- [ ] Existing tests pass (no regressions)

#### Manual Verification:
- [ ] Width slider smoothly changes title box width
- [ ] Alignment buttons reposition text within the configured width
- [ ] Auto width (default) behaves identically to pre-change
- [ ] Width at minimum (100px) still renders
- [ ] Width at maximum (1920px) fills canvas
- [ ] Outline appears on hover (blue dashed rect around title box)

---

## Phase 5: Title Position (Spec 1 - Sub-feature)

### Overview
Add `titleBoxX` and `titleBoxY` to the data model. When set, the title renders at the specified position. Add a "Reset Position" button. No canvas interaction yet — position is set programmatically (for testing and undo support).

### Changes Required:

#### 1. Data Model
**File**: `MyESModules/Models/TitleStyle.js`

Add position fields:

```javascript
titleBoxX: options.titleBoxX ?? null,
titleBoxY: options.titleBoxY ?? null,
```

#### 2. TitleManager
**File**: `MyESModules/State/TitleManager.js`

Add position setters and reset:

```javascript
setPosition(x, y) {
    state.titleStyle.titleBoxX = x;
    state.titleStyle.titleBoxY = y;
    notify();
},
resetPosition() {
    state.titleStyle.titleBoxX = null;
    state.titleStyle.titleBoxY = null;
    state.titleStyle.titleBoxWidth = null;
    notify();
}
```

#### 3. TitleRenderer
**File**: `MyESModules/Rendering/TitleRenderer.js`

The `render()` function from Phase 4 already handles `titleBoxX` and `titleBoxY` (see Phase 4, section 3). No additional changes needed if Phase 4 is complete.

#### 4. Title Handlers
**File**: `MyESModules/App/createTitleHandlers.js`

Add position reset handler:

```javascript
resetTitlePosition() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.resetPosition();
    }
    onRenderScheduled(this);
}
```

#### 5. Vue Methods
**File**: `MyESModules/App/createCollageMethods.js`

Add reset method wrapper:

```javascript
resetTitlePosition() {
    titleHandlers.resetTitlePosition.call(this);
},
```

#### 6. Sidebar UI
**File**: `index.html` (in Title section, after width slider)

Add reset button:

```html
<div class="detail-section">
    <button class="pure-button reset-title-btn" @click="resetTitlePosition">
        <span class="material-icons" style="font-size: 16px; vertical-align: middle; margin-right: 4px;">restart_alt</span>
        Reset Position
    </button>
</div>
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 5.1.1 | Title has been moved to a custom position | The user clicks "Reset Position" | Title returns to default position (bottom-center) with auto width |
| 5.1.2 | Title is at default position | The user clicks "Reset Position" | Title position is unchanged (idempotent) |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 5.2.1 | `titleStyle.titleBoxX` is `null` | TitleRenderer.render is called | Title renders at default position (bottom-center) |
| 5.2.2 | `titleStyle.titleBoxX` is `100`, `titleBoxY` is `200` | TitleRenderer.render is called | Title box renders at (100, 200) in logical canvas coords |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.3.1 | TitleManager.setPosition sets values | `setPosition(100, 200)` | `titleBoxX=100`, `titleBoxY=200` |
| 5.3.2 | TitleManager.resetPosition nulls all | `resetPosition()` | `titleBoxX=null`, `titleBoxY=null`, `titleBoxWidth=null` |
| 5.3.3 | TitleRenderer respects custom position | `titleBoxX=100`, `titleBoxY=200` | Title box drawn at (100, 200) |
| 5.3.4 | TitleRenderer falls back to default | `titleBoxX=null`, `titleBoxY=null` | Title centered at bottom margin |

### Success Criteria:

#### Automated Verification:
- [ ] TitleManager position setter tests pass
- [ ] TitleRenderer position tests pass
- [ ] Existing tests pass

#### Manual Verification:
- [ ] Reset Position button restores title to default position
- [ ] Title at default position looks identical to pre-change behavior

---

## Phase 6: Title Canvas Interaction (Spec 1 - Sub-feature)

### Overview
Create `TitleInteraction.js` — a new interaction handler module that enables click-drag to move the title and edge-drag to resize its width. Follows the `PanelSwap.js` pattern for pointer event handling, with coordination to avoid conflicts with panel swap and gesture handlers.

### Changes Required:

#### 1. New Module
**File**: `MyESModules/Interaction/TitleInteraction.js` (NEW)

```javascript
/**
 * TitleInteraction — Canvas pointer handler for title box manipulation.
 * Supports: drag to move, edge-drag to resize width.
 * Coordinates with PanelSwap to avoid conflicts.
 *
 * @param {Object} options
 * @param {string} options.canvasId - DOM ID of the canvas element
 * @param {Object} options.state - The reactive CollageState
 * @param {Object} options.titleManager - TitleManager instance
 * @param {Function} options.onRenderScheduled - Call to trigger canvas re-render
 * @param {Function} options.onInteractionStart - Called when drag/resize begins
 * @param {Function} options.onInteractionEnd - Called when drag/resize ends
 * @returns {Object} TitleInteractionHandler
 */
export function createTitleInteraction({ canvasId, state, titleManager, onRenderScheduled, onInteractionStart, onInteractionEnd }) {
    let handlerAttached = false;
    let isInteracting = false;
    let interactionType = null; // 'drag', 'resize-left', 'resize-right'
    const DRAG_THRESHOLD = 3;   // CSS pixels
    const EDGE_THRESHOLD = 8;   // CSS pixels for resize handle hit area

    // Placeholder for bound handlers
    let onPointerDown, onPointerMove, onPointerUp, onGlobalPointerUp;

    const handler = {
        attach() { /* ... */ },
        detach() { /* ... */ },
        _clearInteractionState() { /* ... */ },
        _screenToCanvas(e) { /* ... */ },
        _hitTestTitle(x, y, canvasWidth, canvasHeight) {
            // Returns { hit: true, target: 'body' | 'left-edge' | 'right-edge' } or { hit: false }
            // Uses TitleRenderer.computeBounds() to get title bounding box
            // Converts CSS coords to logical coords
            // Checks if point is within EDGE_THRESHOLD of left/right edges
        },
        _onPointerDown(e) {
            // Skip if multi-touch gesture active
            // Skip if no title text
            // Hit-test title box
            // Record start coords, set pointer capture
        },
        _onPointerMove(e) {
            // If not interacting: check hover target, update cursor
            // If interacting: apply delta to position or width
            // Clamp to canvas bounds
            // Schedule render
        },
        _onPointerUp(e) {
            // If was interacting: notify onInteractionEnd
            // Clear state
        }
    };

    // Bind handlers
    onPointerDown = (e) => handler._onPointerDown(e);
    // ... etc
    return handler;
}
```

**Key design decisions:**

1. **Hit testing**: Uses `computeBounds` from TitleRenderer to get the title bounding box in logical canvas coords. Converts CSS pointer coords to logical coords using the same scaling as `PanelSwap._hitTestPanel`.

2. **Interaction modes**:
   - `drag`: Click on title body (not within EDGE_THRESHOLD of edges) → move X/Y
   - `resize-left`: Click within EDGE_THRESHOLD of left edge → shrink/grow width from left
   - `resize-right`: Click within EDGE_THRESHOLD of right edge → shrink/grow width from right

3. **Boundary constraints**:
   - X position: clamped to `[0, canvasWidth - boxWidth]`
   - Y position: clamped to `[fontSize + MARGIN, canvasHeight - MARGIN]`
   - Width: minimum `max(100, textWidth)`, maximum `canvasWidth - 80`

4. **Pointer capture**: `setPointerCapture` on pointerdown, `releasePointerCapture` on pointerup, global `window.addEventListener('pointerup')` safety net.

5. **Coordination with PanelSwap**: PanelSwap's `_onPointerDown` returns early if `state.titleInteractionMode` is non-null. TitleInteraction's `_onPointerDown` returns early if `state._multiTouchGestureActive` is true.

6. **Cursor feedback**: On hover over title body → `move`. On hover over edge → `ew-resize`. On not hovering title → `''` (default).

7. **State updates**: On each pointermove during interaction, calls `titleManager.setPosition(x, y)` or `titleManager.setWidth(w)` and `onRenderScheduled()`.

#### 2. PanelSwap Coordination
**File**: `MyESModules/Interaction/PanelSwap.js` (line 361)

Add guard in `_onPointerDown`:

```javascript
_onPointerDown(e) {
    // Skip if multi-touch gesture is active
    if (state._multiTouchGestureActive) return;
    // Skip if title interaction is active (title box was clicked)
    if (state.titleInteractionMode) return;
    // ... rest of method
}
```

#### 3. Lifecycle Integration
**File**: `MyESModules/App/createCollageLifecycle.js` (after panel swap handler, ~line 135)

```javascript
// Initialize title interaction handler (canvas drag/resize for title box)
this._titleInteraction = createTitleInteraction({
    canvasId: ids.previewCanvas,
    state: this,
    titleManager: this.titleManager,
    onRenderScheduled: () => {
        this._scheduleRender();
    },
    onInteractionStart: () => {
        // Guard against panel swap interference
    },
    onInteractionEnd: () => {
        // Push undo command for position/width change
        // (future: integrate with undo manager)
    }
});
this._titleInteraction.attach();
```

In `beforeUnmount()` (after `_multiTouchHandler.detach()`, ~line 265):

```javascript
if (this._titleInteraction) {
    this._titleInteraction.detach();
}
```

#### 4. Barrel Exports
**File**: `MyESModules/index.js`

Add export:

```javascript
export { createTitleInteraction } from './Interaction/TitleInteraction.js';
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 6.1.1 | Title text is rendered on canvas | The user hovers over the title | A dashed blue outline appears around the title box, cursor changes to `move` |
| 6.1.2 | Title text is rendered on canvas | The user hovers over the left edge of the title | Cursor changes to `ew-resize` |
| 6.1.3 | Title text is rendered on canvas | The user clicks and drags the title body | The title moves with the cursor, outline stays visible |
| 6.1.4 | Title is at some position | The user releases the mouse after dragging | Title stays at new position |
| 6.1.5 | Title text is rendered on canvas | The user clicks and drags the right edge | Title box width increases/decreases, text re-aligns within new width |
| 6.1.6 | Title is being dragged | The user moves cursor outside the canvas | Drag continues (pointer capture), title follows cursor |
| 6.1.7 | Title is at canvas edge | The user drags title further past the edge | Title is clamped to canvas boundary |
| 6.1.8 | User clicks on a panel (not title) | The click completes | Panel is selected (normal behavior, no title interaction) |
| 6.1.9 | Two-finger gesture is active | The user touches the title area | Title interaction is skipped (multi-touch takes priority) |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 6.2.1 | TitleInteraction is attached | Pointer down on title body | `titleInteractionMode` becomes `'drag'`, `titleHoverTarget` becomes `'body'` |
| 6.2.2 | TitleInteraction is in drag mode | Pointer moves 50px right | `titleBoxX` increases by 50 logical pixels |
| 6.2.3 | TitleInteraction is in resize-right mode | Pointer moves 30px right | `titleBoxWidth` increases by 30 logical pixels |
| 6.2.4 | TitleInteraction is in resize-left mode | Pointer moves 20px left | `titleBoxWidth` increases by 20, `titleBoxX` decreases by 20 |
| 6.2.5 | Pointer up after interaction | `_clearInteractionState` is called | `titleInteractionMode` becomes `null`, cursor resets |
| 6.2.6 | `state._multiTouchGestureActive` is true | Pointer down on title | TitleInteraction skips the event |
| 6.2.7 | `state.titleInteractionMode` is `'drag'` | PanelSwap `_onPointerDown` fires | PanelSwap returns early (no panel selection) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 6.3.1 | Hit test on title body | Point within title bounds, not near edges | `{ hit: true, target: 'body' }` |
| 6.3.2 | Hit test on left edge | Point within EDGE_THRESHOLD of left edge | `{ hit: true, target: 'left-edge' }` |
| 6.3.3 | Hit test on right edge | Point within EDGE_THRESHOLD of right edge | `{ hit: true, target: 'right-edge' }` |
| 6.3.4 | Hit test outside title | Point outside title bounds | `{ hit: false }` |
| 6.3.5 | Hit test with no title text | `titleRuns` is empty | `{ hit: false }` |
| 6.3.6 | Drag clamps X to left boundary | `titleBoxX` would go below 0 | `titleBoxX` is clamped to 0 |
| 6.3.7 | Drag clamps X to right boundary | `titleBoxX + boxWidth` would exceed canvas | `titleBoxX` is clamped |
| 6.3.8 | Resize clamps width to minimum | `titleBoxWidth` would go below text width | `titleBoxWidth` is clamped to text width |
| 6.3.9 | Attach/detach | `attach()` then `detach()` | Event listeners added then removed |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 6.1.e.1 | Drag title to new position | Set title, drag title on canvas | Title appears at new position after drag |
| 6.1.e.2 | Resize title width | Set title, drag right edge | Title box width changes |
| 6.1.e.3 | Panel click not affected | Click on a panel | Panel is selected, title is not moved |
| 6.1.e.4 | Drag outside canvas | Start drag on title, move outside canvas, release | Title follows cursor and stays at final position |

### Success Criteria:

#### Automated Verification:
- [ ] TitleInteraction hit test tests pass (all target types)
- [ ] Boundary clamping tests pass
- [ ] Attach/detach tests pass
- [ ] PanelSwap coordination tests pass
- [ ] All existing tests pass

#### Manual Verification:
- [ ] Hover over title shows dashed outline and `move` cursor
- [ ] Hover over edges shows `ew-resize` cursor
- [ ] Drag title moves it smoothly
- [ ] Resize edges change width smoothly
- [ ] Title cannot be dragged off canvas
- [ ] Panel selection still works when clicking outside title
- [ ] Two-finger gestures don't trigger title interaction
- [ ] Drag continues when cursor leaves canvas bounds

---

## Phase 7: Settings Persistence for Title (Spec 1 - Final Polish)

### Overview
Persist new title fields (position, width, opacity) to localStorage and restore them on app load.

### Changes Required:

#### 1. Settings Persistence Defaults
**File**: `MyESModules/Persistence/SettingsPersistence.js` (line 12-28)

Add new fields to `defaultSettings()`:

```javascript
titleFontOpacity: 1.0,
titleBgOpacity: 1.0,
titleBoxX: null,
titleBoxY: null,
titleBoxWidth: null,
```

#### 2. Settings Handlers — Save
**File**: `MyESModules/App/createSettingsHandlers.js` (line 18-36)

Add new fields to `_saveSettings()`:

```javascript
titleFontOpacity: state.titleStyle.fontOpacity,
titleBgOpacity: state.titleStyle.bgOpacity,
titleBoxX: state.titleStyle.titleBoxX,
titleBoxY: state.titleStyle.titleBoxY,
titleBoxWidth: state.titleStyle.titleBoxWidth,
```

#### 3. Settings Handlers — Apply
**File**: `MyESModules/App/createCollageLifecycle.js` (line 295-318)

Add new fields to `_applySavedSettings()`:

```javascript
if (settings.titleFontOpacity !== undefined) this.titleStyle.fontOpacity = settings.titleFontOpacity;
if (settings.titleBgOpacity !== undefined) this.titleStyle.bgOpacity = settings.titleBgOpacity;
if (settings.titleBoxX !== undefined) this.titleStyle.titleBoxX = settings.titleBoxX;
if (settings.titleBoxY !== undefined) this.titleStyle.titleBoxY = settings.titleBoxY;
if (settings.titleBoxWidth !== undefined) this.titleStyle.titleBoxWidth = settings.titleBoxWidth;
```

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 7.1.1 | User sets title opacity to 50% and position to custom | User refreshes the page | Title opacity and position are restored |
| 7.1.2 | User sets title width to 600px | User refreshes the page | Title width is restored to 600px |
| 7.1.3 | User never customizes title position | User refreshes the page | Title is at default position (no saved position) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 7.2.1 | Save includes new fields | State with custom title settings | Saved JSON includes `titleFontOpacity`, `titleBgOpacity`, `titleBoxX`, `titleBoxY`, `titleBoxWidth` |
| 7.2.2 | Load restores new fields | Saved settings with custom values | `titleStyle` fields match saved values |
| 7.2.3 | Load handles missing fields | Old saved settings without new fields | New fields default to `1.0` (opacity) or `null` (position/width) |

### Success Criteria:

#### Automated Verification:
- [ ] Settings persistence tests cover new fields
- [ ] All existing tests pass

#### Manual Verification:
- [ ] Title settings persist across page refresh
- [ ] Old saved settings (without new fields) load without errors
- [ ] Reset Position clears persisted values

---

## Testing Strategy

### Unit Tests

| File | Tests |
|------|-------|
| `TitleRendererTest.html` | Opacity rendering (globalAlpha save/restore), width/alignment within box, position rendering, interaction outline, `computeBounds` pure function |
| `TitleManagerTest.html` | Position setters, width setter, opacity setters, reset position |
| `SettingsPersistenceTest.html` | Save/load with new title fields, backward compatibility |
| **NEW** `TitleInteractionTest.html` | Hit testing (body, left-edge, right-edge, outside), boundary clamping, attach/detach, multi-touch guard |

### E2E Tests (Playwright)

| File | Tests |
|------|-------|
| **NEW** `test/e2e/title-enhancements.spec.js` | Opacity sliders, width slider, alignment within width, drag title, resize title, reset position, panel click not affected |
| **NEW** `test/e2e/sidebar-reorganization.spec.js` | Layout in left sidebar, collapsible sections, image library functionality |
| `test/e2e/landing-page.spec.js` | Home link visibility and attributes |

### Manual Testing Steps

1. **Home Link**: Verify link appears, opens new tab, has correct attributes
2. **Sidebar**: Verify layout controls in left sidebar, collapsible behavior, no layout in right sidebar
3. **Opacity**: Set font opacity to various values, verify text transparency; set bg opacity, verify background transparency
4. **Width**: Set width, verify text re-aligns within box; test all three alignments
5. **Position**: Drag title to various positions, verify it stays; test boundary clamping
6. **Resize**: Drag left and right edges, verify width changes; test minimum width constraint
7. **Persistence**: Set all title options, refresh page, verify all settings restored
8. **Regression**: Verify panel selection, panel swap, crop editing, layout changes all still work

## Performance Considerations

- **`computeBounds`** creates an offscreen canvas for text measurement. This is called once per render cycle. For the interaction handler, it's called on every pointermove during drag — acceptable since it's a single offscreen canvas with no DOM impact.
- **`globalAlpha` save/restore** adds two extra `ctx.save()`/`ctx.restore()` calls per title render. Negligible performance impact.
- **TitleInteraction** hit testing on every pointermove is O(1) — no panel iteration needed.

## Migration Notes

- **Backward compatibility**: All new title fields default to `null` (position/width) or `1.0` (opacity). Existing saved settings without these fields will load with defaults, preserving existing behavior.
- **Settings version**: No version bump needed — `defaultSettings()` merge pattern handles missing fields gracefully.
- **No data migration**: Existing user sessions continue to work without modification.

## References

- Spec 1: `_agent_docs/specifications/2026-07-13-01-title-updates.md`
- Spec 2: `_agent_docs/specifications/2026-07-13-02-move-layout-to-left-sidebar.md`
- Spec 3: `_agent_docs/specifications/2026-07-13-03-link-to-home.md`
- World Review: Session `ses_0a23f0a92ffeEGnCE7hfTipn54`
- Technical Plan: Session `ses_0a23de15fffeP3s6JaIDmhMS9g`
- Pattern reference: `MyESModules/Interaction/PanelSwap.js` (interaction handler pattern)
- Pattern reference: `MyESModules/Rendering/TitleRenderer.js` (current title rendering)
- Skill reference: `building-web-apps` (Canvas 2D `globalAlpha`, Vue 3 Options API, pointer events)
