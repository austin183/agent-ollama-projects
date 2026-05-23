# Panel Swap + Scroll Consistency — Learnings 2026-05-16

**Purpose**: Document learnings from fixing the scroll-after-swap coordinate jump bug (round-5).

---

## What Worked

### Root cause identification via code path audit

The bug was found by tracing the data flow: `swapPanelImages` updates `customImageOrder` and `panelAssignments`, the assembler reads `panelAssignments`, but `CropManager` reads `panel.imageIndex` directly. The mismatch was only visible at runtime during scroll, because the static preview rendered correctly (assembler was right) but scroll clamping used wrong bounds (CropManager was wrong).

### Default parameter preserves backward compatibility

Adding `panelAssignments: [UUID: Int] = [:]` as a default parameter to `CropManager` methods means existing callers (tests, future code) still work with the fallback `panel.imageIndex`. The default only applies when `panelAssignments` is empty or not provided, making the change non-breaking.

## What Didn't Work / Gaps

### Initial fix removed the crop swap

The first pass removed the `sourceRect` swap from `swapPanelImages`, reasoning that "crops are image-specific." This was wrong — the user expects the visual content (the selected portion of an image) to travel with the image when panels swap. The crop swap is correct; the only real bug was `CropManager`'s stale image lookup for clamping bounds.

### `CropManager` operates in isolation from `panelAssignments`

`CropManager` was designed before `panelAssignments` existed. When the permutation layer was added (Session 15, panel drag-to-reorder), `panelAssignments` was wired to the assembler but `CropManager` was overlooked. This is a classic case of a new data layer not being propagated to all consumers.

## What Was Confusing

### Bug manifests as coordinate jump, not wrong image

The wrong image lookup in `CropManager` doesn't cause the preview to show the wrong image — that's controlled by `cropMap` and `panelAssignments` in the assembler. Instead, the wrong image's dimensions produce incorrect clamping bounds (`maxOX`, `maxOY`), so when the user scrolls, the crop origin is clamped to the wrong range and the visible portion jumps to an unexpected position. The symptom (jump) is decoupled from the cause (wrong image dimensions).

### Crop swap vs crop independence

There's a subtle distinction:
- `CropInfo.sourceRect` — coordinates within the source image (what portion is visible) — **travels with the image** on swap
- `CropInfo.destinationRect` — panel position on canvas (where it's drawn) — **stays with the panel** on swap
- `panel.imageIndex` — the original image assignment — **becomes stale** after swap
- `panelAssignments[panelId]` — the effective image assignment — **stays current** after swap

## New Patterns Not Previously Documented

### All consumers of slot-to-content mapping must use the same resolution path

**Rule**: When a mapping layer exists between UI slots and content (e.g., `panelAssignments: [UUID: Int]` mapping panel IDs to image indices), every code path that resolves "which content belongs to this slot?" must use the mapping, not the slot's raw property.

**Resolution pattern**: `effectiveIndex = mapping[slotId] ?? slot.defaultIndex`

**Affected code paths in this app**:
- `CollageAssembler.drawPanels()` — uses `panelAssignments[panel.id] ?? panel.imageIndex` (was correct)
- `CropManager.applyPan()` — now uses `panelAssignments[id] ?? panel.imageIndex` (was wrong, fixed)
- `CropManager.applyPinch()` — now uses `panelAssignments[id] ?? panel.imageIndex` (was wrong, fixed)
- `CropManager.resetCrop()` — now uses `panelAssignments[panelId] ?? panel.imageIndex` (was wrong, fixed)

### Stale slot property is a latent bug waiting for the right interaction

`panel.imageIndex` is never updated after layout generation. Before the permutation layer, this was fine — the index was always correct. After `customImageOrder` and `panelAssignments` were added, the index became stale for swapped panels, but the bug was invisible until a code path that still used `panel.imageIndex` was exercised with a swapped panel. The preview path (assembler) was correct, so the bug only surfaced during scroll/pan operations.

## Skill Improvements

### `building-swiftui-macos-apps/SKILL.md` — Permutation-Based Content Reordering

Add a "Consumer consistency" note to the existing permutation section:
- When adding a mapping layer (`panelAssignments`), audit ALL code paths that look up content by slot
- Use the resolution pattern `mapping[slotId] ?? slot.defaultIndex` consistently
- A stale slot property (`panel.imageIndex`) is a latent bug until exercised

---
**Status**: Closed
**Follow-up**: Run tests to confirm no regression; manual test scroll after swap with images of different dimensions
