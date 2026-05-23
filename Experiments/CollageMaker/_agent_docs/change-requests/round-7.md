# Configurable Canvas Size

**Date:** 2026-05-17
**Source:** SOLID review, issue #10 — "Hardcoded canvas size"

## Problem

`CanvasConfig.defaultCanvasSize` is hardcoded to `1920x1080` with no user-facing way to change it. Every layout generation, preview, and export call site references this constant directly. If output resolution becomes a feature requirement, every call site will need updating.

## Current State

- `CanvasConfig.swift` defines `defaultCanvasSize` and `defaultPreviewSize` as static constants
- `LayoutGenerator.generate()` defaults to `CanvasConfig.defaultCanvasSize`
- `CollageViewModel.updatePreview()` and `exportCollage()` hard-reference `CanvasConfig.defaultCanvasSize`
- No persisted setting for canvas size

## Desired End State

- `canvasSize` is a configurable property on `CollageViewModel`
- Persisted to `UserDefaults` (via `SettingsStorage`) alongside other settings
- `LayoutGenerator`, preview, and export all read from the ViewModel's `canvasSize`
- Optional: UI control to select from preset sizes (e.g., 1080p, 4K, A4, Instagram square)

## Scope

- Add `canvasSize: CGSize` to `CollageViewModel`
- Persist via `SettingsStorage` (requires `CGSize` encoding/decoding)
- Pass `canvasSize` through to `LayoutGenerator.generate()`, `updatePreview()`, `exportCollage()`
- Add preset size enum for UI selection (future)
