# Session 12 — 2026-05-14

### Bug Fixes: Background image rendering, gradient coverage, live preview updates

**Goal:** Fix remaining image update issues from round-1 bug report: background image not appearing, gradient not covering full canvas, gradient angle/colors not updating live.

**Bugs Discovered and Fixed:**

1. **Gradient doesn't extend fully across canvas** — `CollageAssembler.swift:307`. The gradient line length was computed as `min(size.width, size.height) / 2` from center in each direction, producing a line too short to reach the corners of a rectangular canvas (e.g., 1920x1080). Fixed by using the true diagonal: `CGFloat(sqrt(w*w + h*h)) / 2`, ensuring full coverage at any angle.

2. **Gradient angle, gradient colors, background opacity don't trigger preview** — `CollageViewModel.swift`. The `didSet` observers for `gradientAngle`, `gradientStartColor`, `gradientEndColor`, and `backgroundOpacity` only persisted to `UserDefaults` but never called `updatePreview()`. Fixed by adding `updatePreview()` to each `didSet`.

3. **Title changes don't trigger preview** — `CollageViewModel.swift:67`. The `title` property's `didSet` persisted to `UserDefaults` but didn't call `updatePreview()`. Fixed by adding `updatePreview()` to the `didSet`.

4. **Background image never appears (opacity=0)** — `CollageViewModel.swift:143`. `UserDefaults.standard.double(forKey:)` returns `0.0` when the key doesn't exist, so `backgroundOpacity` initialized to `0`. The image was being drawn correctly but at 0% opacity — completely invisible. Fixed by checking if the UserDefaults key exists first, defaulting to `1.0` (fully opaque) when it doesn't.

5. **Background image `NSImage` → `CGImage` extraction on background thread** — `CollageViewModel.swift` + `CollageAssembler.swift`. The `backgroundImage` (`NSImage?`) was captured and passed into `Task.detached` (background thread), where `NSImage.cgImage(forProposedRect:)` was called. `NSImage` is an AppKit class requiring main-thread access — calling `cgImage(forProposedRect:)` on a background thread can silently return `nil`. Fixed by extracting the `CGImage` on the main thread in `updatePreview()` and `exportCollage()` before the detached task, then passing `CGImage?` through the assembly pipeline instead of `NSImage?`. Updated protocol, implementation, and test mock signatures accordingly.

6. **Redundant `.onChange` in ExportPanel** — `ExportPanel.swift:102-104`. The `.onChange(of: viewModel.backgroundStyle)` block calling `updatePreview()` was redundant since `backgroundStyle.didSet` now handles it. Removed.

**Production Code Changes:**
- `ViewModel/CollageViewModel.swift` — Added `updatePreview()` to `didSet` of `title`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundOpacity`. Fixed `backgroundOpacity` default from `0.0` to `1.0`. Changed `backgroundImage` capture to extract `CGImage` on main thread before `Task.detached`. Updated both `updatePreview()` and `exportCollage()`.
- `Services/CollageAssembler.swift` — Changed gradient line length from `min(w,h)/2` to true diagonal. Updated `assembleWithCGImages` and `assemblePreviewWithCGImages` signatures to accept `CGImage?` instead of `NSImage?` for background image. Updated delegate methods to extract `CGImage` from `NSImage?` before delegating.
- `Views/ExportPanel.swift` — Removed redundant `.onChange(of: viewModel.backgroundStyle)`.
- `CollageMakerTests/CollageViewModelTests.swift` — Updated `MockAssembler` protocol conformance to match new `CGImage?` signatures.

**Telemetry Used:**
- Added targeted `Logger` statements to `ExportPanel.chooseBackgroundImage()`, `CollageViewModel.updatePreview()`, and `CollageAssembler.drawImageBackground()` to trace the pipeline
- Logs revealed `opacity=0.000000` as the root cause of invisible background image
- All debug logging cleaned up after diagnosis

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **68 tests pass** (unchanged)
- Background image: **Fixed** (appears in preview at correct opacity)
- Gradient coverage: **Fixed** (extends fully across canvas at any angle)
- Gradient controls: **Fixed** (angle, colors update live)
- Title: **Fixed** (updates live — from Session 11)

**Learnings Documented:**
- `_agent_docs/learnings/background-image-rendering-pipeline-learnings.md`
