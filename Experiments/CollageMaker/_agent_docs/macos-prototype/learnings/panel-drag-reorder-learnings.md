# Panel Drag-to-Reorder — Learnings 2026-05-14

**Purpose**: Document learnings from implementing Phase 3 of Round 3 — canvas-level panel drag-to-reorder with visual feedback.

---

## What Worked

### Permutation-based image-to-panel decoupling

Using `customImageOrder: [Int]` as a permutation array cleanly separates panel slot positions from which image occupies each slot. The key insight: `LayoutGenerator` maps slot `i` → `imageOrder[i]`, so panels never change their `imageIndex` when reordering — only the permutation array changes. This avoids the complexity of mutating panel frames or rebuilding layouts on every swap.

### Plan accuracy

The plan's three-file scope (`CollageViewModel`, `LayoutGenerator`, `CollageEditorView`) was accurate. No files were missed, and the data flow (ViewModel state → LayoutGenerator mapping → EditorView gesture → ViewModel swap → preview update) matched the implementation exactly.

### Gesture coexistence

Three `simultaneousGesture` DragGestures now coexist on the same ZStack:
1. Title drag (locks on title frame hit-test)
2. Panel reorder drag (locks on panel hit-test)
3. Scroll pan (via `NSViewRepresentable` overlay, different input modality)

Each uses a `@State` locking flag to prevent re-locking mid-gesture. The panel reorder gesture guards against title drag with `guard !viewModel.isDraggingTitle else { return }`, ensuring the title gesture wins when both could fire.

## What Didn't Work / Gaps

### `moveImages` permutation math

When the sidebar image order changes, `customImageOrder` must be remapped so the canvas layout stays stable. The inverse permutation (`buildMoveMapping`) computes "where did position `i` come from after the move?" for each index. This is error-prone and hard to verify without tests. The implementation handles the two cases (`to < fromFirst` vs `to >= fromFirst`) but there's no unit test coverage for this path.

### No live swap preview

The current implementation only calls `updatePreview()` in `onEnded`, after the swap is committed. A live preview during drag (showing the target panel with the source image) would require swapping `panelAssignments` temporarily during `onChanged`, then re-swapping on cancel — adding complexity for marginal UX gain.

### `LayoutKey` struct growing

The `LayoutKey` struct in `CollageEditorView` now has 8 properties (width, height, panel IDs, crop keys, title frame X/Y/W/H). Each time a new canvas overlay is added, `LayoutKey` grows. This is a smell — the frame cache invalidation logic is becoming a maintenance burden.

## New Patterns Not Previously Documented

### Multiple DragGestures with distinct hit-test targets

**Previously documented**: Single DragGesture with one hit-test target (panel or title).
**New**: Multiple `simultaneousGesture` DragGestures on the same ZStack, each with its own hit-test region and locking flag. Key rules:
- Each gesture uses `startLocation` on first `onChanged` to determine its target
- A `@State` flag (`dragTitleLocked`, `dragSourcePanelId`) prevents re-locking mid-gesture
- Cross-gesture guards (`isDraggingTitle`) prevent the wrong gesture from activating
- `minimumDistance: 5` on all drag gestures prevents tap-to-select conflict

### Permutation array for slot-to-content mapping

**Pattern**: When UI elements have fixed positions (panel slots) but variable content (images), maintain a `[Int]` permutation where `order[slot] = contentIndex`. Swapping content between two slots is a single `swapAt()` call. This avoids:
- Rebuilding the layout (panel frames stay the same)
- Updating crop state (crops are keyed by panel UUID, not image index)
- Complex index remapping (the permutation is the source of truth)

**Persistence**: JSON-encode the `[Int]` array to UserDefaults. Reset to `Array(0..<count)` when content count changes.

### Ghost cursor overlay pattern

**Pattern**: During a drag-to-reorder gesture, show a semi-transparent thumbnail of the dragged content following the cursor. Implementation:
- `@State dragCursorLocation: CGPoint?` updated in `onChanged`
- `@State dragSourceImageIndex: Int` captured at gesture start
- `Image(nsImage: thumbnail)` with `.opacity(0.7)` positioned at cursor location
- Thumbnail is the pre-generated 64x64 `ImageItem.thumbnail`, not the full-resolution image

**Visual feedback strokes**: Cyan on source panel, green on target panel, both using `.stroke(Color, lineWidth: 2.5)` on clear rectangles positioned at the panel's scaled frame.

### `panelAssignments` as the bridge between permutation and rendering

The `panelAssignments: [UUID: Int]` dict maps each panel UUID to its current image index. `regenerateLayout()` populates it from `customImageOrder`, and `swapPanelImages()` updates the two affected entries. The assembler reads `panelAssignments` for rendering, so the permutation never needs to reach the assembler layer.

## Skill Improvements

### `building-swiftui-macos-apps/REFERENCES/swiftui-gestures.md`

Add a section on "Multiple Coexisting DragGestures":
- Pattern for multiple `simultaneousGesture` DragGestures on the same parent
- Locking flags and cross-gesture guards
- Hit-test region isolation via `startLocation`

### `building-swiftui-macos-apps` main skill

Add "Permutation-based content reordering" to the state management or anti-patterns section:
- When to use a permutation array vs direct array mutation
- How `panelAssignments` bridges the permutation to the rendering layer
- Resetting the permutation when content count changes

## Next Steps

- Add unit tests for `swapPanelImages()` and `buildMoveMapping()`
- Consider live swap preview (temporary `panelAssignments` swap during `onChanged`)
- Evaluate whether `LayoutKey` should be replaced with a more targeted invalidation strategy

---
**Status**: Closed
**Follow-up**: Round 3 plan is now complete (Phases 1, 2, 3 implemented). Next: manual testing of all three phases.
