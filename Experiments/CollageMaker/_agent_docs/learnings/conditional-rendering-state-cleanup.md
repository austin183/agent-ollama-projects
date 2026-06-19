# Conditional Rendering State Cleanup — Learnings

**Date:** 2026-06-19
**Session:** 119
**Purpose:** Document learnings from the stale overlay rendering bug discovered when removing an overlay mask image.

---

## What Worked

### Explicit state clearing for conditional rendering paths

When a rendering method updates state only within a conditional branch (`if let overlay = config.overlay { ... }`), removing the condition's input leaves the previously rendered state visible. The fix is to add an `else` branch that explicitly clears the stale state.

**Pattern:**

```swift
// Before (bug): overlayImage persists when mask is removed
if let overlay = config.overlay {
    previewManager.updateOverlay(overlay: overlay, canvasSize: ...)
}

// After (fix): overlayImage cleared when no overlay config
if let overlay = config.overlay {
    previewManager.updateOverlay(overlay: overlay, canvasSize: ...)
} else {
    previewManager.overlayImage = nil
    previewManager.overlayBlendMode = nil
}
```

### Backward-compatible enum migration

When removing a `Codable` enum case, saved data with the old raw value will decode to `nil` with `init(rawValue:)`. A dedicated `migrate(rawValue:)` method handles the mapping cleanly at the persistence boundary, keeping the enum itself simple.

---

## Key Pattern: Conditional State Updates Need Symmetric Cleanup

Any rendering pipeline that conditionally produces output needs a symmetric path to clear that output when the condition becomes false. This applies to:

- **Overlay layers** — mask image set/unset
- **Background images** — image set/unset
- **Title rendering** — text present/empty
- **Per-panel renders** — panels added/removed

The general rule: **every code path that produces rendered state has a corresponding path that clears it**. If the update is conditional, the clear must be explicit.

This is distinct from the "don't clear before async replacement" pattern (session-057), which warns against clearing state before the replacement arrives. That pattern addresses the *timing* of clears. This pattern addresses the *existence* of clear paths.

---

**Status:** Closed
**Follow-up:** None
