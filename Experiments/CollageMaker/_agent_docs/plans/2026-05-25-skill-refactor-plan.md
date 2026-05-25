# Refactor `building-macos-apps` Skill — Smaller Chunks, Clearer References

## Problem

The `building-macos-apps` skill has grown to 35 reference files (6,210 lines total) under a flat `references/` directory. Issues:

1. **Two files exceed the 500-line best-practice limit:**
   - `swiftui-gestures.md` — 669 lines
   - `nsviarepresentable.md` — 512 lines

2. **Multi-concern files** (named for one topic, contain others):
   - `combine-published.md` — @Published patterns, but also contains drag-and-drop snippets, PhotosPicker, NSOpenPanel, NSSavePanel
   - `nsviarepresentable.md` — core protocol, but also NSTextView binding and NSColorWell wrapping
   - `swiftui-gestures.md` — gesture APIs, but also resize handle patterns (edge, corner, aspect ratio)

3. **Flat directory with 35 files** is becoming hard to navigate and reason about.

## Decision: Keep as Single Skill

The skill covers a coherent domain (macOS SwiftUI app development). Splitting into multiple skills would fragment related knowledge and hurt discovery. The description is already well-targeted.

## Plan

### Phase 1 — Create Subdirectories

Restructure `references/` into domain-grouped subdirectories:

```
references/
  ui/              — SwiftUI UI patterns
  gestures/        — Gesture handling
  appkit/          — AppKit interop, NSViewRepresentable
  state/           — State management (@Observable, @Published, concurrency)
  graphics/        — Image processing, CoreGraphics, Vision, vImage
  testing/         — Testing patterns
  conventions/     — HIG, desktop conventions
  tooling/         — Build, run, debug, windowing, commands, settings
```

### Phase 2 — Split Oversized Files

#### `swiftui-gestures.md` (669 lines) → 3 files

| New file | Content | Approx. lines |
|---|---|---|
| `gestures/swiftui-gestures.md` | Core gesture APIs, location/coordinate space, composition (simultaneous/sequenced/exclusive), gesture mask, MagnificationGesture basics | ~150 |
| `gestures/gesture-targeting.md` | Per-panel hit testing (Approach 1 recommended, Approach 2 known issue, Approach 4 rejected), multiple coexisting gestures, overlapping hit regions, preemptive exclusion, ghost cursor overlay | ~250 |
| `gestures/resize-handles.md` | Edge-based resize handle, corner-based resize with aspect ratio, dominant-dimension pattern, uniform bounding box, corner hit detection, minimum width from natural text bounds | ~200 |

#### `nsviarepresentable.md` (512 lines) → 3 files

| New file | Content | Approx. lines |
|---|---|---|
| `appkit/nsviarepresentable.md` | Protocol requirements, basic pattern, gesture recognizer integration with Coordinator, closure-based API alternative, AppKit/SwiftUI coordinate mismatch, NSView transparency, scroll input capture | ~200 |
| `appkit/nstextview-binding.md` | NSTextView with NSAttributedString binding, isEqual for cursor preservation, textDidChange not firing for attributes, re-entrancy cascade trap, ObservableObject holder | ~180 |
| `appkit/nscolorwell.md` | NSColorWell wrapping, color equality trap, alpha handling | ~50 |

### Phase 3 — Extract Miscellany

#### From `combine-published.md` → `ui/file-input.md`

Extract the drag-and-drop snippets, PhotosPicker (JPEG support), NSOpenPanel for folder browse, and NSSavePanel for export into a new `ui/file-input.md` file. These are file I/O operations, not Combine patterns.

### Phase 4 — Move Remaining Files to Subdirectories

| Current file | New location |
|---|---|
| `scroll-views.md` | `ui/scroll-views.md` |
| `swiftui-overlays.md` | `ui/swiftui-overlays.md` |
| `split-inspectors.md` | `ui/split-inspectors.md` |
| `cgrect-equality-crop-lookup.md` | `ui/cgrect-equality-crop-lookup.md` |
| `drag-and-drop.md` | `gestures/drag-and-drop.md` |
| `appkit-interop.md` | `appkit/appkit-interop.md` |
| `nsattributedstring-drawing.md` | `appkit/nsattributedstring-drawing.md` |
| `codable-appkit.md` | `appkit/codable-appkit.md` |
| `observable-bindable.md` | `state/observable-bindable.md` |
| `combine-published.md` | `state/combine-published.md` |
| `focused-values.md` | `state/focused-values.md` |
| `swift-concurrency.md` | `state/swift-concurrency.md` |
| `coreimage-filters.md` | `graphics/coreimage-filters.md` |
| `vision-api-details.md` | `graphics/vision-api-details.md` |
| `vimage-processing.md` | `graphics/vimage-processing.md` |
| `coordinate-systems.md` | `graphics/coordinate-systems.md` |
| `testing-patterns.md` | `testing/testing-patterns.md` |
| `desktop-conventions.md` | `conventions/desktop-conventions.md` |
| `hig-accessibility.md` | `conventions/hig-accessibility.md` |
| `hig-alerts-feedback.md` | `conventions/hig-alerts-feedback.md` |
| `hig-keyboard-shortcuts.md` | `conventions/hig-keyboard-shortcuts.md` |
| `hig-context-menus.md` | `conventions/hig-context-menus.md` |
| `hig-progress-indicators.md` | `conventions/hig-progress-indicators.md` |
| `hig-undo-redo.md` | `conventions/hig-undo-redo.md` |
| `hig-sidebars.md` | `conventions/hig-sidebars.md` |
| `build-and-run.md` | `tooling/build-and-run.md` |
| `commands-menus.md` | `tooling/commands-menus.md` |
| `settings.md` | `tooling/settings.md` |
| `windowing.md` | `tooling/windowing.md` |
| `window-management.md` | `tooling/window-management.md` |
| `menu-bar-extra.md` | `tooling/menu-bar-extra.md` |
| `file-export-import.md` | `ui/file-export-import.md` |

### Phase 5 — Update SKILL.md

1. Update all reference links in the reference table to new paths
2. Update all inline cross-references (e.g., "See [references/coordinate-systems.md]" → "See [references/graphics/coordinate-systems.md]")
3. Remove `components-index.md` if it's just a duplicate of the SKILL.md table
4. Verify the SKILL.md body stays under 500 lines

### Phase 6 — Update AGENTS.md

The AGENTS.md file references several reference files. Update paths:
- `references/testing-patterns.md` → `references/testing/testing-patterns.md`
- `references/build-and-run.md` → `references/tooling/build-and-run.md`
- `references/coordinate-systems.md` → `references/graphics/coordinate-systems.md`

### Phase 7 — Verify Internal Cross-References

Any reference file that links to another reference file needs its relative paths updated. Key links to check:
- `nsviarepresentable.md` → `scroll-views.md` (new: `../ui/scroll-views.md`)
- `swiftui-gestures.md` → `nsviarepresentable.md` (new: `../appkit/nsviarepresentable.md`)
- `swiftui-gestures.md` → `coordinate-systems.md` (new: `../graphics/coordinate-systems.md`)
- Any other inter-file references

## Execution Order

1. Create subdirectories
2. Split oversized files (write new files first, then delete originals)
3. Extract miscellany from `combine-published.md`
4. Move remaining files to subdirectories
5. Update SKILL.md reference table and inline links
6. Update AGENTS.md paths
7. Fix internal cross-references between reference files
8. Delete `components-index.md` if redundant
9. Verify: `find references/ -name "*.md" | wc -l` should still be ~36 (35 original + 1 new file-input, minus consolidation)
