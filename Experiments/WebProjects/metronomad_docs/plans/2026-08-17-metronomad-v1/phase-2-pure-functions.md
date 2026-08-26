# Phase 2: Pure Functions (P0)

**Depends on:** Phase 1 (entry pattern, barrel, playwright config).

**Context to load:**
- `context.md` → File Layout & Module Interfaces (Utils interfaces), Design Decision D1 (T-06)
- Skill: `references/testing-unit.md` (Mocha/Chai in-browser pages), `references/es-modules.md`
- Reference: `CollageMaker/MyComponents/` + `CollageMaker/scripts/run-tests.js`

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

All timing/formatting/clamping math, fully unit-tested. No browser APIs touched.

## Changes Required

- `MyESModules/Utils/{beatGrid,timeFormat,paramClamps}.js` — implement T-01…T-34 (below); every function leads with `Number.isFinite` guards (skill convention).
- Barrel updates; `MyComponents/TimingMathTest.html` (Mocha+Chai CDN page, `mocha.run()` after all describes).
- `scripts/run-tests.cjs` — adapted from `CollageMaker/scripts/run-tests.js` (`BASE_DIR` → Metronomad, `SERVER_ROOT` unchanged; same check-server-then-run behavior).

## Scenarios (T-01…T-34 — full set; canonical copy in `behavior-specs.md` §3.3)

**`beatGrid.js`**

| ID | Input | Output |
|----|-------|--------|
| T-01 | `beatInterval(120)` | `0.5` |
| T-02 | `beatInterval(60)` / `(30)` / `(250)` | `1.0` / `2.0` / `0.24` |
| T-03 | `beatInterval(0)`, `(NaN)`, `(Infinity)` | `NaN` (guarded via `Number.isFinite` + `> 0`; assert the guard) |
| T-04 | `buildSchedule({ tP: 100.0, bpm: 120, countInBeats: 4, offset: 90.0 })` | `{ clicks: [{ time: 100.5, isAccent: true }, { time: 101.0, isAccent: false }, { time: 101.5, isAccent: false }, { time: 102.0, isAccent: false }], songStart: { time: 102.5, offset: 90.0 } }` |
| T-05 | `buildSchedule({ tP: 0, bpm: 30, countInBeats: 16 })` | 16 clicks at 2.0, 4.0, …, 32.0; accents on clicks 1/5/9/13; `songStart.time = 34.0` |
| T-06 | `buildSchedule({ tP: 5, bpm: 250, countInBeats: 1 })` | `clicks = [{ time: 5.24, isAccent: true }]`, `songStart.time = 5.48` (D1: no lead floor) |
| T-07 | `buildSchedule({ tP: 1, bpm: 120, countInBeats: 0 })` | throws `RangeError` (count-in ≥ 1 by contract; UI clamps, engine guards per P-13) |
| T-08 | `beatPhaseFromGrid(102.75, 100.5, 0.5)` | `{ beatIndex: 2, inBeat: 0.5 }` |
| T-09 | `beatPhaseFromGrid(100.49, 100.5, 0.5)` (before first beat) | `{ beatIndex: -1, inBeat: 0 }` — no dot lit during the lead beat |
| T-10 | `beatPhaseFromGrid(104.999, 100.5, 0.5)` | `{ beatIndex: 3, inBeat: 0.998 }` (floor, not round — no wrap to 0 until the true boundary) |
| T-11 | `beatPhaseFromGrid(NaN, 100.5, 0.5)` | `{ beatIndex: -1, inBeat: 0 }` (Number.isFinite guard) |

**`timeFormat.js`**

| ID | Input | Output |
|----|-------|--------|
| T-12 | `formatTime(75.3)` | `"1:15.3"` |
| T-13 | `formatTime(0)` | `"0:00.0"` |
| T-14 | `formatTime(65.25)` | `"1:05.3"` (half-up to tenth) |
| T-15 | `formatTime(3599.94)` | `"59:59.9"` |
| T-16 | `formatTime(600.0)` | `"10:00.0"` (minutes ≥ 10) |
| T-17 | `formatTime(-1)`, `formatTime(NaN)` | `"0:00.0"` (clamped/guarded) |
| T-18 | `parseOffsetInput("1:05.2")` | `65.2` |
| T-19 | `parseOffsetInput("90")` | `90.0` (bare seconds accepted) |
| T-20 | `parseOffsetInput("1:5")` | `65.0` (seconds without tenths) |
| T-21 | `parseOffsetInput("0:00.0")` | `0.0` |
| T-22 | `parseOffsetInput("1:75")` | `null` (seconds ≥ 60 invalid) |
| T-23 | `parseOffsetInput("-5")` | `null` |
| T-24 | `parseOffsetInput("")`, `("abc")`, `("1:2:3")` | `null` |
| T-25 | `parseOffsetInput(90)` (number passthrough) | `90.0` (coerces) |

**`paramClamps.js`**

| ID | Input | Output |
|----|-------|--------|
| T-26 | `clampBpm(119.6)` | `120` (whole numbers, spec §4) |
| T-27 | `clampBpm(251)` / `(29)` | `250` / `30` |
| T-28 | `clampBpm(NaN)` / `(undefined)` | `120` (default) |
| T-29 | `clampCountIn(0)` / `(16.4)` / `(99)` | `1` / `16` / `16` |
| T-30 | `clampCountIn(NaN)` | `4` (default) |
| T-31 | `clampOffset(90, 3.0)` | `3.0` |
| T-32 | `clampOffset(-5, 3.0)` | `0` |
| T-33 | `clampOffset(1.2345, 3.0)` | `1.2` (quantized to tenths — matches display precision) |
| T-34 | `clampOffset(1, NaN)` | `0` (invalid duration guard) |

## Success Criteria

**Automated:**
- [ ] `node scripts/run-tests.cjs` — all 34 T-scenarios pass.

**Manual:** none (pure math).
