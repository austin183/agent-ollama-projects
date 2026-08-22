# Review → Plan Conversion (Light Planning Pass)

When a code review is **plan-ready**, do not run a full planning session (world-review + planner delegation + scenario derivation). A light pass — transcription + scoping + clustering — produces the plan in one session. Re-running discovery re-derives what the review already pinned: correct artifacts, redundant work.

## Plan-Ready Test (all three, per finding)

A review is plan-ready when **every** finding carries:

1. **Location** — file:line, specific enough to verify in minutes
2. **Fix** — a concrete fix contract implementable as written (an RD-decision candidate)
3. **Named regression test** — the "why the tests are green" gap states the exact test that should pin the fix

A review missing any of the three produces a plan that needs a real planning session — the exact extra cost this path avoids. (Keep the review output contract from the `code-review` skill's `reference/milestone-review.md` so end-of-milestone reviews are plan-ready by construction.)

## Rules

1. **Transcribe, don't derive.** Copy the review's test expectations into scenario rows verbatim; skip research and scenario derivation. The one step that must not be skipped is **source verification** — it bounds the only residual risk (a review error transcribed into a plan).
2. **Cluster by file ownership, not finding ID.** Findings that touch the same lines land in one phase, one session. A coherent multi-finding refactor (teardown/DI, one choke point) is never split across phases — splitting reworks the same files 2–3 times. The review lists findings by severity; the plan re-orders by *edit surface*.
3. **Amendments get one canonical home.**
   - A fix that changes behavior a prior plan pinned → the new plan's `behavior-specs.md` holds the canonical amended row labeled `ID (rev)`; the old plan's row is updated **in the same session** to a pointer.
   - A capability that is *deleted* → struck through with a retirement note in the old plan (not ported), when its observable content already lives in surviving rows.
   - New review-specific rows get a fresh namespace `R-<finding>.<n>` (plus `RD-<n>` for the fix contracts) so they can't collide with the base plan's IDs.
4. **Backlog phases may be scope lists, not build specs.** A curated nit backlog of self-contained one-line items does not warrant pre-authored scenario tables and phase files. Pre-authoring all of it is the same redundant-work failure as Rule 1.

## The Light Pass (checklist, in order)

1. **Verify locations against source.** Spot-check each fix's target (binding, function, call site) against the code. Catches staleness *and* under-specification — e.g. a test that asserts before the state the fix changes, needing an extra trigger the review didn't name.
2. **Cluster findings into phases by file ownership** (Rule 2); keep coherent refactors whole.
3. **Pin fix contracts** as `RD-<n>` decisions in `context.md` — each is the review's "Fix:" paragraph, made canonical.
4. **Transcribe test expectations into scenario rows** in `behavior-specs.md`: new rows under `R-<finding>.<n>`; amended rows under `ID (rev)` (Rule 3).
5. **Record-numbering continuity** — check the base plan's existing KB/decision numbers before assigning new ones; never mint a duplicate.
6. **Open Decisions table in `index.md`** — every product/scope call made explicit with a stated default, so execution can start on defaults and the user trims later.
7. **Integrity check** — `bash .pi/skills/writing-plans/script/plan-integrity-check.sh <plan-dir>` (see `decompose-plan.md` Step 2).
8. **Report** — plan tree, phase map, and what the source verification confirmed or caught.

## Scope-List Phase Template (backlog)

```markdown
# Phase N: <Name> — Backlog (Priority)

**Depends on:** <prior phases, by ID>

**Context to load:**
- `index.md` → Open Decisions, Phase Map
- <review doc section, if any>

## Overview
Curated backlog from <review>. Each item is self-contained; items are scoped on pickup —
this file is a disposition table, not a build spec.

## Disposition

| Item | Location | Note | Disposition |
|------|----------|------|-------------|
| N-3 | `file:line` | one line | Do / Do-docs / Defer |

## Scoping on Pickup

Scheduling an item = (1) add its scenario row to `behavior-specs.md`, (2) author its
phase file with the full template (see `decompose-plan.md`), (3) add it to the phase map.
```

## Worked Exemplar

The exercise that produced this reference: a six-pass end-of-milestone review (1 CRITICAL, 9 IMPORTANT, 33 nits — each with location + fix + named test) converted in one light-planning session into a three-phase plan directory of ~550 lines: `index.md` with an Open Decisions table, `context.md` with RD-1…RD-6 fix contracts, `behavior-specs.md` with R-*/(rev) rows, and a Phase 3 using the scope-list variant above. The planning work was transcription + scoping + clustering, not design.
