# Session 117 — UI Automation Phase 1: CLI Image Loading & Sandboxed File Access

**Date:** 2026-06-19
**Plan:** `_agent_docs/plans/2026-06-19-ui-automation-cli-loading.md` (Phase 1)

## Summary

Implemented Phase 1 of the UI automation plan: CLI image loading via environment variable, enabling automated tests to launch the app with pre-loaded images from a known state.

First launch failed silently — the app started but images did not load. Debugging with `OSLog` revealed `TestBootstrap.loadTestImageURLs()` was returning `nil` because the sandboxed app could not read the `TestImages` directory. Fix: disabled the app sandbox for Debug builds (`ENABLE_APP_SANDBOX = NO` in `project.pbxproj`).

## Changes

### New file — `TestBootstrap.swift`
- Reads `COLLAGEMAKER_TEST_IMAGES_DIR` environment variable
- Scans directory for image files (`.jpg`, `.jpeg`, `.png`, `.tiff`, `.heic`, `.heif`)
- Returns sorted `[URL]` or `nil` if env var not set or directory unreadable
- Added `OSLog` for debugging file discovery

### Modified — `CollageMakerApp.swift`
- Added `.task` modifier on `ContentView` that calls `viewModel.clearAll()` then `await viewModel.addImages(from: urls)` when test URLs are present
- Zero impact on normal usage (env var not set in production)

### Modified — `script/build_and_run.sh`
- Added `--test` mode that launches with `COLLAGEMAKER_TEST_IMAGES_DIR` set to absolute path of `TestImages/`
- Fixed duplicate `--telemetry` case block
- Updated usage string

### Modified — `project.pbxproj`
- Set `ENABLE_APP_SANDBOX = NO` for Debug builds to allow reading arbitrary directories via env var

## Debugging Notes

- `FileManager.default.contentsOfDirectory` returned `nil` for a valid path because the sandboxed app had no permission to access the directory
- `log show --predicate 'process == "CollageMaker" and category == "TestBootstrap"'` confirmed the path was correct but the directory read failed
- Relative paths in `open` env vars resolve relative to the shell's working directory, not the app's — use absolute paths

## Verification

- `xcodebuild build` — Succeeded
- `COLLAGEMAKER_TEST_IMAGES_DIR=... open ...` — App launched with 5 images loaded automatically
- Logs confirmed: "Found 5 test image(s)" → "Added 5 image(s); total count 5" → saliency analysis complete

## Files Changed

| File | Change |
|------|--------|
| `CollageMaker/TestBootstrap.swift` | **New** — env var reader, ~35 lines |
| `CollageMaker/CollageMakerApp.swift` | `.task` modifier, +5 lines |
| `script/build_and_run.sh` | `--test` mode, fixed duplicate case, +5 lines |
| `CollageMaker.xcodeproj/project.pbxproj` | `ENABLE_APP_SANDBOX = NO` for Debug |

## New Learnings

Created `_agent_docs/learnings/sandbox-file-access-test-bootstrap.md` — documents the macOS sandbox blocking `FileManager` access to arbitrary directories, and the pattern of disabling sandbox for Debug builds when test infrastructure requires file system access outside the app's sandbox containers.

---
**Status:** Complete
**Follow-up:** Phase 2 (UI tests) pending user direction.
