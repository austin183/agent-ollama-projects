# Phase 3: Waveform View Factory (P0)

**Depends on:** Phase 1 — `poolPeaks` / `extractPeaks` result shape from D-C as built (the view pools high-res peaks to CSS columns; it never walks raw samples).

**Context to load:**
- `index.md` → Overview, Key Discoveries (canvas column bound 640 px — R-8)
- `context.md` → **D-F in full** (factory contract, DI shape, render/dispose rules), D-C (poolPeaks), Known Behaviors KB-14 (playhead is DOM — the view has no clock), Risk Register R-8, R-11, Cross-Cutting Constraints
- `behavior-specs.md` → §3 (this phase's canonical rows)
- As-built (DI reference): `MyESModules/App/createBeatDots.js` (`createBeatDots(vm, base, callbacks)` `:41-56` — the shape to mirror)
- Skill: `building-web-apps` → `references/canvas-2d.md` (lifecycle `init/resize/scheduleRender/dispose`, DPR, GPU release), `references/interaction.md` (pointer capture try/catch, `touch-action: pan-y`, global pointerup + blur safety net), `references/testing-unit.md` (Proxy-mocked 2D ctx, fake RAF collector + `flushRAF`), `references/memory-management.md` (dispose ordering)

**TDD workflow (RED → GREEN):** RED first — create `MyComponents/WaveformViewTest.html` importing `{ createWaveformView }` through the barrel. **RED shape (R-11):** broken page (module link failure), not per-test failures. GREEN: implement `createWaveformView.js`, add the barrel export. The view is DI-pure like the engine/beatDots — the suite injects `raf`/`cancelRaf`/`devicePixelRatio`/`getDom`/`getHeightCss` and a mock-VM; **no global patching** (the review plan's DI-injection discipline — fakes injected, never monkey-patched).

## Overview

Build the canvas rendering + interaction factory `createWaveformView` — the only new module that touches the DOM. It renders pooled min/max columns once per (peaks, size) pair (RAF-coalesced, DPR-scaled, one line per CSS column), owns its own listeners, and `dispose()`s cleanly. Scrub callbacks are **optional** — Phase 4 wires none (display-only), Phase 5 wires the three.

## Changes Required

### 1. `MyESModules/App/createWaveformView.js` (new)
**Changes:** D-F interface verbatim:

```js
export function createWaveformView(vm, base = {}, callbacks = {})
// base: { canvasId='waveformCanvas', raf, cancelRaf, devicePixelRatio, getDom,
//         getHeightCss = () => 64 }   (window/document defaults — I-7 convention)
// callbacks: { onScrubStart(tenths), onScrubMove(tenths), onScrubEnd(commit) } — ALL OPTIONAL
// returns { init(canvas), setPeaks(peaks), setDraft(tenths|null),
//           resize(widthCss, heightCss), scheduleRender(), dispose() }
```

- **Render** (WF-V1.1/WF-V1.6): `poolPeaks(peaks, cssWidth)` → one vertical line per **CSS column** from `y(min)` to `y(max)`, mirrored about the center, batched in one path pass; a silent column (min=max=0) draws a zero-height line at center (a gap reads as silence). Draw count is width-bounded (≤640 from `#app` max-width), never DPR-bounded (R-8).
- **Coalescing** (WF-V1.2, W-5): `scheduleRender()` sets at most one pending RAF; a resize storm leaves one pending render with the final size winning.
- **DPR** (WF-V1.3): `canvas.width = cssW · dpr`, `canvas.height = cssH · dpr`, ctx scaled so drawing stays in CSS space.
- **Draft marker** (WF-V1.7): `setDraft(tenths)` stores the transient value and schedules a render that adds one marker line in-canvas; `setDraft(null)` clears it. The DOM overlay marker is never touched by the view.
- **No internal clock** (WF-V1.5): the RAF collector is empty in steady state — the playhead is a DOM overlay driven by Vue (KB-14/D9).
- **Pointer path** (WF-V1.8/9/10, W-1): attached **only when `callbacks.onScrubStart` is provided**. `pointerdown` → x→tenths via `vm.duration` (`(x/cssWidth) · duration`), `setPointerCapture` in try/catch (Safari stale pointerId — the throw must not kill the drag); `pointermove` only while dragging; `pointerup` (canvas) / global `window` `pointerup` → `onScrubEnd(true)` exactly once + `canvas.focus()`; `pointercancel` / `window` `blur` → `onScrubEnd(false)` (discard, no focus). Capture released on every exit; move-before-down is ignored.
- **Resize listener** (WF-V1.4): `window` resize → measure container × `getHeightCss()` → `resize()` → coalesced render.
- **`dispose()`** (WF-V1.4): idempotent — cancel pending RAF, remove ALL listeners (canvas pointer*, window pointerup, window blur, window resize), `canvas.width = 0; canvas.height = 0` (GPU release).

### 2. `MyESModules/index.js` (barrel)
**Changes:** add `createWaveformView` to the App block.

### 3. `MyComponents/WaveformViewTest.html` (new)
**Changes:** the §3 table. Proxy-wrap a real 2D ctx stub recording draw calls (skill `testing-unit.md` pattern); fake RAF collector with `flushRAF()`; fake DOM node (`{ width, height, style, addEventListener, removeEventListener, setPointerCapture, releasePointerCapture, focus, getBoundingClientRect }`).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §3)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-V1.1 | P0 | View inited; 4096-bucket peaks set; size 300×64 CSS | `setPeaks(peaks)` → `flushRAF()` | exactly **one** render: `poolPeaks` to 300 columns, one vertical line per CSS column (300 lines), mirrored about the center (O-3); a second `setPeaks` of the *same* peaks object at the same size → no further render |
| WF-V1.2 | P0 | View inited, peaks set | `resize(600)` → `resize(500)` → `resize(400)` without flushing (a W-5 rotation storm) | at most **one** pending RAF; `flushRAF()` → one render at the **final** size (400 columns) — earlier sizes never paint |
| WF-V1.3 | P0 | `devicePixelRatio` injected as 2 | `resize(300, 64)` | backing store `canvas.width === 600`, `canvas.height === 128`; drawing coordinates stay in CSS-column space (ctx scaled by 2) |
| WF-V1.4 | P0 | View inited with scrub callbacks; a pending render queued | `dispose()` twice | first call: pending RAF cancelled, canvas + window (`pointerup`, `blur`) + `resize` listeners all removed, `canvas.width === 0 && canvas.height === 0` (GPU release); second call: no throw, no double-removal |
| WF-V1.5 | P1 | View inited, peaks set, steady state | observe the RAF collector after flush | collector is **empty** — no internal clock; the only RAF ever queued is the coalesced render (the playhead is DOM, not canvas) |
| WF-V1.6 | P1 | Peaks with a known per-column profile (e.g. column k: min −0.5, max +0.5) at height 64 | render | one draw op per CSS column from `y(max)` to `y(min)`, center line at y = 32 (mirrored bars, O-3); a silent column (min = max = 0) draws a zero-height line at center — a gap reads as silence |
| WF-V1.7 | P1 | Rendered state | `setDraft(1.5)` → `flushRAF()`; then `setDraft(null)` → `flushRAF()` | draft marker line painted at the draft position on the first flush; gone after the second; the DOM overlay marker is untouched by the view (it tracks the committed offset only) |
| WF-V1.8 | P2 | `setPointerCapture` stubbed to **throw** (Safari stale pointerId, W-1) | `pointerdown` then `pointermove` | the throw is caught; the drag continues — `onScrubMove` still fires; no stuck state |
| WF-V1.9 | P1 | Active drag (pointer captured) | (a) `pointerup` on canvas; (b) pointer released **off-canvas** → global `window` `pointerup`; (c) `window` `blur` mid-drag; (d) `pointercancel` (in-page dispatch, iOS OS-gesture shape — two-finger scroll/rotate) | (a) `onScrubEnd(true)` exactly once; (b) `onScrubEnd(true)` via the global path (capture released) exactly once; (c) `onScrubEnd(false)` — discard; (d) `onScrubEnd(false)` — discard; each path releases capture and a subsequent `pointermove` fires nothing (W-1 cleanup paths) |
| WF-V1.10 | P2 | No drag active | `pointermove` dispatched on the canvas | no `onScrub*` callback fires (move before down is ignored); x→tenths conversion uses `vm.duration`: x = 50 % of width → tenths = 0.5 × duration (1.5 for a 3 s file) |

## Success Criteria

**Automated:**
- [ ] RED observed first: broken-page (link) RED for `WaveformViewTest.html` before the factory exists (R-11), then GREEN.
- [ ] WF-V1.1…WF-V1.10 all pass.
- [ ] `node scripts/run-tests.cjs` fully green; `npx playwright test` unchanged at 23.
- [ ] Grep pass: `rg "window\.|document\." MyComponents/WaveformViewTest.html` → zero monkey-patching (all DI-injected); `rg "requestAnimationFrame" MyESModules/App/createWaveformView.js` → only through `base.raf` (default reads `window.requestAnimationFrame` once at factory time, I-7 shape).

**Manual:**
- [ ] n/a in this phase (the canvas ships to the page in Phase 4).

**Phase close:** run the handoff audit against Phase 4's "Context to load" and inlined WF-I1.\*/E2E-3.1…3.4 rows (does the as-built `init`/`setPeaks`/`resize` surface match the wiring in D-F — in particular that Phase 4 can build the view with **no** callbacks and call `setPeaks` from the VM?) before marking done in `index.md`.
