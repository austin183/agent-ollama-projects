# Sandbox File Access — Test Bootstrap Gotcha

**Date:** 2026-06-19
**Context:** UI automation Phase 1 — CLI image loading for automated tests

## Problem

A sandboxed macOS app (`ENABLE_APP_SANDBOX = YES`) cannot read arbitrary directories via `FileManager.default.contentsOfDirectory()`, even when the path is valid and the directory exists. The call silently returns `nil` (caught by `try?`), with no error or crash.

This blocks test infrastructure that uses environment variables to specify a test fixture directory (e.g., `COLLAGEMAKER_TEST_IMAGES_DIR=/path/to/TestImages`).

## Root Cause

The macOS app sandbox restricts file system access to:
- The app's own bundle
- User-selected locations (via `NSOpenPanel`/`NSSavePanel`)
- Designated containers (Application Support, Documents, etc.)
- Temporary directory

An arbitrary path from an environment variable is none of these — it's outside the sandbox.

## Fix

Disable the sandbox for Debug builds by setting `ENABLE_APP_SANDBOX = NO` in the Debug build configuration of `project.pbxproj`:

```
D941DEB92FB0ED2B00B1C1C2 /* Debug */ = {
    isa = XCBuildConfiguration;
    buildSettings = {
        ENABLE_APP_SANDBOX = NO;  // was YES
        ...
    };
};
```

Release builds retain the sandbox for production safety.

## Debugging Clues

- `FileManager.default.contentsOfDirectory(at:)` returns `nil` for a path you can verify exists
- No crash, no exception — just silent `nil`
- Works in Xcode debug runs if you disable sandbox in scheme settings
- `log show` confirms the path is correct but the read failed
- `os_sandbox` subsystem logs may show access denied events

## Prevention

- When building test infrastructure that reads files from arbitrary paths, disable sandbox for Debug builds
- Use absolute paths in environment variables — `open` launches the app with `~` as the working directory, not the project root
- Add `OSLog` at the file discovery boundary to surface the failure mode (path correct but read failed vs path wrong)

## Related

- `PBXFileSystemSynchronizedRootGroup` auto-discovers files from the filesystem — no manual `pbxproj` edits needed for new source files
- `open` with env vars: `MY_VAR=value open app.app` passes the env var to the launched process
