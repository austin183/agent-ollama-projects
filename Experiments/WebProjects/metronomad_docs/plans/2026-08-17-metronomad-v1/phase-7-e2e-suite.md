# Phase 7: E2E Suite (P0/P1)

**Depends on:** Phases 3–6 complete (full app behavior: loading, playback, UI wiring, dots/progress) + `data-state`/`data-beat` hooks in the template (KB-6).

**Context to load:**
- `context.md` → Design Decision D11 (fixture source); Known Behaviors KB-3, KB-6 (testability hooks); Testing Strategy → E2E (thin specs, never listen to audio); File Layout (test/ tree)
- `behavior-specs.md` §3.4 — config + waits conventions (no `waitForTimeout` for assertions; `expect`/`expect.poll`; `t0 = performance.now()` at the Play click)
- Phase 6 session summary: `_agent_docs/sessions/2026-08-20-001-build-tdd-phase6-beat-dots-progress-tdd.json` → key_decisions (visual-clock ownership: the **app-level** `createBeatDots` RAF loop drives the dots — visibility pause, tempo `--beat-interval`, reduced-motion classes; the engine's P-12 visual clock is a tested capability the app does NOT use. `data-beat` = zero-based lit dot, "-1" before the first click. Progress is static during preview; the readout throttles to tenth-second changes)
- Skill: `references/testing-e2e.md`, `references/testing-strategy.md`
- Reference: `CollageMaker/test/e2e/` + `CollageMaker/playwright.config.cjs`
- Fixture base64 source: `_agent_docs/research/howler-research-test.html`
- Server: user runs `start-server.sh` (repo rule — agents never start it); playwright.config.cjs has **no** `webServer` block

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

End-to-end verification with the synthesized fixture; timing asserted with tolerance via the data-state/data-beat hooks.

## Changes Required

- `test/fixtures/sine3s.mp3` (decode the base64 from `_agent_docs/research/howler-research-test.html` — one-off, no tooling); `test/fixtures/bad.mp3` (text bytes, tiny).
- `test/e2e/playback.spec.cjs` (E2E-1.1…1.8), `test/e2e/errors.spec.cjs` (E2E-2.1…2.4) per `behavior-specs.md` §3.4.
- Add the `data-state` (body) and `data-beat` (dot row) hooks to the template if not already present (KB-6).

## Scenarios (full set — canonical copy in `behavior-specs.md` §3.4)

**Config reminder:** chromium only, `baseURL: http://localhost:8000`, `workers: 1`, `timeout: 30000`, no `webServer`, plus `use.launchOptions.args: ['--autoplay-policy=no-user-gesture-required']` for deterministic `AudioContext` state in headless.

**`playback.spec.cjs`** — 3 s fixture, 120 BPM (beat = 0.5 s), **count-in 2** → clicks at +0.5 s / +1.0 s, song starts at t0+1.5 s (grid law: t_p+(N+1)·beat — T-04/P-01), song ends ≈ +3.0 s after the start (full lifecycle in ~4.5 s of wall time).

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-1.1 | Load → ready | `setInputFiles('#fileInput', fixture)` | Filename "sine3s.mp3" + duration "0:03.0" visible; `data-state=ready`; Play enabled |
| E2E-1.2 | Full sequence timing | Set count-in 2 → click Play (t0) | `data-state=countingIn` within 300 ms of t0; data-beat shows "0" then "1" before the flip (zero-based lit dot — KB-6; "-1" during lead-in); `data-state=playing` at t0+1.5 s ± 0.3 s; live region "Song started"; progress advances past 0:01.0; `data-state=ready` ≈ 3.0 s after the playing flip ± 0.5 s; progress reset to offset; "Song ended" announced |
| E2E-1.3 | Stop during count-in | Play → `countingIn` → Stop | `ready` within 500 ms; progress 0:00.0; BPM/offset preserved; controls enabled |
| E2E-1.4 | Stop during playback | Play → `playing` → Stop | `ready`; progress reset to offset |
| E2E-1.5 | Restart | Play → `playing` → Restart | `countingIn` → `playing` again; progress restarts from offset |
| E2E-1.6 | Parameter lock | In `countingIn` and `playing` | BPM input, scrubber, offset text, count-in all `disabled`; re-enabled after Stop |
| E2E-1.7 | Preview clamp | Offset 0:01.0 → Preview | Plays from 1.0 s; auto-stops ≤ 2 s (D2 clamp to song end); back to `ready`; offset still 0:01.0 |
| E2E-1.8 | Beat dots in play | Observe 4 dots during a sequence | Dot 1 has distinct class (`beat-dot--downbeat`); active-dot index advances ≥ 1 over 2 observed beats |

**`errors.spec.cjs`**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-2.1 | Decode failure | Upload `bad.mp3` (text bytes named .mp3) | `role=alert` message (no cryptic DOMException text); `data-state` stays `noFile`; then upload the real fixture → `ready` (non-blocking error, D8) |
| E2E-2.2 | Drop lock | Load fixture → Play → `playing` → dispatch file drop | State/filename unchanged; "Drop a new song after stopping" indication |
| E2E-2.3 | Clamps | Offset "9:99.9" → commit; offset "-1" → commit; BPM "999" / "10" | 0:03.0; 0:00.0; 250 / 30, each with clamp hint |
| E2E-2.4 | Non-audio drop | Upload a `.txt` file | Stays `noFile`; no crash; console-error free |

*Note:* a true **codec-reject** E2E is not possible on chromium (it supports every common codec — verified in research §6); that path is covered by unit F-02 (spy) and manually on Safari (U-14).

## Success Criteria

**Automated:**
- [ ] `npx playwright test` — all 12 E2E scenarios pass, 2 consecutive runs green (timing tolerances stable).

**Manual:** none (E2E covers the automatable slice).
