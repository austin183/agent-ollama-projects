# UITest Bundle Resource Discovery

**Date:** 2026-06-26
**Context:** Fixing UI test failures — `TestImages` directory not accessible from UITest bundle

## Problem

XCUIAutomation tests need test fixture files (images, data, etc.) accessible to the launched app. The initial approach tried to locate `TestImages/` by walking up the directory tree from `Bundle(for: Self.self).bundleURL` using chains of `deletingLastPathComponent()`. This always fails because:

1. The UITest bundle lives in DerivedData (`~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/...`)
2. Walking up from DerivedData never reaches the source tree
3. The path depth varies by Xcode version and project configuration

## Root Cause

Resources are not automatically copied into test bundles. Unlike the main app target (which has a Resources build phase), UITest targets start with an empty Resources phase. Files must be explicitly added as folder references and build files in `project.pbxproj`.

## Fix

### Step 1: Add folder reference to `project.pbxproj`

Four edits are needed:

1. **`PBXFileReference`** — Add a folder reference pointing to the resource directory relative to the project:
   ```
   TESTIMAGES_REF /* TestImages */ = {isa = PBXFileReference; lastKnownFileType = folder; name = TestImages; path = ../TestImages; sourceTree = "<group>"; };
   ```

2. **`PBXBuildFile`** — Create a build file for the reference:
   ```
   TESTIMAGES_BUILD /* TestImages in Resources */ = {isa = PBXBuildFile; fileRef = TESTIMAGES_REF /* TestImages */; };
   ```

3. **`PBXGroup`** — Add the reference to the project's main group children so it appears in Xcode's navigator.

4. **`PBXResourcesBuildPhase`** — Add the build file to the UITest target's Resources phase:
   ```
   UITests_Resources /* Resources */ = {
       isa = PBXResourcesBuildPhase;
       files = (
           TESTIMAGES_BUILD /* TestImages in Resources */,
       );
   };
   ```

### Step 2: Use `Bundle` API to discover resources

Replace fragile path navigation with:
```swift
Bundle(for: Self.self).url(forResource: "TestImages", withExtension: nil)!.path
```

The `withExtension: nil` is key — it finds a folder resource, not a file with an extension.

## Result

After a `build-for-testing`, `TestImages/` is copied to:
```
DerivedData/.../Build/Products/Debug/UITestRunner.app/Contents/PlugIns/UITests.xctest/Contents/Resources/TestImages/
```

The `Bundle(for:).url(forResource:withExtension:)` API finds it reliably regardless of DerivedData path structure.

## Debugging Clues

- `FileManager.default.fileExists(atPath:)` returns `false` for a path constructed from `Bundle(for:).bundleURL.deletingLastPathComponent()` chains
- The fallback path in a `candidates` array is always the last one tried, and it's always wrong
- `ls` on the actual test bundle shows no `TestImages/` in `Contents/Resources/`
- Building with `build-for-testing` (not just `build`) is needed to compile the UITest target

## Prevention

- Always use `Bundle(for:).url(forResource:withExtension:)` to locate bundled resources — never navigate up from `bundleURL`
- Add test fixture directories as folder references in the UITest target's Resources build phase
- Use `build-for-testing` to verify resources are copied, not just `build`
- For `project.pbxproj` edits, verify with `ls` on the built bundle's `Contents/Resources/` directory

## Related

- `xcuiautomation-macos-api-gotchas.md` — XCUIAutomation API differences in macOS SDKs
- `sandbox-file-access-test-bootstrap.md` — Debug builds need sandbox disabled for test file access
