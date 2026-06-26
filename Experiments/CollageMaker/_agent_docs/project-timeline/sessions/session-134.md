# Session 134 — UI Test Resource Path Fix

**Date:** 2026-06-26
**Plan:** `2026-06-24-visual-validation-automation.md` Phase 1 (follow-up)

## Summary

Fixed UI test failures in Xcode caused by `TestImages` not being bundled with UITest targets. The `testImagesDirectory()` method in both `CollageMakerTitleTests.swift` and `CollageMakerSnapshotTests.swift` used a fragile chain of `deletingLastPathComponent()` calls to navigate from the DerivedData test bundle path back to the source tree. This path is always invalid — the test bundle lives in DerivedData, not the source tree. Resources must be copied into the bundle at build time and accessed via `Bundle` APIs.

## Changes

### `project.pbxproj` — 4 edits

1. Added `PBXFileReference` for `TestImages` (type `folder`, path `../TestImages`)
2. Added `PBXBuildFile` to include it in the UITest bundle's Resources phase
3. Added `TestImages` to the main `PBXGroup` children
4. Added the build file to the UITests `PBXResourcesBuildPhase` (`D941DEAC2FB0ED2B00B1C1C2`)

This copies `TestImages/` into `CollageMakerUITests.xctest/Contents/Resources/TestImages/` at build time.

### `CollageMakerTitleTests.swift` & `CollageMakerSnapshotTests.swift`

Replaced the 14-line `testImagesDirectory()` method with a single line:
```swift
Bundle(for: Self.self).url(forResource: "TestImages", withExtension: nil)!.path
```

## Verification

- Build: succeeded
- `TestImages` confirmed present in UITest bundle's `Contents/Resources/` after `build-for-testing`
- Unit tests: 449 pass (no regressions)
- User confirmed UI tests pass in Xcode

## New Learnings

- `uitest-bundle-resource-discovery.md` — how to properly bundle and discover test resources in UITest targets

---
**Status**: Complete
**Follow-up**: None — one-shot infrastructure fix
