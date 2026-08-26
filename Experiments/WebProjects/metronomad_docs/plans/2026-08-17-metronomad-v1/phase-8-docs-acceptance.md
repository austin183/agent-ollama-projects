# Phase 8: Docs, Site Link, Final Acceptance (P1)

**Depends on:** Phases 1–7 complete (full suite green).

**Context to load:**
- `index.md` — Desired End State (what the acceptance checklist proves)
- `context.md` → Design Decisions (for the AGENTS.md architecture summary: Howler scope, raw Web Audio, no Tone.js D6) + Testing Strategy + References
- Phase 6 session summary: `_agent_docs/sessions/2026-08-20-001-build-tdd-phase6-beat-dots-progress-tdd.json` → key_decisions (docs must reflect ACTUAL visual-clock ownership: the **app-level** `createBeatDots` RAF loop drives the dots — visibility pause, tempo `--beat-interval`, reduced-motion classes; the engine's P-12 visual clock `onFrame`/`startVisualClock`/`stopVisualClock` is a tested capability the app does **not** use — do not describe the engine as driving the dots)
- Site integration: `~/workspace/austin183.github.io/index.html` (project-card pattern: `card-icon` + `card-title` + `card-description` + `launch-button`)
- Repo root `AGENTS.md` (commit convention: `Co-Authored-By: LittleLight <noreply@traveler.dstny>`)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

Make the project discoverable and self-documenting; run the final acceptance pass.

## Changes Required

- **Root `index.html`** — add a `project-card` (verified pattern: `card-icon` with material icon e.g. `music_note`, `card-title` "Metronomad", one-paragraph `card-description` — count-in metronome + exact downbeat song start, all in-browser — and `<a href="Metronomad/index.html" class="launch-button">Launch</a>`), placed with the other project cards.
- **`Metronomad/AGENTS.md`** — outline: 1-line purpose; Architecture (static, no build step; Howler for context/codecs/unlock, raw Web Audio lookahead scheduler — no Tone.js); directory tree; Running (`bash start-server.sh` → `http://localhost:8000/Metronomad/index.html`); Testing (`node scripts/run-tests.cjs`; `npx playwright test`); Conventions (named exports, factories, no `waitForTimeout` — assert state + tolerance; audio never asserted by ear in E2E); `_agent_docs/` pointers; `Co-Authored-By: LittleLight <noreply@traveler.dstny>` commit convention.
- Final: run world-review on the completed P1 test files per the skill's Feature Development Workflow (last quality gate).

## Success Criteria

**Automated:**
- [x] Full unit + E2E suite green from a clean server start. (2026-08-21: 127/127 unit across 5 files + 16/16 E2E on the running server; clean-restart re-verify is a user step per the repo's no-agent-server rule.)

**Additional automation added during Phase 8** (post-acceptance TDD rounds, all green): `test/e2e/keyboard.spec.cjs` (item 10 — exact Tab order, locked controls unfocusable, keyboard-only flow + live-region announcements; its RED run found and fixed a stale progress-readout bug — ready-state `songPosition`/`offset` invariant watch in `createMetronomadApp.js`), `test/e2e/reducedMotion.spec.cjs` (item 11 — static dot, no pulse), `test/e2e/visibility.spec.cjs` (U-17 — frozen while hidden, grid-law snap on return). Checklist items below remain the user's manual gate (audio-quality items 4/5 listening and real screen-reader audio are not E2E-able by design).

**Manual (acceptance checklist):**
1. Load a real multi-minute mp3 via drag *and* Browse
2. Scrub + direct offset entry agree
3. Preview confirms entry and preserves offset
4. Clicks crisp; accent clearly higher-pitched
5. Song lands on the downbeat with the dots (listen + watch)
6. Stop/Restart mid-count-in and mid-song — no phantom audio
7. Parameters locked while running; hint visible
8. Ended → Ready, position reset to offset
9. Garbage file → friendly message, app usable
10. Full keyboard pass + live-region announcements
11. Reduced-motion safe
12. Zero console errors
13. 30-minute guard message on an oversized file
