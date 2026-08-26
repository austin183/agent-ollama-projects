# Phase 1: Shippable Gate — C-1 + I-1…I-4 + I-9 (P0)

**Depends on:** nothing (v1 complete; baseline 127 unit / 21 E2E green).

**Context to load:**
- `index.md` → Overview, Open Decisions (OD-1 default assumed confirmed), What We're NOT Doing
- `context.md` → RD-1…RD-5 (fix contracts), Interface Shapes, Testing Strategy, Cross-Cutting Constraints (string inventory)
- `behavior-specs.md` → §1…§5 (this phase's canonical rows)
- Review: `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` → C-1, I-1…I-4, I-9, N-16, N-20, N-22, N-23 (the "why the tests are green" paragraphs state the exact test gap for each)
- v1 plan: `context.md` → D2 (preview clamp), D8 (non-blocking errors), KB-6 (hooks); `behavior-specs.md` → V-03, V-04, V-05, U-10 rows (patterns to mirror)
- Skill: `building-web-apps` → mock-VM construction, in-page transition-logger E2E timing

**TDD workflow:** per finding, failing test first (the review names each one), then the minimal fix, then the next. Suggested order inside the phase: I-1 → I-2 (same choke point, one file) → I-3 → I-4 → I-9 (isolated) → C-1 last (largest surface: data + methods + template + U-11 wording + E2E).

## Overview

Close the review's §8 "before v1 is considered shippable" list: make BPM/count-in typeable per-keystroke, funnel all file acceptance through one guarded choke point with single-flight decode, guard the engine against end-of-song offsets, fix the U-09 stop-during-preview announcement, and make the test runner unable to report green with zero tests. Plus two cheap coverage add-ons (N-22, N-23).

## Changes Required

### 1. File acceptance choke point (I-1, I-2, N-23)
**Files:** `MyESModules/App/createMetronomadMethods.js`, `index.html`, `MyComponents/UiHandlersTest.html`

- `onFileDropped`: guard order per RD-2 — `isParamLocked` check (moved here from `onDrop`, which keeps only the `isDragOver` reset) → `decoding.active` silent return → load.
- `#browseBtn` in `index.html`: add `:disabled="isParamLocked"`.
- N-23: one mock-VM test — after Stop, dropping a *shorter* file re-clamps `offset`/`offsetText` to the new duration (the `clampOffset` call at the ok-path is currently untested).

### 2. Engine boundary guard (I-3)
**Files:** `MyESModules/Playback/playbackEngine.js`, `MyESModules/Utils/paramClamps.js`, `MyComponents/PlaybackEngineTest.html`, `MyComponents/TimingMathTest.html`

- `startSequence` invalid-check: add `offset >= buffer.duration` (RD-4; matches the existing `preview` D2 guard).
- `clampOffset`: quantize-then-reclamp — `Math.min(duration, Math.round(clamped * 10) / 10)`.
- P-13 (rev) engine cases + T-35 timing-math row.

### 3. Preview stop announcement (I-4)
**Files:** `MyESModules/App/createMetronomadMethods.js`, `MyComponents/UiHandlersTest.html`, `MyComponents/PlaybackEngineTest.html`

- `STOPPED` case: read `this.isPreviewing` **before** `_returnToReady` clears it → "Preview stopped" vs "Stopped" (RD-5).
- Engine test: `preview()` → `stop()` → events exactly `['preview', 'stopped']`, stale preview `onended` ignored (R-I4.2).

### 4. Test runner hardening (I-9)
**File:** `scripts/run-tests.cjs`

- Throw (non-zero exit, per-file error) when `mocha._runner` is unavailable **or** `s.tests === 0` — "0 tests" is a failure.
- Remove the runner's own `python3 -m http.server` spawn; use the user-started server on :8000; derive paths from `path.resolve(__dirname, '..')` (R-I9.3; AGENTS.md "from anywhere" rule).
- Verify with a scratch 0-test page (see `context.md` Testing Strategy), then delete the scratch.
- `Metronomad/AGENTS.md` Testing section: `run-tests.cjs` now requires the user-started server on :8000 like the E2E — update the "from anywhere" line to say so (cwd-independence stays true; server-independence goes away).

### 5. Commit-on-Enter/blur entry for BPM + count-in (C-1, N-16, N-20)
**Files:** `MyESModules/App/createMetronomadData.js`, `createMetronomadMethods.js`, `index.html`, `MyComponents/UiHandlersTest.html`, `test/e2e/` (new or extended spec), v1 `behavior-specs.md` (U-11 row wording)

- Per RD-1: `bpmText`/`countInText` drafts + `v-model` + Enter/blur commit; `commitBpmEntry`/`commitCountInEntry`; shared `_restoreLastValid(kind)` (N-16); `countInClamped` hint "Count-in limited to 1–16" (N-20); steppers sync the draft (R-C1.4).
- `onBpmInput`'s parse/clamp core survives inside `_parseParamInput`; the per-keystroke `@input` clamp is deleted.
- **E2E-2.3 update (mechanical, semantics unchanged):** its BPM cases do `fill('#bpmInput', '999')` and assert the clamped value immediately — under the commit pattern each needs a `press('Enter')` (or blur) after the `fill` before the value/hint assertions. The offset cases already commit via Enter/blur and are untouched.
- Update the v1 `behavior-specs.md` U-11 row to the amended text (canonical copy in this plan's `behavior-specs.md` §1) with a pointer.
- E2E-R-C1.1 with `pressSequentially` (the review's live-repro path: `90`, `120`, `250` must all type cleanly).

### 6. Coverage add-ons (N-22)
**File:** `test/e2e/` (smoke or errors spec)

- U-21: upload the fixture via `setInputFiles` with a 40-character `name`; assert `.file-name` is truncated (CSS ellipsis — assert `title` equals the full name; visual truncation is a manual check).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md`)

**§1 Parameter entry:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-11 (rev) | P0 | Ready | User types "999" in BPM and commits (Enter/blur) | Clamps to 250, field shows "250", hint "BPM limited to 30–250"; "10" → 30; non-numeric/empty on commit restores the previous valid value into field and model; stepper buttons change the model by ±1 **and** sync the field |
| R-C1.1 | P0 | Ready, BPM 120, field "120" (unit, mock-VM) | `bpmText` set to `'9'` then `'90'` then `'190'` (simulated keystrokes; no commit) | `this.bpm` **unchanged (120)** after every keystroke; no hint shown; only on `commitBpmEntry()` does the model move (190, no clamp) |
| R-C1.2 | P0 | Ready, count-in 4, field "4" | Type "16" over it keystroke-by-keystroke, then commit | Model stays 4 until commit → 16; typing "1" over "4" (field "1") and blurring commits 1 (valid) — no accidental restore of 4 |
| R-C1.3 | P0 | Ready, field cleared to `''` mid-entry | Blur (commit) with empty field | Model + field restore last valid (120 / 4); no hint |
| R-C1.4 | P1 | Ready, BPM 250 via stepper | Observe field | Field shows "250" (stepper synced the draft) |
| R-C1.5 | P1 | Ready, count-in committed "99" | Commit | Clamps to 16, field "16", hint "Count-in limited to 1–16" shown (N-20) |
| E2E-R-C1.1 | BPM typeable per-keystroke | Load fixture; triple-click `#bpmInput`; `pressSequentially('90')`; Enter | Field "90"; sequence runs at 90 BPM (click spacing ≈ 0.667 s, in-page logger); no display/model divergence at any point |

**§2 File loading:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-13 (rev) | P0 | Playing | Drop **or** Browse | Rejected ("Drop a new song after stopping" / Browse disabled); playing song unaffected — engine buffer, position, fill, `aria-valuemax` never reference the new file. After Stop, same drop accepted: Ready, old buffer dropped + URL revoked |
| R-I1.1 | P0 | `playing` (mock-VM) | `onFileDropped(validFile)` | `loadFile` never called; error message set; `appState` unchanged |
| R-I1.2 | P1 | E2E: `playing` | Observe `#browseBtn` | `disabled` present; drop-path rejection message unchanged (E2E-2.2 stays green) |
| R-I2.1 | P0 | `decoding.active` (mock-VM, non-settling loadFile spy) | Second `onFileDropped` | Second `loadFile` never called; first continuation wins on resolve; `decoding` false exactly once |
| R-I2.2 | P1 | First `loadFile` pending (controllable spy) | Rejected second drop, then resolve first | `decoding.active` true until first resolves — Play never enabled mid-decode |
| R-I2.3 | P0 | Unit: `onFileDropped(a)` pending → `onFileDropped(b)` → settle `a` | | Exactly one buffer in `_buffer` (a's); b's decode never started |
| (N-23) | P1 | mock-VM, Stop done, shorter file dropped | ok-path | `offset`/`offsetText` re-clamped to the new (shorter) duration |

**§3 Engine boundary:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| P-13 (rev) | P0 | Invalid params | `startSequence` with `bpm 0` / `countInBeats 17` / `offset -1` / `offset 3.0` (3.0 s buffer) / `offset 3.0001`; `preview({offset: 3.0})` | All `{ ok: false }`; no sources created; state unchanged |
| T-35 | P0 | `clampOffset(2.96, 2.96)` / `(2.94, 2.96)` / `(3.0, 2.96)` | | `2.9` / `2.9` / `2.9` — never `> duration`; T-31/T-33/T-34 unchanged |

**§4 Preview stop:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-09 (rev) | P1 | Preview playing | User Stop | Stops ≤ 50 ms; reset to offset marker; announced **"Preview stopped"** (both stop paths) |
| R-I4.1 | P1 | mock-VM, `isPreviewing === true` | `onEngineStateChange('stopped')` | "Preview stopped"; `isPreviewing` false; ready |
| R-I4.2 | P1 | Engine (fakes): `preview()` running | `stop()` | Events exactly `['preview', 'stopped']`; stale preview `onended` ignored |
| R-I4.3 | P1 | mock-VM, `isPreviewing === false` | `onEngineStateChange('stopped')` | "Stopped" (non-preview regression) |

**§5 Runner:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I9.1 | P0 | Page loading Mocha, **zero** tests | `node scripts/run-tests.cjs` | Non-zero exit; per-file "0 tests" error |
| R-I9.2 | P0 | `#mocha` present, no `mocha._runner`, no result elements | Run | Non-zero exit; error names file + missing runner |
| R-I9.3 | P1 | Run from arbitrary cwd | Run | Works; no self-spawned server; paths from `__dirname` |

## Success Criteria

**Automated:**
- [ ] All new/rev rows above pass (R-C1.*, R-I1.*, R-I2.*, R-I4.*, R-I9.*, U-11 rev, U-13 rev, U-09 rev, P-13 rev, T-35, N-22/N-23 add-ons).
- [ ] `node scripts/run-tests.cjs` fully green — count > 127 (new tests added, none deleted).
- [ ] `npx playwright test` fully green — 21 + new (E2E-R-C1.1, R-I1.2, U-21 add-on); E2E-2.2 unchanged and green; E2E-2.3 green with the mechanical commit-trigger update above (assertions unchanged).
- [ ] `run-tests.cjs` exit code verified non-zero on the scratch 0-test page (then scratch deleted).
- [ ] V1 `behavior-specs.md` U-11 row updated to the amended text with a pointer to this plan's canonical row.

**Manual (user, with server on :8000):**
- [ ] Type `90`, `120`, `250`, `16`, `1` into BPM/count-in per-keystroke (including select-all-replace and mid-word edits) — field and model always agree; hints appear only on clamped commits.
- [ ] Play → Browse is visibly disabled; drop while playing shows the rejection; a second drop during "Decoding …" is ignored with no flicker in the decoding indicator.
- [ ] Stop during Preview announces "Preview stopped" (screen-reader or DevTools live-region watch).

**Phase close:** run the handoff audit (writing-plans `references/phase-handoff.md`) against Phase 2's context load before marking done in `index.md`.
