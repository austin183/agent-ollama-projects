# Phase 3: Nit Backlog — Curated (P2, scoped on pickup)

**Depends on:** Phase 1 (same-file nits build on its rewrites) and Phase 2 (engine/beatDots nits build on the RD-6 shapes).

**Context to load (for the scoping session, not for execution):**
- `index.md` → Open Decisions OD-2/OD-3
- `context.md` → Cross-Cutting Constraints (string inventory, KB numbering — next free ID **KB-11**)
- Review: `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` → Nits N-1…N-33 (each self-contained with location + fix)
- `_agent_docs/sessions/2026-08-22-002-build-tdd-address-v1-review-phase2-design-hygiene.json` — the as-built RD-6 shapes Phase 3 items build on (`createBeatDots(vm, base, callbacks)` + injected browser globals, the `beforeUnmount` order with the engine-dispose defense as a plain `if` — not the RD-6 prose's `else if` —, and the `BEATS_PER_BAR` home for "4")

**This file is a scope list, not a build spec** (per `index.md`): the review already carries each nit's location and fix, so no scenario tables are pre-authored here. When the scoping session schedules an item, it (a) gets a scenario row in `behavior-specs.md` if it has testable behavior, (b) becomes a `phase-3-N-<slug>.md` file following the phase template, and (c) is added to `index.md`'s phase map. Items below are in the review's recommended order; the OD-2 default deferrals are marked.

## Scope list (with planning-pass dispositions)

### Batch A — Engine / fileLoader hygiene (after Phases 1–2; `build-tdd`)
| Item | Disposition | Note |
|------|-------------|------|
| N-1 | **Do** | Clear the 25 ms scheduler interval at the PLAYING flip (all clicks precede `songStart.time`); pin with a fake-timer count assertion |
| N-2 | **Do (docs)** | Record as **KB-11** in v1 `context.md` (background-tab interval throttling → compressed count-in; song start stays exact, dots self-heal). The optional >50 ms skip is a behavior change — **defer** with the KB |
| N-3 | **Do** | Delete the dead object-URL lifecycle from `fileLoader` (created/tracked/revoked, never consumed — grep-verified) or consume it; planning default: **delete**, collapse the contract to "exactly one decoded buffer live"; F-05 row updates accordingly (new row in `behavior-specs.md` at scoping). `extractExt` visibility decision at the same time |
| N-4 | **Do** | `startSequence` returns a frozen copy view (or test-only accessor) instead of the live `_seq` |
| N-5 | **Do** | Interpolate `maxDurationSec` into the `tooLong` message |
| N-6 | **Do** | Extract `_finish(event)` for the duplicated terminal-transition pattern |
| N-7 | **Do** | Export `ENGINE_EVENTS`; replace the magic `'ended'`/`'previewEnded'` literals in `createMetronomadMethods.js` |

### Batch B — App / template polish (after Phase 1; `build-tdd`)
| Item | Disposition | Note |
|------|-------------|------|
| N-8 | **Do** | Clear `errorMessage` where its condition resolves (tap-works, Stop-unlocks) or add a dismiss "×" — pick at scoping; new strings must pass the string-inventory check |
| N-9 | **Do** | Cache `--beat-interval` (same trick as the position readout) — Phase 2's `createBeatDots` rewrite is the natural home if not folded in there |
| N-10 | **Do** | Progressbar: static `aria-label` + `aria-valuetext="formatTime(songPosition)"` (B-04 row updates — B-04 currently pins the churning label) |
| N-11 | **Defer** (OD-3 default: No) | Spec-defensible as-is; revisit only if a user reports preview reads as broken |
| N-12 | **Do** | `announcement = 'Count-in restarted'` in `onRestart`'s ok path (V-07 string inventory +1, spec-consistent) |
| N-13 | **Do** | Dragover flicker: `pointer-events: none` on `.drop-zone > *` (cheapest; no counter state) |
| N-14 | **Do** | Post-`await` guard in the resume path: `if (!this._engine) return;` — unmount-during-resume; mock-VM test |
| N-15 | **Do** | Drop the redundant scrubber `:tabindex` (disabled already removes it) |

### Batch C — Docs / KB / spec consistency (no code; `build-docs`)
| Item | Disposition | Note |
|------|-------------|------|
| N-19 | **Do** | Pick one offset format story: planning default — keep `formatTime` (unpadded minutes, matches every display) and fix the placeholder/hint to "m:ss.t" |
| N-20 | *Already in Phase 1* | Count-in clamp hint (folded with C-1 — same lines) |
| N-21 | *Already in Phase 2* | v1 behavior-specs stale rows |
| N-28 | *Closed at review time* | Deferred decision recorded as KB-10 in v1 `context.md` — nothing to do |
| N-32 | **Do (docs)** | Record rapid-live-region coalescing at high BPM / count-in 1 as a known AT behavior (KB-12) |
| N-33 | **Do (docs)** | Backgrounded tab keeps audio playing — record as KB so it isn't "fixed" later (KB-13; or fold into KB-11 if the scoping session prefers one "background behavior" entry — decide at scoping) |

### Batch D — Test quality (cheap; `build-tdd`)
| Item | Disposition | Note |
|------|-------------|------|
| N-22 | *Already in Phase 1* | U-21 ellipsis E2E |
| N-23 | *Already in Phase 1* | Offset re-clamp VM test |
| N-24 | **Do (docs)** | Document the scoping: U-18 stays unit-adequate (P-11 + V-07); the `ctx.suspend()` E2E variant is dropped due to headless suspend quirks — note in v1 `behavior-specs.md` U-18 row |
| N-25 | **Do** | Import `SCHEDULER.RESUME_TIMEOUT_MS` in the real-timer test; assert against the constant |
| N-26 | **Do** | E2E-1.3: assert `actionT < playing.t` instead of the self-imposed `< 450` bound |
| N-27 | **Do** | `_refocusPlayStopButton` disabled-branch test (mock button `disabled: true`) |

### Batch E — Mobile touch cluster — **Deferred** (OD-2 default)
| Item | Disposition | Note |
|------|-------------|------|
| N-29 | Defer | Scrubber touch target (WCAG 2.5.8) — CSS-only, small; schedule when mobile use is real |
| N-30 | Defer | iOS double-tap zoom pin (`font-size: 16px`, `-webkit-text-size-adjust`) |
| N-31 | Defer | Hide native number spinners (BPM duplicates the custom steppers) |
| N-28 (upgrade path) | Defer | If mobile becomes the target: vendor vue/howler + inline SVG + hand-written SW (KB-10 documents the path) |

## Success Criteria (for the phase as a whole, after all scheduled items land)

**Automated:**
- [x] Every "Do" item above either has passing tests or is a docs item verified by reading (KB-11/KB-12/KB-13 present in v1 `context.md` with the reserved numbering; KB-10 kept its ID).
- [x] `node scripts/run-tests.cjs` and `npx playwright test` fully green at each batch's commit — 2026-08-22: unit 158/158, E2E 23/23. (Deviation: batch-level commits A/B+D rather than per-item — the item changes share files, and hunk-splitting them was error-prone; each commit message lists its items.)
- [x] String inventory re-audited: N-8 adds zero strings (clearing only); N-12 adds "Count-in restarted" — consistent with the spec §10 exemplary family ("Count-in started", "Song started", "Stopped") and exactly what review N-12 requested.

**Manual (user):**
- [ ] Spot-check the touched surfaces (error banner lifecycle, restart announcement, dragover, scrubber) — 5-minute pass, no deep re-acceptance.

**Phase close:** mark the plan complete in `index.md` only when every scheduled item is done or explicitly deferred with a recorded rationale; session summary notes any items deferred mid-phase.
