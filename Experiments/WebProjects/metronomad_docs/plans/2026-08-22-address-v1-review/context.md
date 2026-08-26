# Review-Fix Plan — Context (stable whole-plan detail)

## Fix-Contract Decisions

**RD-1 — Commit-on-Enter/blur for BPM and count-in (C-1; fixes the U-11 design consequence).**
Adopt the pattern the offset field already uses: a local draft text bound via `v-model`, committed + clamped **only** on Enter/blur. The per-keystroke `@input` clamp is deleted. Steppers (`onBpmStep`) remain live (they mutate the model directly and must sync the draft). Contract:

- New data: `bpmText`, `countInText` (draft strings); `countInClamped` (hint flag for N-20).
- `commitBpmEntry()` / `commitCountInEntry()` — parse (existing `_parseParamInput` core survives as the shared parse/clamp helper), write model + `_lastValid*`, set `bpmClamped`/`countInClamped` from the result, revert the draft to the committed display, set hint. Empty/non-numeric → restore last valid (the shared `_restoreLastValid(kind)` extracted per N-16 — one helper for both inputs).
- Template: `v-model="bpmText"` + `@keyup.enter="commitBpmEntry"` + `@blur="commitBpmEntry"` (same for count-in); drop `:value`+`@input`.
- **Stepper/draft sync:** whenever the model changes by any path other than commit (steppers, file-load reset of related state), the draft is re-rendered from the model (`formatBpm` = plain integer string) — the display/model divergence C-1 exhibited is exactly what the per-keystroke regression test (U-11 row, revised) must not allow in any state.
- The offset field's placeholder/hint wording ("mm:ss.t") and `formatTime`'s unpadded minutes are a separate consistency call — **N-19 owns it in Phase 3**; Phase 1 must not change offset display.

**RD-2 — One file-acceptance choke point (I-1).**
`onFileDropped(file)` becomes the single entry for both drop and browse, and owns BOTH guards, checked in this order:

1. `if (this.isParamLocked) { this.errorMessage = 'Drop a new song after stopping'; return; }` (moved out of `onDrop`, which keeps only the `isDragOver` reset).
2. `if (this.decoding.active) return;` — silent no-op (I-2, RD-3).

`#browseBtn` gains `:disabled="isParamLocked"` (disabled, not merely dimmed — matches the U-12 "unfocusable, not just disabled" convention for locked controls).

**RD-3 — Single-flight decode (I-2).**
Rejection at the top of `onFileDropped` is safe because `loadFile` emits `'decoding'` **synchronously before its first await** (`fileLoader.js`), so `decoding.active` is visible to any same-tick or later event. No in-flight counter in the loader (out of scope per index). The transient-`'idle'`-lie and buffer-divergence failure modes both disappear with rejection.

**RD-4 — Engine boundary guard for end-of-song offsets (I-3).**
`startSequence`'s invalid-check gains `offset >= buffer.duration` → `{ ok: false }`, matching `preview`'s existing D2 guard — one rule, both entry points. `clampOffset` changes to **quantize-then-reclamp**: `Math.min(duration, Math.round(clamped * 10) / 10)` so a duration of 2.96 can no longer quantize up to 3.0 > duration. T-31/T-33/T-34 (v1 behavior-specs) remain true under the new order; the new row T-35 pins the 2.96 case.

**RD-5 — "Preview stopped" on user stop (I-4).**
In `onEngineStateChange`'s `STOPPED` case: branch on `this.isPreviewing` (still `true` when the engine's `stopped` event arrives — `_returnToReady` clears it, so the read must precede it) → announce "Preview stopped"; else "Stopped". The auto-end path (`previewEnded`) is unchanged. This makes U-09's announced string true on **both** stop paths.

**RD-6 — Teardown ownership and DI for the visual clock (I-5 + I-6 + I-7 + N-17, one refactor).**
- **Engine** loses `startVisualClock`/`stopVisualClock`/`_rafTick`/the `onFrame` parameter and the `stopVisualClock()` calls in `_teardown`/`dispose`. It keeps `getBeatGrid`/`songPosition` (genuine `createBeatDots` dependencies). P-12's remaining value (phase law + cancel semantics) is already covered by B-01/B-02 against the app's real loop — P-12 is **retired**, not ported.
- **`createBeatDots(vm, base, callbacks)`** (N-17): the factory captures `vm` once — built in `mounted()` where the instance exists; `startVisualClock`/`stopVisualClock`/`onVisibilityChange`/`stopAll` drop the `vm` argument. App methods `_startBeatDots`/`_stopBeatDots`/`onVisibilityChange` update their call sites.
- **`base`** gains browser globals with defaults mirroring the engine's parameter style: `{ getEngine, getClock, getDom, raf = window.requestAnimationFrame, cancelRaf = window.cancelAnimationFrame, matchMedia = window.matchMedia, isPageHidden = () => document.hidden }` (I-7). `BeatDotsTest` deletes its save/restore global patching and injects fakes — the leak-on-throw risk the review names goes away.
- **`stopAll`** tears down only its own resources (pending RAF, `matchMedia` listener, dot classes, `_stopped` flag). It **never touches the engine** (I-6).
- **`beforeUnmount`** owns the full ordering explicitly: listener removal → `beatDots.stopAll()` → `engine.dispose()` → `fileLoader.release()`. The v1 `else if (this._engine)` fallback is **not** preserved as a shape — with `stopAll` no longer disposing, an `else if` would skip `engine.dispose()` in the normal path (visualizer present). As built (2026-08-22, Phase 2): independent `if` guards — `stopAll` when `_beatDots` exists, then `dispose` when `_engine` exists, each nulling its handle; the dispose guard doubles as defense for a mount that built the engine but no visualizer. Lifecycle-level tests assert `engine.dispose` is called exactly once in both the full-mount (B-06) and no-visualizer (R-I6.2 variant) cases.

