# Phase 5: UI Integration — Play/Stop/Restart/Preview (P0)

**Depends on:** Phase 3 (fileLoader → buffer/duration in state), Phase 4 (playbackEngine API). **P0 acceptance gate — first real-audio moment.**

**Context to load:**
- `context.md` → Design Decisions D2 (preview clamp), D8 (app states, non-blocking errors); Known Behaviors KB-4, KB-5; File Layout & Module Interfaces → **Vue wiring paragraph** (mounted/beforeUnmount ordering, non-reactive `_engine`/`_clock`) + Template essentials
- Skill: `references/vue-options-api.md` (.call(this) binding), `references/testing-unit.md` (mock-VM construction), `references/accessibility.md` (live regions, focus)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

Wire engine ↔ Vue: the full core workflow with real audio.

## Changes Required

- `createMetronomadMethods.js` real handlers (V-01…V-07); `createMetronomadData.js` (decoding flag, errorMessage, announcement); `createMetronomadLifecycle.js` (mounted/beforeUnmount per context.md wiring note); template finalization (lock hints, focus return, drop rejection U-13).
- `MyComponents/UiHandlersTest.html` — mock-VM pattern (spread factory methods first, override spies).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md`)

**Vue app (`createMetronomadMethods`)** — handler contracts tested via mock-VM construction:

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| V-01 | P0 | `ready` state | `onPlayToggle()` | `engine.startSequence` called with `{ buffer, bpm, countInBeats, offset }` matching current controls. In `countingIn`/`playing`/`preview` → `engine.stop()` (single Play↔Stop toggle, spec §14.5) |
| V-02 | P0 | `countingIn`/`playing` | `onRestart()` | `engine.restart(...)` called; in `ready`/`noFile`/`preview` → no-op. After Stop/Restart, the Play/Stop button is refocused (`$nextTick` + state guard) |
| V-03 | P1 | `ready` | `onBpmInput('251')` / `('')` | `bpm = 250` + `bpmClamped = true` (hint shown); empty → restores last valid bpm. `onCountInInput('0')` → 1; `('99')` → 16 |
| V-04 | P1 | `ready`, duration 3.0 | `commitOffsetEntry('1:05.2')` / `('abc')` | Offset = 3.0 + hint; `'abc'` → offset unchanged + hint "Enter the time as mm:ss.t" |
| V-06 | P1 | Any state | `isParamLocked` computed | True in `countingIn`/`playing`/**`preview`** (any running audio); scrubber additionally `tabindex="-1"` when locked (U-12/U-23). Restart's `:disabled` uses `isSequenceRunning` = `countingIn \|\| playing` only — Restart stays disabled during preview (spec §6: Restart is for the count-in/song sequence) |
| V-07 | P1 | State transitions | Live-region text (polite) | "" → "Count-in started" → "Song started" → "Stopped" / "Song ended" / "Preview started" / "Preview stopped" / "Audio was interrupted — press Play to try again". Errors use `role="alert"` |

**User behavior this phase delivers (manual verification set)**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-01 | P0 | App in No-file state | User drags a valid `song.mp3` (3 s) onto the drop zone (or uses Browse) | Drop zone shows "Decoding song.mp3…", Play disabled; after decode: state Ready, filename + duration "0:03.0" shown, Play/BPM/offset/count-in enabled, live region announces "song.mp3 loaded" |
| U-02 | P0 | Ready, `song.mp3` (3.0 s), BPM 120, offset 0:00.0, count-in 4 | User presses Play | Within 150 ms state "Counting in" (button label **Stop**), announced "Count-in started"; clicks at +0.5 s (accent, dot 1 lit), +1.0 s, +1.5 s, +2.0 s; at +2.5 s song starts at 0:00.0 with **no click** (dot 1 pulses), state "Playing", announced "Song started"; progress reads the offset **0:00.0** at the state flip |
| U-03 | P0 | Playing, offset 0:00.0, 3 s song | Song reaches its end | State returns to Ready automatically, progress/position reset to the offset "0:00.0", button label "Play", announced "Song ended" |
| U-04 | P0 | Counting in (click 2 of 4 just sounded) | User presses Stop | All scheduled clicks cancelled — **no click sounds after the stop**; state Ready within 50 ms; offset/BPM preserved; announced "Stopped"; focus returns to the Play/Stop button |
| U-05 | P0 | Playing | User presses Restart | Song stops immediately (< 50 ms, no fade); new count-in begins with first click exactly one beat after the press (120 BPM → +0.5 s); song starts at +2.5 s at the **original offset**; announced "Count-in started" |
| U-06 | P0 | Ready, BPM 120, offset 1:30.0, count-in 4 | User presses Play | The song's first audible sample is the audio at 1:30.0 in the file, beginning on the beat boundary after the 4th click (manual: listen + progress reads "1:30.0" at the state flip) |
| U-08 | P1 | Ready, offset 0:01.0 in a 3 s song | User presses Preview | Song plays from 0:01.0 with **no clicks, no count-in** until the song ends at 0:03.0 (3 s preview clamped to the 2 s remaining, D2); app state stays Ready with button label "Stop"; announced "Preview started"; at end, announced "Preview stopped" |
| U-09 | P2 | Preview playing | User presses Stop | Audio stops within 50 ms; dots + progress reset to the offset marker position; offset preserved; announced "Preview stopped" |
| U-12 | P1 | Counting in (or Playing) | User tries to change BPM / offset / count-in | All three controls disabled **and unfocusable** (Tab skips them), group shows a subtle "locked until next Play" hint; after Stop, new values are used on the next Play |
| U-13 | P1 | Playing | User drops another file on the zone | Drop rejected with "Drop a new song after stopping"; the playing song is unaffected. After Stop, the same drop is accepted: state Ready with new file; old buffer reference dropped and old object URL revoked |

*(U-07, U-17, U-18, U-19, U-22 belong to later phases — see behavior-specs.md §3.1 for the full table.)*

## Success Criteria

**Automated:**
- [ ] V-01…V-07 pass; full unit suite green.

**Manual (first real-audio moment):**
- [ ] U-01…U-09 with a real multi-minute song: count-in lands in tempo; song starts exactly at the offset on the downbeat (listen + watch dots + progress reads the offset at the flip); Stop kills all sound immediately (no phantom clicks); Restart re-counts; Preview works and preserves offset.
