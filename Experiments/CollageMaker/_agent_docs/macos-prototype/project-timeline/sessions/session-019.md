# Session 19 — 2026-05-15

### Round 4.2: Panel Swap Overlay Coordinate Fix

**Goal:** Fix the overlay coordinate issue from round-4.2: when two panels are swapped via drag-and-drop, the crop coordinates (`sourceRect`) should swap along with the images so the selected portion of each image stays visually consistent.

**Bug Discovered and Fixed:**

1. **Crop coordinates stay with panel slot instead of traveling with image** — `CollageViewModel.swift:391-399`. The `cropMap` is keyed by `panelId` (UUID), so when `swapPanelImages()` swapped image assignments between two panels, the crop entries remained bound to their original panel slots. After swap, Panel A displayed image 1 but used the crop tuned for image 0, and Panel B displayed image 0 but used the crop tuned for image 1. Fixed by swapping the `sourceRect` values between the two panels' `CropInfo` entries in `swapPanelImages()`, while preserving each panel's own `destinationRect` (canvas position).

**Root Cause:**
- `CropInfo.sourceRect` stores coordinates within the source image (what portion of the image is visible)
- `CropInfo.destinationRect` stores the panel's canvas position (where it's drawn)
- When panels swap images, `sourceRect` should travel with the image, but `destinationRect` should stay with the panel slot
- The original `swapPanelImages()` only swapped image assignments, not crop data

**Production Code Changes:**
- `ViewModel/CollageViewModel.swift` — `swapPanelImages()` now swaps `sourceRect` between the two panels' `CropInfo` entries, reconstructing each with the target's `sourceRect` and its own `destinationRect`. Handles the case where one or both panels may not have a crop entry (no-op when crop is absent).

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **Not yet re-run** (no test-impacting changes)
- Panel swap with crop: **Fixed** (sourceRect travels with image, destinationRect stays with panel)