## Interface Shapes (as-built targets)

```js
// createMetronomadMethods.js — new/changed (Phases 1)
_restoreLastValid(kind)            // kind: 'bpm' | 'countIn' (N-16)
commitBpmEntry()                   // RD-1; parses this.bpmText
commitCountInEntry()               // RD-1 + N-20 hint (countInClamped)
onFileDropped(file)                // RD-2 guards first, then load (order: lock → decoding)

// Utils/paramClamps.js (Phase 1)
clampOffset(value, duration)       // quantize-THEN-reclamp (RD-4); T-35 row

// Playback/playbackEngine.js (Phases 1–2)
startSequence({buffer,bpm,countInBeats,offset})  // + offset >= buffer.duration guard (RD-4)
// Phase 2: no onFrame/startVisualClock/stopVisualClock (RD-6)

// App/createBeatDots.js (Phase 2)
createBeatDots(vm, base, callbacks)  // base: { getEngine, getClock, getDom,
                                     //   raf, cancelRaf, matchMedia, isPageHidden }
// returns { startVisualClock, stopVisualClock, onVisibilityChange, stopAll }
// stopAll: visualizer resources only (RD-6)

// App/createMetronomadLifecycle.js (Phase 2)
// beforeUnmount: removeEventListener → stopAll → engine.dispose() → fileLoader.release()

// Utils/beatGrid.js (Phase 2)
export const BEATS_PER_BAR = 4     // I-8; accent rule k % BEATS_PER_BAR === 1
// createBeatDots: DOT_COUNT = BEATS_PER_BAR
// Vue data: beatsPerBar → template v-for + downbeat class bind to it
```

## Testing Strategy

- **Regression-first TDD.** Every Phase 1 fix begins with the failing test the review names (the review's "why the tests are green" paragraphs state the exact gap). The C-1 per-keystroke unit test (`'9'` then `'0'`, model untouched until commit) is the plan's flagship regression — it is the shape of test that let the defect slip.
- **Suite growth, no renumbering.** Existing IDs keep their meaning except where this plan amends them (U-11, U-13, U-09, P-12, P-13, B-05 — amended rows live in `behavior-specs.md` here, canonical for the amended text). New IDs: `R-*` for review-specific rows. v1 IDs (T-35 etc. where noted) extend the v1 tables.
- **Runner hardening is itself tested** (I-9): after the fix, a suite page that loads but registers 0 tests must exit non-zero. Verify manually with a scratch test page, then delete the scratch (or leave a permanent "empty suite" fixture page under `MyComponents/` if the session finds it cleaner — its own 0-test guard must not trip the runner: name it so `run-tests.cjs`'s glob still picks it up and assert on the *exit code*, not a green line).
- **E2E convention unchanged:** in-page 5 ms transition logger for timing; `pressSequentially` (keystroke-by-keystroke) is the one new input style, used only where the finding is about per-keystroke behavior (E2E-R-C1.1) — `fill()` stays for everything else.
- **Docs move with code:** any phase that changes a contract pinned in `AGENTS.md`, the v1 `behavior-specs.md`, or the v1 `context.md` (KB entries) updates those files in the same session (N-18/N-21 are Phase 2 items; Phase 1's U-11 wording update is inlined there).
- **Baseline gate per phase:** `node scripts/run-tests.cjs` fully green (count grows from 127) and `npx playwright test` fully green (21 + new). Server on :8000, user-started.

## Cross-Cutting Constraints

- **Frozen architecture:** D4 generation counter, D5 single `start(when, offset)`, D9 pure-function beat phase, the 25 ms/100 ms scheduler shape, fileLoader's buffer/URL lifecycle (its dead `objectUrl` cleanup is N-3, Phase 3 — do not touch it in Phases 1–2).
- **String inventory:** the 24 audited user-facing strings stay verbatim except the two this plan owns (U-09's "Preview stopped" now reached via user stop; N-20's optional "Count-in limited to 1–16"). New strings need review against spec §14.
- **Commits:** per phase, `Co-Authored-By: LittleLight <noreply@traveler.dstny>`; commit via `build-quick-work` per repo pattern.
- **KB numbering:** new known behaviors continue the v1 plan's series — the next free ID is **KB-11** (reserved for N-2's background-tab throttling note, Phase 3; KB-10 is taken by the offline deferral).

## References

- `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` — the finding set (C-1, I-1…I-9, N-1…N-33) and §8 action plan this phase map mirrors
- `_agent_docs/plans/2026-08-17-metronomad-v1/` — `context.md` (D1–D11, KB-1…KB-10), `behavior-specs.md` (full v1 scenario set)
- `.pi/skills/building-web-apps/SKILL.md` — repo patterns (mock-VM, fake-injection, in-page timing logger)
- writing-plans skill `references/phase-handoff.md` — the phase-close audit
