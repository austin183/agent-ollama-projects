# Plan Decomposition Procedure

Split an existing single-file plan into a per-phase directory when it exceeds the decomposition threshold (~200 lines, 5 phases, or ~15 KB) **or** when an execution agent shows overthinking while working a phase (re-reading the whole plan, unclear what's relevant to the current task, drifting into other phases' work).

## Why

A single large plan forces every phase session to load all phases, all scenario tables, and all design decisions. Per-phase context isolation — with whole-plan detail one hop away — removes the "what's relevant to this phase?" question entirely.

## Step 0: Read and Confirm

1. **Read the original plan completely** (no limit/offset) before touching it.
2. **Confirm with the user**:
   - The directory layout (below) and that the original will be archived (not deleted)
   - **Phase status** — plans rarely record progress; ask which phases are done/in-progress. Never silently guess; if you must infer, mark it and get confirmation.
3. Do the split in the plan's directory: `[docs directory]/plans/<plan-slug>/` (slug from the original filename).

## Step 1: Build the Tier Files

```
[docs directory]/plans/<plan-slug>/
├── index.md              # Navigation + phase map (single source of truth for progress)
├── context.md            # Stable whole-plan detail
├── behavior-specs.md     # Canonical scenario tables (only if the plan is BDD)
└── phase-N-<slug>.md     # One self-contained file per phase
```

**`index.md`** — header metadata (date, spec, research refs), a short "how to use this plan" (what each file is for + the working convention), then the plan's Overview / Current State / Desired End State / What We're NOT Doing, and the **phase map**:

```markdown
## Phase Map

| Phase | File | Priority | Status |
|-------|------|----------|--------|
| 1. <name> | phase-1-<slug>.md | P0 | ✅ done |
| 2. <name> | phase-2-<slug>.md | P0 | 🔨 in progress |
```

**`context.md`** — the stable, rarely-edited whole-plan sections: design decisions, file layout & module interfaces, testing strategy, performance considerations, known behaviors, references. These are the "ancillary details" every phase may need.

**`behavior-specs.md`** (BDD plans only) — all scenario tables **verbatim**, plus priority ordering. Header states it is "the authoritative, complete set" and that phase files inline the scenarios they own.

## Phase File Template

```markdown
# Phase N: <Name> (Priority)

**Depends on:** <prior phases and the specific contracts they provide, by ID>

**Context to load:**
- `index.md` → <sections>
- `context.md` → <named sections, e.g. "Design Decisions D4/D9">
- `behavior-specs.md` → <named sections/IDs, if any>
- <other: research docs, skill references, reference implementations>

## Overview
<what this phase accomplishes — from the original>

## Changes Required
<from the original, adjusted so section references point at the new files>

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §X)
<the phase's scenario rows INLINED — full tables, not just IDs>

## Success Criteria
<from the original, unchanged>
```

The **Context to load** list is the anti-overthinking mechanism: it makes the scope of attention explicit so the working agent doesn't wander into other phases' concerns.

### Scope-List Variant (backlog phases)

A curated backlog of self-contained items (e.g. a nit list from a review) does not warrant pre-authored scenario tables and build specs. Its phase file is a **disposition table** (Do / Do-docs / Defer, one-line note per item) plus **scoped-on-pickup** mechanics: scheduling an item = add its scenario row to `behavior-specs.md` + author its full phase file + add it to the phase map. Full template in `references/review-to-plan.md`.

## Ownership Rules

1. **Each scenario/behavior ID is inlined in exactly one phase file** — the phase that delivers it.
2. **Depends-on contracts stay as ID references** ("Depends on: Phase 4 — `getBeatGrid()` P-10"), never inlined. They are another phase's contract, not this phase's work.
3. **Label every inlined copy**: "(canonical copy in `behavior-specs.md` §X)" — locality without drift.
4. **Surface overlaps**: if the original assigns the same ID to two phases, resolve the ownership explicitly (one phase owns it; the other references it) and note the resolution.

## Step 2: Integrity Check (before archiving)

Run the mechanical checks first — never by eye:

```bash
bash .pi/skills/writing-plans/script/plan-integrity-check.sh <plan-dir>
# for plans whose IDs don't use the R-*/RD-* conventions:
#   --ids '<ERE of ID prefixes>' --canonical <files…>
```

The script verifies: every referenced ID (default `R-*` / `RD-*`) in the phase files resolves in a canonical file; phase-file count == `index.md` phase-map rows; every phase file named in the phase map exists. It exits non-zero listing each failure.

Then finish by eye (the script can't see these);
the split is not done until all pass:

- [ ] Every scenario/decision/known-behavior ID in the original appears in exactly one canonical table (behavior-specs.md / context.md) — add the plan's ID families to `--ids` so the script covers them
- [ ] Phase-map statuses confirmed with the user
- [ ] No content section from the original is missing from index.md / context.md / behavior-specs.md / the phase files

## Step 3: Archive the Original

Move (don't delete) the original to `[docs directory]/plans/archive/` and prepend a pointer header:

```markdown
> **ARCHIVED — superseded by the split plan directory [`<plan-slug>/`](../<plan-slug>/index.md).** This single-file plan is kept for history only; do not work from it.
```

Add a one-line pointer to the archive at the bottom of `index.md`.

## Step 4: Report

Present the resulting tree, the phase map with statuses, and flag:
- Any ownership overlaps you resolved
- Any content that didn't fit the tiers cleanly (and where you put it)
- The working convention (below) — remind the user that phase sessions should now start from the current phase file

## Working Convention (for execution agents)

> When a plan directory exists, work from the current phase file + its "Context to load" list only — nothing more. Mark the phase complete in `index.md`'s phase map when its success criteria are met — after running the handoff audit from `references/phase-handoff.md` (diff the next phase's context load and inlined tables against as-built code).
