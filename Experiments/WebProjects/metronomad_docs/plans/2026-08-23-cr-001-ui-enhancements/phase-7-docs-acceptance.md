# Phase 7: Docs + Acceptance (P2)

**Depends on:** Phases 5 and 6 complete and green (all WF-\*/TD-\*/E2E-3.x/E2E-4.x rows passing; `#offsetScrubber` gone; tempo prefill live).

**Context to load:**
- `index.md` → Overview, Desired End State, What We're NOT Doing
- `context.md` → **Known Behaviors KB-14…KB-17 in full**, CR §4 limitations, D-K (fixture provenance note for AGENTS.md), Cross-Cutting Constraints (strings, commits)
- As-built: `Metronomad/AGENTS.md` (Architecture / Directory / Running / Testing / Conventions sections), `_agent_docs/plans/2026-08-17-metronomad-v1/context.md` (KB list — append KB-14…KB-17 after KB-13 at `:149`), `_agent_docs/project-timeline/project-timeline.md` (milestone history), this plan's as-built `MyESModules/Analysis/` + `MyESModules/App/createWaveformView.js` (docs must describe what shipped, not what was planned — diff first)
- CR: `_agent_docs/specifications/change-requests/2026-08-23-001-ui-enhancements.md` → §1.8 + §2.6 (draft acceptance criteria — the manual checklist source)

**Workflow:** docs phase — no TDD. Read the as-built code, update the docs to match (fix the *plan* if as-built diverged from it, per the phase-handoff rule), run the acceptance checklist with the user, close out the plan. No scenario rows are owned by this phase; every row below is a verification step.

## Overview

Make the pinned docs true (AGENTS.md, v1 KB list, timeline), run the full manual acceptance pass the automation can't (screen readers, reduced motion, real-world tempo accuracy, low-end mobile), and close the plan.

## Changes Required

