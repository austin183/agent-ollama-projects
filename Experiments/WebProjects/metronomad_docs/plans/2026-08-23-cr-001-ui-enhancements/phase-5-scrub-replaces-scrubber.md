# Phase 5: Scrub + Keyboard Replaces `#offsetScrubber` (P0)

**Depends on:** Phase 4 — the waveform canvas in the DOM (display-only), the D-H Phase-4 template state, `offsetDraft` data field, `displayPosition`/`markerPercent` computeds. Phase 3's view already ships the pointer machinery (callbacks-gated).

**Context to load:**
- `index.md` → Overview, Key Discoveries (R-1/R-2 shape changes)
- `context.md` → **D-G in full** (handler contracts), D-H (the Phase-5 canvas attr diff + scrubber deletion), Known Behaviors KB-17, Risk Register R-1, R-2, R-3, R-5, Cross-Cutting Constraints (strings)
- `behavior-specs.md` → §5 (this phase's canonical rows)
- As-built: `MyESModules/App/createMetronomadMethods.js` (`onOffsetScrub` `:170-178` + its stale JSDoc `:168-169` — R-5), `index.html` (scrubber + N-15 comment `:75-79`, the Phase-4 canvas block), `test/e2e/keyboard.spec.cjs` (exact Tab order `:44-56`, locked-skip `:69-80`, arrow test `:110-112`), `test/e2e/playback.spec.cjs` (`:194`, `:255-262`), `test/e2e/smoke.spec.cjs` (CONTROLS `:22-33`), `MyComponents/UiHandlersTest.html` (mock-VM pattern `:34-60`; U-10 `onOffsetScrub` rows `:647-658` must keep passing unchanged)
- Skill: `building-web-apps` → `references/interaction.md` (keyboard parity, preventDefault discipline)

**TDD workflow (RED → GREEN):** RED per-test:
1. `UiHandlersTest.html`: WF-I2.1…WF-I2.10 first (handlers missing → TypeError RED).
2. GREEN the four handlers (`onWaveformScrubStart` / `onWaveformScrubMove` / `onWaveformScrubEnd` / `onWaveformKeydown`).
3. `waveform.spec.cjs`: E2E-3.5…E2E-3.10 RED → GREEN with the template diff (slider attrs + keydown) and the lifecycle callback wiring (`onScrubStart: (t) => this.onWaveformScrubStart(t)` etc.).
4. In the **same commit** as the scrubber removal: update `keyboard.spec.cjs` (3 sites), `playback.spec.cjs` (2 sites), `smoke.spec.cjs` (drop `#offsetScrubber` from CONTROLS — R-2: the tab-order swap and the removal land together, so no phase boundary ever contains a broken order).

## Overview

Turn the canvas into the interactive offset control: pointer scrub with the W-1 hygiene (capture try/catch, `pointercancel` first-class, blur safety net), full keyboard parity with the native range it replaces (arrows/Shift/Home-End identical; PageUp/Down deliberately coarser at 10 % of duration — W-9, see context.md plan-review UX-1), the ARIA `slider` role (W-10 split finalized), and the **removal of `#offsetScrubber`** (O-1) with every E2E reference re-pointed. All commits funnel through `onOffsetScrub` — one quantization law (T-35), never a second.

## Changes Required

### 1. `MyESModules/App/createMetronomadMethods.js`
**Changes:** D-G verbatim — `onWaveformScrubStart(tenths)` (lock backstop → `offsetDraft = clampOffset(tenths, this.duration)` → `setDraft`), `onWaveformScrubMove(tenths)` (draft-only, same law), `onWaveformScrubEnd(commit)` (`setDraft(null)`; commit → `onOffsetScrub(this.offsetDraft)`; always `offsetDraft = null`), `onWaveformKeydown(e)` (←/→ ±0.1, Shift ±1, PageUp/Down ±10 % of duration, Home/End 0/duration; every commit via `onOffsetScrub(next)`; `preventDefault` only after a handled commit; no-file/no-duration no-op — WF-I2.10).
**Also (R-5):** re-point `onOffsetScrub`'s JSDoc (`:168-169`) — the premise "the scrubber's own range already keeps values in [0, max]" is dead; the method is now *the* shared scrub law for the canvas (pointer + keyboard) and the text field. Its U-10 tests (`UiHandlersTest.html:647-658`) pass unchanged.

### 2. `MyESModules/App/createMetronomadLifecycle.js`
**Changes:** `mounted()` — pass the three callbacks: `createWaveformView(this, {}, { onScrubStart: (t) => this.onWaveformScrubStart(t), onScrubMove: (t) => this.onWaveformScrubMove(t), onScrubEnd: (c) => this.onWaveformScrubEnd(c) })` (factory-time `() => this.x()` traps avoided — the factory captures the instance where it exists, I-7 shape).

### 3. `index.html`
**Changes:**
- Canvas attrs: `role="slider"`, `:tabindex="isReady ? 0 : -1"`, `aria-label="Start offset"`, `:aria-valuemin="0"`, `:aria-valuemax="duration"`, `:aria-valuenow="offset"`, `:aria-valuetext="'Offset ' + formatTime(offset)"`, `:aria-disabled="isParamLocked || null"`, `@keydown="onWaveformKeydown"` (D-H Phase-5 diff; raw-float `aria-valuemax` is intentional — KB-17, R-3).
- **Delete** `#offsetScrubber` + its N-15 comment (`:75-79`) (O-1).

### 4. `test/e2e/keyboard.spec.cjs`
**Changes:** `:51` exact order — new canonical 8-element sequence: `bpmMinusBtn, bpmInput, bpmPlusBtn, **waveformCanvas**, offsetInput, countInInput, playStopBtn, previewBtn` (the canvas takes the scrubber's slot; treat the old order as **superseded**, not amended — R-2). `:71` locked-skip list — `offsetScrubber` → `waveformCanvas` (locked canvas is `tabindex="-1"` → skipped). `:110-112` arrow test — `page.locator('#waveformCanvas').focus()`; 5× ArrowRight → readout `0:00.5 / 0:03.0` (same expectation, new target).

### 5. `test/e2e/playback.spec.cjs`
**Changes:** `:194` re-enabled list — drop `#offsetScrubber`; the canvas is asserted separately: `#waveformCanvas[aria-disabled]` **absent** after Stop (a canvas can't `toBeEnabled()`/`toBeDisabled()` — R-1). `:255` lockedInputs — drop `#offsetScrubber`; add the canvas lock assertion: `#waveformCanvas[aria-disabled="true"]` present in countingIn **and** playing, computed `pointer-events: none` (E2E-1.6 behavior preserved — E2E-3.10).

### 6. `test/e2e/smoke.spec.cjs`
**Changes:** drop `#offsetScrubber` from CONTROLS (it no longer exists); `#waveformCanvas` stays in the Phase-4 presence-only list.

### 7. `test/e2e/waveform.spec.cjs` (extend — Phase 5 rows)
**Changes:** E2E-3.5…E2E-3.10 per the inlined table. `pointercancel`/`blur` are dispatched in-page (standalone `page.evaluate` programs — define every helper locally). Focus-return assertion: `document.activeElement.id === 'waveformCanvas'`.

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §5)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-I2.1 | P0 | Unit (mock-VM), Ready, duration 3.0, offset 0 | `onWaveformScrubStart(1.5)` | `offsetDraft === 1.5` (quantized via `clampOffset`); `view.setDraft(1.5)` called; committed `offset` still 0 (draft, not commit) |
| WF-I2.2 | P0 | Draft active (1.5), duration 3.0 | `onWaveformScrubMove(2.73)`; then `onWaveformScrubMove(999)` | draft `2.7` (quantize-then-reclamp — the same law as `onOffsetScrub`, never a second rule); draft `3.0` (clamped to duration, T-35) |
| WF-I2.3 | P0 | Draft `2.7` | `onWaveformScrubEnd(true)` | `onOffsetScrub(2.7)` law applied: `offset === 2.7`, `offsetText === "0:02.7"`, hint cleared; `offsetDraft === null`; `view.setDraft(null)` called |
| WF-I2.4 | P0 | Draft `2.7`, committed offset 1.0 | `onWaveformScrubEnd(false)` (pointercancel path) | `offset` stays 1.0, `offsetText` unchanged; `offsetDraft === null` — the draft is discarded, nothing committed (W-1) |
| WF-I2.5 | P0 | `isParamLocked === true` | `onWaveformScrubStart(1.5)` | no-op: `offsetDraft === null`, no view call (U-12 JS backstop; CSS `pointer-events: none` is the first line) |
| WF-I2.6 | P0 | Unit, Ready, offset 0, duration 3.0 | 5× `onWaveformKeydown(ArrowRight)` | offset `0.5`, `offsetText "0:00.5"` after the fifth (0.1 s per press — the old scrubber step, W-9); one `ArrowLeft` → `0.4`; at 0, `ArrowLeft` → stays `0` |
| WF-I2.7 | P1 | Offset 0.4, duration 2.96 (the T-35 quantize-up case) | `onWaveformKeydown(Shift+ArrowRight)` | offset `1.4`; from 2.5 → `Shift+ArrowRight` → `2.9` (never 3.0 > duration — `clampOffset` end-clamp) |
| WF-I2.8 | P1 | Duration 30.0, offset 5.0 | PageDown → PageUp → Home → End | `2.0` → `5.0` → `0` → `30.0` (PageUp/Down = 10 % of duration = 3.0 s — deliberately coarser than the native range's step×10, W-9; Home/End = 0 / duration) |
| WF-I2.9 | P1 | Any handled key; and an unhandled key (`KeyA`) | keydown events | `preventDefault()` called exactly for the handled set (arrows, PageUp/Down, Home/End) and never for `KeyA`; `KeyA` changes nothing |
| WF-I2.10 | P1 | Unit, noFile state (`fileName ''`, duration 0) | `onWaveformKeydown(ArrowRight)` / `onWaveformScrubStart(1)` | no-op — no offset write against a zero duration (the canvas is `tabindex="-1"` and unfocusable in this state; the JS guard is the backstop) |

**E2E (this phase's rows — `waveform.spec.cjs` + the re-pointed rows in `keyboard.spec.cjs` / `playback.spec.cjs`):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-3.5 | Click scrubs the offset | E2E-3.1 state; mouse-click at 50 % of the canvas width | `#offsetInput` value `"0:01.5"` (≈ x/width × duration, tenths); canvas `aria-valuenow="1.5"`, `aria-valuetext="Offset 0:01.5"`; readout `0:01.5 / 0:03.0`; **focus returns to `#waveformCanvas`** after the click (CR §1.5) |
| E2E-3.6 | Drag scrubs continuously | mouse.down at 20 %, mouse.move to 60 % (≥3 steps), mouse.up | during the drag the readout tracks the draft (in-page samples advance); on release: offset `≈ 1.8` (±1 tenth), `#offsetInput` mirrors `"0:01.8"`; no stuck draft (a later click commits normally) |
| E2E-3.7 | `pointercancel` discards (W-1) | dispatch `pointerdown` then `pointercancel` in-page (iOS OS-gesture shape) | offset unchanged; no draft stuck — a subsequent real click at 50 % still commits `1.5`; `window.blur` mid-drag behaves identically (both cleanup paths) |
| E2E-3.8 | Keyboard parity on the canvas (replaces the old scrubber arrow test) | focus `#waveformCanvas` (Ready, offset 0, sine3s) | 5× ArrowRight → readout `0:00.5 / 0:03.0`; Shift+ArrowRight → `0:01.5 / 0:03.0`; PageUp (3 s file → +0.3) → `0:01.8 / 0:03.0`; End → `0:03.0 / 0:03.0`; Home → `0:00.0 / 0:03.0`; `aria-valuenow`/`aria-valuetext` follow after each |
| E2E-3.9 | ARIA roles + tabindex (W-9/W-10) | assert in-page across states | **ready**: canvas `role="slider"`, `tabindex="0"`, `aria-valuemin="0"`, `aria-valuemax` = duration (raw float allowed — KB-17), `aria-valuenow` = offset, `aria-valuetext="Offset 0:00.0"`; readout `role="progressbar"`, `aria-valuenow` = songPosition, `aria-valuetext` formatted — the two roles are **distinct elements**; **noFile**: canvas `tabindex="-1"` (out of tab order); the progressbar readout is absent (no file) |
| E2E-3.10 | Param lock on the canvas (E2E-1.6 behavior preserved) | counting-in 8, Play → countingIn/playing → Stop | in countingIn **and** playing: `#waveformCanvas[aria-disabled="true"]` present and computed `pointer-events: none`; after Stop → ready: attribute absent; `#offsetScrubber` no longer exists in the DOM (grep: zero references in `index.html` and `test/e2e/`) |

## Success Criteria

**Automated:**
- [ ] WF-I2.1…WF-I2.10 pass (mock-VM, UiHandlersTest); the existing U-10 `onOffsetScrub` rows (`:647-658`) still pass unchanged.
- [ ] E2E-3.5…E2E-3.10 pass.
- [ ] `node scripts/run-tests.cjs` fully green; `npx playwright test` fully green (27 + 6 new = 33) — including the re-pointed `keyboard.spec.cjs` (new canonical Tab order) and `playback.spec.cjs` (canvas lock assertions).
- [ ] **Grep pass (the O-1 removal is total):** `rg "offsetScrubber" index.html test/ MyComponents/ MyESModules/` → zero hits.
- [ ] Grep pass (one quantization law): `rg "clampOffset" MyESModules/App/createMetronomadMethods.js` → the law lives in `onOffsetScrub`/`commitOffsetEntry`/`onFileDropped`; the new handlers call `clampOffset`/`onOffsetScrub` and never re-derive quantization (no `Math.round(x * 10)` outside `paramClamps.js`).

**Manual (user, server on :8000):**
- [ ] Click and drag on the waveform set the offset; the text field + readout mirror throughout; focus lands back on the canvas after a drag (arrow continuation is one action away).
- [ ] On a phone (or DevTools touch): horizontal scrub works while vertical swipes still scroll the page (`touch-action: pan-y`, W-2); an interrupted gesture (scroll-away) discards the draft.
- [ ] Keyboard: arrows/Shift/PageUp-Down/Home-End on the focused canvas behave like the old range did and better (coarse PageUp/Down step).

**Phase close:** run the handoff audit against Phase 6's "Context to load" and inlined TD-U1.\*/E2E-4.x rows (does the as-built BPM group in `index.html` still match the D-I hint-slot assumption — `bpmClamped` hint at `:70`, `v-model` + commit handlers on `#bpmInput`?) before marking done in `index.md`.
