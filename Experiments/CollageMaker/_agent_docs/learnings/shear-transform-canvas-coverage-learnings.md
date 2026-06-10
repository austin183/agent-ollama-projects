# Shear Transform Canvas Coverage — Learnings

**Date:** 2026-06-10
**Session:** 97

## Shear Transform Asymmetric Coverage

A horizontal shear `x' = x + y·tan(θ)` displaces different y-levels by different amounts:
- **Top edge (y=0):** zero displacement
- **Bottom edge (y=H):** displaced right by `H·tan(θ)`

To cover the full canvas `[0, W]` at **every** y-level, the unsheared left edge of panel 0 must start at `-H·tan(θ)` (the maximum displacement), not `-H·tan(θ)/2`. The `/2` formula only works if displacement is symmetric at both ends, but shear is zero at one end and maximum at the other.

**Verification:** At y=H, sheared left edge = `centerOffset + H·tan(θ)`. For this to equal 0: `centerOffset = -H·tan(θ)`.

**Common pitfall:** Plan review notes claimed `centerOffset = -shearOffset/2` was correct, reasoning that the "bottom-left canvas corner" would be covered. But they confused the top-left sheared corner (`centerOffset + H·s`) with the bottom-left (`centerOffset` at y=0, no shear). The bottom-left (y=H in CGContext) is the one that needs to reach x=0.

## CGContext Implicit Clipping vs SwiftUI ZStack

A `CGContext` created at bitmap size `S` silently discards all drawing outside `[0, S]`. This means:

- **Non-layered preview** (single `CGContext` at `previewSize` with scale transform): content beyond canvas bounds is automatically clipped. No explicit clip needed.
- **Layered mode** (individual per-panel `NSImage`s placed in a SwiftUI `ZStack`): each panel is rendered to its own bitmap at its bounding rect size, then placed at its bounding rect position. No canvas-level clipping occurs — panels extending beyond the canvas are visible.

**Fix:** Add `.clipShape(Rectangle())` + `.frame(width:, height:)` + `.position(x:, y:)` to the ZStack, using the fitted canvas preview frame. This clips content to the canvas area (accounting for letterboxing) and matches the non-layered mode behavior.

**Broader lesson:** When a rendering pipeline has multiple modes (single-context vs per-element), verify that clipping behavior is consistent across modes. A visual discrepancy between modes often indicates one mode is missing a clip that the other provides implicitly.
