# Phase 6: Beat Dots, Progress, Clock Hygiene (P1)

**Depends on:** Phase 4 (engine contracts: `getBeatGrid()` P-10, `onFrame`/`startVisualClock`/`stopVisualClock` P-12, `songPosition`), Phase 5 (Vue handlers, template shell).

**Context to load:**
- `context.md` → Design Decision D9 (beat phase as pure function of the audio clock — the core idea of this phase); Known Behaviors KB-6 (testability hooks); File Layout & Module Interfaces → `createBeatDots` interface + Template essentials (dots row, progress bar, aria-labels); Performance Considerations → Per-frame (text re-render only when the tenth-second changes)
- Skill: `references/testing-unit.md` (RAF callback-collector mocking), `references/accessibility.md` (reduced motion, aria-label)
- Pure function already built in Phase 2: `beatPhaseFromGrid` (T-08…T-11) — the dot loop calls it; do not reimplement

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

Visual beat reference + progress + the visibility/reduced-motion behaviors.

## Changes Required

- `MyESModules/App/createBeatDots.js` (B-01…B-05, D9); `Style.css` (pulse + `prefers-reduced-motion` static variant, U-22); template (dots, progress bar, offset marker, aria-labels B-04).
- `MyComponents/BeatDotsTest.html` — RAF mock + `matchMedia` stub.

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §3.2)

**createBeatDots (UI layer, callback injection per skill convention)**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| B-01 | P1 | Mock `vm` with `beatPhase: { beatIndex: 2, inBeat: 0.5 }` (RAF mocked with the callback-collector pattern) | One RAF flush | Dot index 2 has class `beat-dot--active`; next frame with `beatIndex: 0` → dot 0 active, dot 2 not |
| B-02 | P1 | Dots running | `visibilitychange` → hidden, then visible | Hidden: RAF loop paused (no further `onFrame`). Visible: one immediate re-render from `engine.getBeatGrid()` + `clock.currentTime` — dots snap to the correct beat (U-17) |
| B-03 | P2 | `matchMedia('(prefers-reduced-motion: reduce)').matches === true` | Beat active | Active dot gets class `beat-dot--static` (no `--pulse`); media change updates live |
| B-04 | P1 | `songPosition 1.5, duration 3.0, offset 1.0` | Render | Progress fill width `50%`; offset marker left `33.333%`; progress region `aria-label` = "Song position 0:01.5 of 0:03.0, entry at 0:01.0" |
| B-05 | P1 | All visual timers running | `stopAll()` (called from `beforeUnmount`) | Cancels RAF + watch interval (spied) — no leaks after unmount |

**User behavior this phase delivers (manual verification set)**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-17 | P1 | Playing | User switches tabs ≥ 5 s and returns | Beat dots instantly on the correct beat (recomputed from the audio clock — no stutter, no drift); progress continuous |
| U-22 | P2 | `prefers-reduced-motion: reduce` | Playing | Beat dots use a static highlight (no pulse animation) |

## Success Criteria

**Automated:**
- [x] B-01…B-05 pass; full suite green.

**Manual:**
- [x] U-17: tab switch mid-play → dots snap to correct beat, no drift; U-22 reduced motion; dots visually lockstep with clicks at 120 and 250 BPM.
