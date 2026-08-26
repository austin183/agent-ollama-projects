# CR 001 Staged Changes — diff-review + solid-review

**Date:** 2026-08-25
**Scope:** All staged changes on branch `prototype/metronomad` (27 files, ~3875 insertions) — CR 001: waveform canvas + offset scrubbing + tempo-detection BPM suggestion.
**Method:** Two subagent passes over `git diff --cached`:
- **diff-review** — high-signal bugs + AGENTS.md violations only, with learnings injected to suppress known intentional patterns (float32 test expectations, Proxy ctx mocks, synthetic PointerEvent E2E drivers, barrel conventions, Vue factory duplicate-key hazard).
- **solid-review** — SOLID / separation-of-concerns / best-practice pass, calibrated by real-world impact, told not to re-report findings from `2026-08-22-metronomad-v1-code-review.md` or flag documented intentional test patterns.
- F-1 and F-2 below were additionally spot-verified against the working tree by the reviewer session (import list at `createMetronomadMethods.js:9`, barrel at `index.js:34–40`, CSS clamp at `Style.css:326–328`, `base = {}` at `createMetronomadLifecycle.js:91`).

## diff-review result

**No issues found. Checked for bugs and AGENTS.md compliance.**

What it validated (not findings):
- Syntax-check clean on every new/modified module and test script; all barrel exports resolve; no duplicate factory keys in `createMetronomadMethods`/`Data`/`App`.
- The barrel import cycle (F-1 below) is **safe at runtime today**: `channelArrays`/`detectTempo` are function declarations referenced only at call time, after full module evaluation.
- `tempoDetection.js` guards verified (`pMax < pMin`, `refinePeriod` neighbor bounds, `corrAt` range guards, `inBandAlias` bounds).
- `createWaveformView` drag state machine: every exit path funnels through `_endDrag`, guarded by `_dragPointerId === null`; `dispose()` idempotent.
- `_analysisValid` three-clause guard checked before and after both async tasks; `beforeUnmount` order matches AGENTS.md exactly.
- `onWaveformKeydown`'s missing `isParamLocked` guard is the pinned D-G spec, not a bug (canvas `tabindex="-1"` when not ready; `aria-disabled` keeps it operable per R-1).
- All test imports resolve; UiHandlersTest method references exist; E2E helpers exist in `helpers.cjs`; synthetic-PointerEvent / Proxy-ctx / float32-exact usage matches documented intentional patterns.

## solid-review findings (to address)

### F-1: Warning — Production circular module dependency via the barrel

**File:** `MyESModules/App/createMetronomadMethods.js:9`

```js
// Barrel import for the Phase-6 analysis names (R-11 discipline): if a
// re-export is ever removed, the module graph breaks loudly instead of
// silently yielding undefined.
import { channelArrays, detectTempo } from '../index.js';
```

The barrel re-exports `createMetronomadMethods` (`index.js:40`), so this creates a **cycle in the production module graph**: `index.js → createMetronomadMethods.js → index.js`. Works today only because both names are used inside method bodies (call-time) — diff-review confirmed no runtime defect.

- The stated rationale doesn't survive contact with ES-module semantics: a direct import from `./Analysis/channelData.js` / `./Analysis/tempoDetection.js` fails *equally loudly* (link-time `SyntaxError`) if the export is removed. The barrel indirection only additionally guards the barrel's own re-export lines, which three test files already import through the barrel.
- Fragile in one direction: any future *top-level* (evaluation-time) use of those names in this module hits a TDZ `ReferenceError` from the cycle — a hard-to-diagnose failure a direct import would not have.
- No other production module imports the barrel (`index.html` imports direct paths), so this is the only production edge in the cycle and it is new in this change.

**Fix (one line):** import directly — `import { channelArrays } from '../Analysis/channelData.js'; import { detectTempo } from '../Analysis/tempoDetection.js';` — and drop the R-11 comment (the barrel stays link-checked by the test suites).

