# Review Findings Are Plan-Ready: Light Planning Pass, Cluster by File Ownership, Pin Amendment Canonicality

**Date:** 2026-08-22
**Context:** Metronomad v1 shipped (8/8 phases, 127 unit + 21 E2E green), then a six-pass full code review (`_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md`) came back "Request changes": 1 CRITICAL, 9 IMPORTANT, 33 nits — each with file:line location, a concrete fix, the exact test that should pin it, and a §8 tiered action plan. The question was whether the response needed a full BDD planning session. It didn't — the review *was* 90% of a plan. A light planning pass produced `_agent_docs/plans/2026-08-22-address-v1-review/` (index + context with RD-1…RD-6 fix contracts + behavior-specs + 3 phase files, ~550 lines) in one session, with the planning work being transcription + scoping + clustering, not design.

## Why a full planning pass was the wrong cost

The v1 plan workflow (plan-bdd: world-review + planner delegation, full scenario derivation) exists for *behavior that doesn't exist yet*. Here every fix already had:
- **Location** (file:line, verified accurate against source during the planning pass),
- **Fix contract** (the review's "Fix:" paragraphs are implementable as written),
- **Named regression tests** (the "why the tests are green" paragraphs state the exact test gap — e.g., C-1's "feed `'9'` then `'0'`, model untouched until commit" is the flagship regression, written by the reviewer),
- **Tiering** (§8: shippable gate ~1 session / design hygiene ~half session / nice-to-have backlog).

Re-running discovery, research, or scenario derivation would have re-derived what the review already pinned — the same failure class as the 2026-08-20 handoff-drift learning, but in the planning direction: *correct artifacts, redundant work*.

## The Rule

1. **A review is plan-ready when every finding carries location + fix + named test.** Then the planning pass is a *transcription + scoping* exercise: verify locations against source (cheap, catches staleness), group findings into phases, pin the fix contracts as RD-decisions, and stop. Skip research, skip scenario derivation; *transcribe* the review's test expectations into scenario rows.
2. **Cluster findings by file ownership, not by finding ID.** Findings that touch the same lines must land in one phase, one session: C-1 + N-16 + N-20 (same input handlers), I-1 + I-2 (same choke point), I-5 + I-6 + I-7 + N-17 (one teardown/DI refactor — splitting it reworks the same files 2–3 times). The review lists findings by severity; the plan must re-order by *edit surface*.
3. **Amended rows get "(rev)" IDs and a single canonical home.** When the fix changes behavior a prior plan pinned (U-11, U-13, U-09, P-13, B-05), the new plan's `behavior-specs.md` holds the canonical amended text under the "(rev)" label; the old plan's row is updated *in the same session* to a pointer. A capability that is *deleted* (engine P-12 visual clock) is struck through with a retirement note — not ported — when its observable content already lives in surviving rows (B-01/B-02). New review-specific rows get a fresh namespace (`R-<finding>.<n>`) so they can't collide with the base plan's IDs.
4. **Backlog phases may be scope lists, not build specs.** A curated nit backlog (20+ one-line items, each already self-contained in the review) does not warrant pre-authored scenario tables and phase files. The phase file is a *disposition table* (Do / Do-docs / Defer, with a one-line note per item) plus "scoped on pickup" mechanics: scheduling an item = add its scenario row + author its phase file + add it to the phase map. Pre-authoring all of it is the same redundant-work failure as Rule 1.
5. **The integrity check is scriptable — run it mechanically, not by eye.** decompose-plan.md Step 2 (every ID in phase files resolves in the canonical table; phase count == phase-map rows; cross-refs resolve) was hand-rolled with grep during this exercise and would catch the staleness class (an ID referenced but never canonical, a phase-map row without a file). It belongs in the kit as a ~30-line script, run before a plan is marked ready.
6. **The review's output contract is the upstream half of this rule.** What made Rule 1 true was the review's format: per-finding location + fix + *why the existing tests are green* + a tiered action plan. Six-pass reviews (architecture / core-correctness / app-layer / tests / spec-compliance / world) with that output shape should be the standing format for end-of-milestone reviews — a review without named tests produces a plan that needs a real planning session, which is exactly the extra cost this learning exists to avoid.

## What Worked (this exercise)

- **Verifying the review against source during the light pass** — 10 spot-checks (template bindings, `onDrop` vs `onFileDropped`, `clampOffset` order, engine visual-clock surface, `stopAll`→`dispose`, runner fallback) confirmed zero staleness *and* caught one gap the review under-specified: E2E-2.3 asserts BPM clamp immediately after `fill()`, which needs an Enter commit trigger under the new pattern. A pure transcription would have shipped that inconsistency into a phase file.
- **KB-number continuity check** — the review's "record as KB" items assumed KB numbering; checking the v1 plan found KB-10 already taken (offline deferral, recorded at review time) and reserved KB-11/12/13 in the new plan. Cheap, prevents two KB-10s.
- **Open Decisions table in `index.md`** — three product/scope calls (commit pattern, backlog scope, one behavior change) made explicit with stated defaults, so execution can start on the defaults and the user trims later.
- **The 2026-08-20 handoff rules applied forward** — phase files carry "Context to load" naming RD-decisions by ID, and phase-close handoff audits are named in success criteria; the review→plan boundary gets the same treatment for free.

## Cost / Benefit

One light planning session (~transcription + 10 spot-checks + integrity grep) vs. a full BDD session (world-review + planner delegation + scenario derivation + iteration) that would have re-derived ~90% of already-pinned content. The residual risk — a review error transcribed into a plan — is bounded by the source-verification step, which is the one part of the light pass that must not be skipped.

## Next Steps

- [x] `writing-plans` skill: new `references/review-to-plan.md` — done 2026-08-22 in the dev kit (plan-ready test, file-ownership clustering, "(rev)"/R-*/retirement canonicality, scope-list backlog template, light-pass checklist).
- [x] `writing-plans` `references/decompose-plan.md`: Step 2 now runs the mechanical check via `script/plan-integrity-check.sh` first and keeps only the by-eye items (uniqueness of canonical home, status confirmation, content completeness); scope-list phase variant added to the template.
- [x] `plan-integrity-check.sh` (new) — **landed at `.pi/skills/writing-plans/script/plan-integrity-check.sh`, not top-level `scripts/`**: scripts live inside the skill that uses them so they ship with the kit to every project (same convention as `analyzing-pi-usage/script/`). Checks ID resolution (`--ids` configurable), phase count vs map, and phase-map file existence; verified green on both Metronomad plan dirs, red on a broken fixture.
- [x] Review workflow codified: the six-pass format + plan-ready output contract now live in the `code-review` skill at `reference/milestone-review.md` (pointer in SKILL.md), so Rule 6 holds by construction for end-of-milestone reviews.
- [x] First real use: the Metronomad `2026-08-22-address-v1-review` plan is linked as the worked exemplar from both `references/review-to-plan.md` and `reference/milestone-review.md`.
- [ ] First *fresh* use: the next plan-ready review (post-Metronomad) should exercise `review-to-plan.md` + the script end-to-end; note any drift in a follow-up learning.

---
**Status**: Open (kit changes landed 2026-08-22; debrief follow-up below still pending)
**Follow-up**: Metronomad review-fix execution (Phases 1–3) exercises the plan this learning describes; re-run the debrief after Phase 1 to validate the light-pass pattern under build-tdd.