### 1. `Metronomad/AGENTS.md`
**Changes** (match as-built; the v1-review plan's Phase 2 set the precedent for how these sections read):
- **Architecture**: add the two new facts — (a) `MyESModules/Analysis/` pure signal modules (`channelData`, `waveformPeaks`, `tempoDetection`), barrel-exported; (b) `createWaveformView` (app-level, in `MyESModules/App/`) is DI-pure like the engine/beatDots and owns only canvas + its own listeners; the app-level RAF loop in `createBeatDots` remains the **sole** visual-clock owner — the playhead is a DOM overlay riding the existing 10 Hz `songPosition` throttle (KB-14: it stays under reduced-motion).
- **Directory** tree: add `Analysis/` (3 modules), `App/createWaveformView.js`, `MyComponents/WaveformPeaksTest.html` / `TempoDetectionTest.html` / `WaveformViewTest.html`, `test/e2e/waveform.spec.cjs` / `tempo.spec.cjs`, `test/fixtures/clicks20.wav` (+ `scripts/make-clicks20-wav.cjs` provenance note), and note `#offsetScrubber`'s replacement by the canvas slider.
- **Testing** conventions: add — engine/view unit tests open no real AudioContext (tempo trains are in-page `Float32Array` synthesis); `clicks20.wav` is the known-tempo E2E fixture (120 BPM, reproducible via the generator script).
- **Conventions**: add the two new user-facing strings to the inventory note; note the KB-6 hooks `#waveformCanvas[data-loaded]` / `#waveformPlayhead[data-position-tenths]` (no styling, no ARIA); the post-load analysis tasks' `_analysisValid` generation guard (D4 discipline applied to UI-side async — the `_disposed` unmount half).

### 2. v1 plan `context.md` — append KB-14…KB-17
**Changes:** after KB-13 (`:149`), append the four Known Behaviors verbatim from this plan's `context.md` §Known Behaviors (KB-14 reduced-motion playhead stays; KB-15 tempo heuristic limitations; KB-16 paint gate + placeholder during re-decode; KB-17 raw-float `aria-valuemax`). Each entry states the decision date (2026-08-23) and the CR reference.

### 3. Manual acceptance checklist (run with the user; the CR §1.8/§2.6 criteria, refined)
- [ ] **Screen reader — slider:** VoiceOver *and* NVDA: focus the canvas in Ready → announces as a slider, "Start offset", value = the offset (`Offset m:ss.t`); ←/→ move 0.1 s, Shift 1 s, PageUp/Down 10 %, Home/End 0/duration; each move's value is queryable; focus returns to the canvas after a pointer drag.
- [ ] **Screen reader — progressbar:** the readout announces as a progressbar with the song position; during playback its value changes at 10 Hz **without announcement churn** (it is not a live region — W-10 by construction); the two roles are distinct and never confused.
- [ ] **Screen reader — tempo suggestion double-read (UX-6, context.md Code World-Review Addendum):** drop `clicks20.wav` in VoiceOver (and NVDA if practical): the prefill announces twice by construction (hint `<p role="status">` + the live region — both CR-pinned). Judge whether the double-read is acceptable UX; if not, the remedy is a CR-level spec change (one pinned surface yields), NOT an in-plan markup edit.
- [ ] **Reduced motion:** OS reduced-motion on → beat dots go static (existing behavior), the playhead **still moves** in tenths (KB-14 — confirm it was not suppressed); waveform itself is static art (no animation).
- [ ] **Tempo accuracy on real songs:** 3–5 real songs with known BPMs (steady rock, a half-time-feel track, an intro-heavy track, a drumless/odd one): the prefill is a useful guess or absent — **no confidently-wrong suggestion** (the W-13 product principle); the user's correction is never clobbered.
- [ ] **Playback regression (the precision path is frozen):** click pitch (accent vs regular) and downbeat exactness unchanged — the manual-acceptance items from v1; Play at an offset set by *dragging the waveform* starts sample-accurate (the engine never saw any of this CR's UI).
- [ ] **Low-end mobile (or throttled DevTools):** 30-min-class file — decode → Ready unhitched (peaks yield after Ready, W-6); if a visible hitch appears, the documented fallback is chunked processing (CR §1.2) — record it as a follow-up CR, do not fix in this plan.
- [ ] **Memory:** reload/unmount cycles leave no GPU/listener growth (canvas `dispose()` zeroes the backing store; devtools heap stable across 5 load/unmount cycles).

### 4. Plan close-out
**Changes:**
- `_agent_docs/project-timeline/project-timeline.md`: add the milestone (CR 2026-08-23-001 shipped: waveform progress + offset scrubbing + tempo suggestion; unit/E2E final counts).
- `index.md` phase map: all 7 phases ✅ done with final test counts (after the checklist passes).
- Re-run the integrity check (index.md footer command) and confirm the session summaries for Phases 1–6 exist in `_agent_docs/project-timeline/sessions/`.
- Commit is `build-quick-work`'s responsibility (per repo pattern) — this phase prepares the commit message content: what shipped, the O-1 scrubber removal (user-visible), and the two new strings.

## Scenarios owned by this phase

None — this phase verifies and documents. Every behavior it checks is pinned by an earlier phase's rows (WF-P1.\*/TD-1.\*/WF-V1.\*/WF-I1.\*/WF-I2.\*/TD-U1.\*/E2E-3.x/E2E-4.x) or is a manual-only acceptance item above.

## Success Criteria

**Automated:**
- [ ] `node scripts/run-tests.cjs` fully green (final count recorded in the phase map); `npx playwright test` fully green (final count recorded).
- [ ] `bash .pi/skills/writing-plans/script/plan-integrity-check.sh _agent_docs/plans/2026-08-23-cr-001-ui-enhancements --ids 'WF-[PIV]1\.[0-9]+|TD-U1\.[0-9]+|TD-1\.[0-9]+|E2E-[34]\.[0-9]+'` → OK.
- [ ] Grep pass: `rg "offsetScrubber" index.html test/ MyComponents/ MyESModules/ Metronomad/AGENTS.md` → zero (docs carry no stale references); `rg "KB-1[4-7]" _agent_docs/plans/2026-08-17-metronomad-v1/context.md` → all four present, appended after KB-13.
- [ ] AGENTS.md Directory tree matches `ls MyESModules/Analysis MyComponents test/e2e test/fixtures` (no phantom files, no missing ones).

**Manual (user):**
- [ ] The full §3 checklist above, signed off — especially the dual SR pass and the "no confidently-wrong BPM" real-song check.

**Phase close:** final — flip the phase map, record the milestone; no handoff audit needed (no next phase).