### F-2: Suggestion — Waveform backing-store height ignores the W-4 CSS clamp (vertical squish ≤375 px)

**Files:** `MyESModules/App/createWaveformView.js:44` (`base.getHeightCss || (() => 64)`), `MyESModules/App/createMetronomadLifecycle.js:91` (passes `base = {}`, so the 64 default is always used), `Style.css:326–328` (`@media (max-width: 375px) { .waveform { height: 48px; } }`).

The canvas backing store is sized `widthCss × 64` at init and on every resize, but at ≤375 px viewports the CSS box is 48 px. `#waveformCanvas` stretches to the box (`inset: 0; height: 100%`), so the waveform renders at 48/64 scale — amplitudes 25 % compressed, 1-px columns at 0.75 device px. E2E-3.4 pins only the container's computed height, so the suite is blind to the mismatch.

**Fix:** default `_getHeightCss` to measuring the container (`_canvas.parentElement.clientHeight`) at init/resize (mirroring what resize already does for width), or inject a height provider from the lifecycle; add one E2E-3.4 assertion that `#waveformCanvas.height / devicePixelRatio` equals the container height at a 360 px viewport.

### F-3: Suggestion — `formatTime` exposed as a template method for one ARIA binding

**File:** `index.html:189–199`

```js
import { formatTime } from './MyESModules/Utils/timeFormat.js';
…
methodsConfig: { ...createMetronomadMethods(), formatTime },
```

A pure utility is widened into the VM's method surface for a single inline binding (`:aria-valuetext="'Offset ' + formatTime(offset)"`, `index.html:154`). The file's established pattern is a computed (`formattedDuration`, `formattedPosition`, `formattedDisplayPosition`). A small `offsetAriaText()` computed in `createMetronomadApp.js` keeps the utility out of the instance-method surface and keeps string shaping in one place. Minor, but it sets a precedent that any template convenience can bypass the data/computed layer.

### F-4: Suggestion — Percent-of-duration math duplicated in four computeds

**File:** `MyESModules/App/createMetronomadApp.js:51–93`

`progressPercent`, `offsetMarkerPercent`, `playheadPercent`, and `markerPercent` each repeat the same guard+clamp+divide:

```js
if (!Number.isFinite(this.duration) || this.duration <= 0) return 0;
const clamped = Math.min(Math.max(v, 0), this.duration);
return (clamped / this.duration) * 100;
```

The change deliberately left the two pre-existing computeds untouched (R-4 — defensible), but extending a 2-copy duplication to 4 copies is where extraction pays: a private `percentOf(v)` helper (or one computed the others delegate to) removes three copies of the invariant. Cosmetic; no behavior risk.

## Summary

| ID | Severity | Title | Location |
|----|----------|-------|----------|
| F-1 | **Warning** | Production circular dependency via the barrel (`index.js ↔ createMetronomadMethods.js`); direct Analysis imports give the same link-time loudness without the cycle | `createMetronomadMethods.js:9` |
| F-2 | Suggestion | Canvas backing store fixed at 64 px while the W-4 CSS clamp makes the box 48 px at ≤375 px viewports → 25 % vertical squish; E2E-3.4 blind to it | `createWaveformView.js:44`, `Style.css:326–328` |
| F-3 | Suggestion | `formatTime` widened into the template method surface for one ARIA binding; a computed matches the file's pattern | `index.html:189–199` |
| F-4 | Suggestion | Guard+clamp+percent math duplicated across four computeds | `createMetronomadApp.js:51–93` |

**No Critical findings** — no runtime hazard (div-by-zero, race, unhandled rejection, or resource leak) identified in the staged change.

## Explicitly cleared (not findings — do not re-litigate)

