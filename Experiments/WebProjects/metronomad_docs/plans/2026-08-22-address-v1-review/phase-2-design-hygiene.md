# Phase 2: Design Hygiene — I-5…I-8 + N-17, N-18, N-21 (P1)

**Depends on:** Phase 1 complete (its `createMetronomadMethods.js` and `UiHandlersTest` changes must be in; Phase 2 re-wires the same files' beat-dots call sites).

**Context to load:**
- `index.md` → Overview, What We're NOT Doing (frozen architecture list)
- `context.md` → **RD-6 in full** (the teardown/DI refactor contract), Interface Shapes, Cross-Cutting Constraints
- `behavior-specs.md` → §6 (this phase's canonical rows, incl. the P-12 retirement note)
- Review: `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` → I-5…I-8, N-17, N-18, N-21
- v1 plan: `context.md` → D9 (beat phase ownership paragraph — the ownership pin to rewrite), KB-6; `behavior-specs.md` → P-12, B-05 rows (retirement/amendment targets)
- As-built: `MyESModules/App/createBeatDots.js`, `MyESModules/App/createMetronomadLifecycle.js`, `MyESModules/Playback/playbackEngine.js` (visual-clock + teardown regions), `MyComponents/BeatDotsTest.html` (the global-patching boilerplate to delete)
- Skill: `building-web-apps` → fake-injection pattern (the engine's parameter style is the mirror for RD-6's `base`)

**TDD workflow:** this phase is refactor-heavy — the tests move/change *with* the code, not strictly before it. Sequence: R-I5.1 (engine surface removal, tests first) → R-I6.1/R-I6.2 (ownership flip, lifecycle test first) → R-I7.1 (injection; delete global patching last, once all B-suite rows pass via fakes) → R-I8.1 (constant) → docs (N-18, N-21) with a final grep pass.

## Overview

Make the module ownership story true: the engine has no unused visual clock; the lifecycle owns all teardown; `createBeatDots` is as DI-pure as the engine; "4 beats per bar" has one home; and the pinned docs (AGENTS.md, v1 behavior-specs) match the code.

## Changes Required

### 1. Engine visual-clock removal (I-5 → R-I5.1)
**Files:** `MyESModules/Playback/playbackEngine.js`, `MyESModules/index.js` (barrel — drop any re-exports that vanish), `MyComponents/PlaybackEngineTest.html`

- Delete `startVisualClock`/`stopVisualClock`/`_rafTick`/`onFrame` and the `stopVisualClock()` calls in `_teardown` and `dispose`; drop `raf`/`cancelRaf` from the factory params **only if** nothing else uses them (verify: the engine's only RAF consumer is the visual clock — if the interrupt watch or anything else uses `_raf`, keep the params and note it).
- `getBeatGrid`/`songPosition` stay (genuine `createBeatDots` dependencies).
- P-12 test deleted with a comment pointing at B-01/B-02 (its observable content lives there).

### 2. Teardown ownership flip (I-6, N-17 → R-I6.1, R-I6.2, B-05 rev, B-06)
**Files:** `MyESModules/App/createBeatDots.js`, `createMetronomadLifecycle.js`, `createMetronomadMethods.js` (call-site signatures), `MyComponents/BeatDotsTest.html`

- `createBeatDots(vm, base, callbacks)` — capture `vm` once; the four methods drop the `vm` argument (N-17).
- `stopAll` tears down visualizer resources only (pending RAF, matchMedia listener, dot classes, `_stopped`) — **no engine access** (R-I6.1 pins this with a spy).
- `beforeUnmount` owns the ordering explicitly: listener removal → `stopAll()` → `engine.dispose()` → `fileLoader.release()`. The existing `else if (this._engine)` fallback stays as defense and gets its own variant test (R-I6.2).

### 3. DI symmetry for `createBeatDots` (I-7 → R-I7.1)
**Files:** `MyESModules/App/createBeatDots.js`, `MyComponents/BeatDotsTest.html`

- `base` gains `raf`, `cancelRaf`, `matchMedia`, `isPageHidden` with `window.*`/`document.*` defaults (RD-6 shape), mirroring the engine's parameter style.
- `BeatDotsTest.html`: **delete** the save/restore patching of `window.requestAnimationFrame`/`window.matchMedia` and the `document.hidden` override; inject fakes. All existing B-01…B-04 rows must pass unchanged via injection — if any row's expectation depended on a real-global quirk, fix the test to assert the injected contract (flag it in the session summary).

### 4. `BEATS_PER_BAR` (I-8 → R-I8.1)
**Files:** `MyESModules/Utils/beatGrid.js`, `MyESModules/App/createBeatDots.js`, `createMetronomadData.js`, `index.html`, `MyESModules/index.js`

- `export const BEATS_PER_BAR = 4` from `beatGrid.js`; accent rule uses it; `DOT_COUNT` derives from it; `beatsPerBar` on Vue data; template `v-for="dot in beatsPerBar"` + `:class="{ 'beat-dot--downbeat': dot === 1 }"` unchanged in output.
- E2E-1.8 (dot row shape) stays green without changes — it is the regression net for this item.

### 5. Doc corrections (N-18)
**Files:** `Metronomad/AGENTS.md`, `MyESModules/App/createMetronomadLifecycle.js` (JSDoc), v1 plan `context.md`

- AGENTS.md **Visual clock ownership** bullet: rewrite per the as-built Phase 2 state — `createBeatDots` (app-level, in `MyESModules/App/`) is the *sole* owner of the visual clock; the engine's visual clock no longer exists. Delete the "tested public capability the app does not use" sentence.
- AGENTS.md **Memory** bullet: `beforeUnmount` order = listener removal → `stopAll` → `engine.dispose()` → `fileLoader.release()` (code already does this; docs catch up).
- AGENTS.md **Howler** bullet: split the `autoSuspend`/`autoUnlock` parenthetical — they are two different features; `autoUnlock` stays default-true deliberately (`howlerSetup.js:27-30`).
- v1 `context.md`: strike the "clear error/toast timers" cleanup step (historical drift — no such timers exist).
- Lifecycle JSDoc: match the final ordering.

### 6. v1 behavior-specs refresh (N-21)
**File:** v1 plan `behavior-specs.md`

- T-08/T-10 `now` inputs: align the rows with the values the tests actually use (101.75 / 102.499) — the tests corrected the stale table; make the table the truth again.
- E2E-2.3's "9:99.9": replace with "9:59.9" (T-22: seconds ≥ 60 is invalid; the test already uses 9:59.9).
- P-12 row: strike through with a pointer to this plan's §6 retirement note. B-05 row: update to the amended text (canonical copy in this plan's `behavior-specs.md` §6).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §6)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I5.1 | P1 | Unit (engine), no visual-clock params | `createPlaybackEngine(...)` | No `onFrame` param; returned object has no `startVisualClock`/`stopVisualClock`; `getBeatGrid`/`songPosition` intact; fake-RAF collector stays empty across start/stop/dispose |
| R-I6.1 | P1 | Unit (beatDots), engine spy with `dispose` recorder, all timers running | `stopAll()` | RAF cancelled, matchMedia listener removed, dots cleared, `_stopped` set — `engine.dispose` **never called** |
| R-I6.2 | P1 | Unit (lifecycle, mock-VM, spies) | `beforeUnmount()` | Order spied: listener removal → `stopAll` → `engine.dispose()` → `fileLoader.release()`, each once; variant with `_beatDots` absent → `dispose` still called via fallback |
| R-I7.1 | P1 | Unit (beatDots) with injected `raf`/`cancelRaf`/`matchMedia`/`isPageHidden`; no global patching in the suite | B-01…B-05 behavior re-run via injection | All assertions pass; `BeatDotsTest.html` contains zero `window.*`/`document.*` monkey-patching |
| R-I8.1 | P1 | `Utils/beatGrid.js` | Import | `BEATS_PER_BAR === 4`; accent rule uses it; dots + template bind to it; E2E-1.8 green unchanged |
| B-05 (rev) | P1 | All visual timers running | `stopAll()` from `beforeUnmount` | No leaks; **no engine access of any kind** |
| B-06 (new) | P1 | See R-I6.2 | Unmount ordering | Engine `dispose` called by the lifecycle, not the visualizer |

*(N-18 and N-21 carry no scenario rows — they are doc-consistency items verified by the grep pass below.)*

## Success Criteria

**Automated:**
- [ ] R-I5.1, R-I6.1, R-I6.2, R-I7.1, R-I8.1, B-05 (rev), B-06 pass.
- [ ] `node scripts/run-tests.cjs` fully green (P-12 removed — the count drops by exactly its size; B-suite rows all present via injection).
- [ ] `npx playwright test` fully green, 23 tests, unchanged by this phase (refactor-only: no user-visible behavior changes; E2E-1.8 is the net for I-8). *Handoff note (Phase 1 close, 2026-08-22): the E2E baseline is 23 after Phase 1's +2 (E2E-R-C1.1, E2E-U-21), not the 21 in the original text.*
- [ ] **Grep pass:** `rg "startVisualClock|stopVisualClock|onFrame|_rafTick" MyESModules/Playback/` → zero hits; `rg "engine.dispose" MyESModules/App/createBeatDots.js` → zero hits; `rg "window\.(request|cancel)AnimationFrame|window\.matchMedia|document\.hidden" MyComponents/BeatDotsTest.html` → zero hits; `rg "DOT_COUNT" MyESModules/App/createBeatDots.js` → definition only, from `BEATS_PER_BAR`.
- [ ] AGENTS.md + v1 `behavior-specs.md` + v1 `context.md` updated per §5/§6 above; no stale "tested public capability" wording remains.

**Manual (user):**
- [ ] Play → dots/progress unchanged from v1 (count-in, song, Stop/Restart, preview, tab-switch snap, reduced-motion).
- [ ] Full page unmounts cleanly (no console errors on navigation away).

**Phase close:** run the handoff audit against Phase 3's scope list before marking done in `index.md`.
