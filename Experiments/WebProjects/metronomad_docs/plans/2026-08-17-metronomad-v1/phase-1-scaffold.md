# Phase 1: Scaffold (P1)

**Depends on:** nothing (first phase).

**Context to load:**
- `index.md` — Overview, What We're NOT Doing
- `context.md` → File Layout & Module Interfaces (directory tree + Template essentials paragraph)
- Skill: `.pi/skills/building-web-apps/SKILL.md` → `references/midiestro-pattern.md`, `references/vue-options-api.md`, `references/es-modules.md`

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

Static UI shell that renders all states, with the repo's standard entry pattern. No audio yet.

## Changes Required

- `index.html` — CDN scripts (vue.global.js, howler.min.js 2.2.3, shared `../src/css/variables.css` + `../src/css/Style.css` + `./Style.css`, `../src/js/themeSwitcher.js`), `#app` template with all regions (drop zone, file row, controls, dots, progress, live regions) driven by `appState`.
- `Style.css` — layout, drop zone hero, beat dot base styles, reduced-motion variant hook.
- `MyESModules/App/createMetronomad{App,Data,Methods,Lifecycle}.js` — stubs (data only: `appState: 'noFile'`, defaults bpm 120 / countIn 4 / offset 0); `MyESModules/index.js` barrel.
- `playwright.config.cjs` — per `behavior-specs.md` §3.4 config note (chromium only, `:8000`, autoplay flag, no `webServer`).
- `test/e2e/smoke.spec.cjs` — page-load smoke.

## Success Criteria

**Automated:**
- [ ] `npx playwright test` smoke passes: page loads at `http://localhost:8000/Metronomad/index.html` with zero console errors; `data-state=nofile`; drop zone visible; all controls present and disabled.

**Manual:**
- [ ] User confirms layout reads well: drop zone hero in no-file state; controls grouped and labeled.