- **View/DSP boundary leakage:** none. `createWaveformView` reads only `vm.duration` (at event time); the VM owns all scrub state; `poolPeaks`/`extractPeaks` never see the view or the engine.
- **`_bpmTouchedThisFile` placement:** cohesively in the methods layer; set at all four touch points (commit incl. garbage-restore, ± step, keystroke), reset only in the load ok-branch; quantization funnels to `clampOffset`, formatting to `formatTime` — no `Utils/` duplication.
- **Async tasks / generation guards / teardown:** verified airtight for drop-while-decoding, unmount-mid-task, and failed-load-no-bump interleavings; post-compute re-checks are harmless since the computes are synchronous.
- **`{ ...peaks }` shallow copy in `_runPeakExtraction`:** arrays shared but never mutated by the view (`poolPeaks` reads only).
- **Tempo hint + live-region double read:** pre-decided UX-6 item with a CR-level remedy path (learning `2026-08-25-doc-phase-gates-and-double-announced-events.md`, rule 2) — intentional.
- **Test mock patterns** (float32 exact-equality expectations, Proxy ctx mocks, synthetic PointerEvent E2E drivers): all documented intentional patterns per `_agent_docs/learnings/archived/`.
- **Skill/doc updates** (`../skills/building-web-apps/`): consistent with the code as-built.

## Disposition

- **F-1: RESOLVED (2026-08-25, same session).** `createMetronomadMethods.js` now imports `channelArrays` from `../Analysis/channelData.js` and `detectTempo` from `../Analysis/tempoDetection.js` directly; the R-11 barrel-import comment was dropped. No production module imports the barrel anymore (grep-verified); the barrel stays link-checked by the test suites, which import through it. Verified: full unit suite green (228 passes / 0 failures, 8 suites) and full E2E suite green (37 passed). Zero behavior change.
- **F-2: RESOLVED (2026-08-25, same session, TDD).** The default `_getHeightCss` now measures `_canvas.parentElement.clientHeight` (fallback 64 with no box), mirroring the width measurement in `_onWindowResize`; production injects no provider, so the backing store now tracks the W-4 clamp in both directions. RED→GREEN: new unit row **WF-V1.11** (`WaveformViewTest.html`; `makeEnv` gained a `noDefaultHeight` option to exercise the factory's own default) failed `expected 64 to equal 48` pre-fix, green post-fix. E2E-3.4 extended with backing-store assertions at both 360 px (48) and 1280 px (64): `#waveformCanvas.height / devicePixelRatio === parentElement.clientHeight`. AGENTS.md test range updated to WF-V1.1…WF-V1.11.
- **F-3: RESOLVED (2026-08-25, same session).** New `offsetAriaText()` computed in `createMetronomadApp.js` ("Offset " + `formatTime(offset)`); `index.html` binds `:aria-valuetext="offsetAriaText"`, drops the `formatTime` import, and `methodsConfig` is back to bare `createMetronomadMethods()`. String contract unchanged — E2E-3.9 still pins `Offset 0:00.0`. `skills/building-web-apps/references/testing-e2e.md` updated: the template-scope lesson stays, the fix guidance now names the computed as the canonical form (methodsConfig merge = works but widens the method surface), and the "don't substitute a different expression" bullet no longer cites a precomputed binding as the anti-pattern (the contract is the string, not the expression).
- **F-4: RESOLVED (2026-08-25, same session).** Module-level `percentOfDuration(duration, value)` in `createMetronomadApp.js` (guard → clamp → percent, 0 for non-positive/non-finite duration); all four computeds (`progressPercent`, `offsetMarkerPercent`, `playheadPercent`, `markerPercent`) delegate to it — math unchanged. The R-4 comment now records the supersession (Phase 4 left the pair untouched; F-4 extracted the shared law without changing math). Behavior pinned by existing unit + E2E coverage (playhead/marker/progress rows all green).

**Verification for F-2…F-4:** full unit suite green (229 passes / 0 failures, 8 suites — incl. new WF-V1.11) and full E2E suite green (37 passed).
