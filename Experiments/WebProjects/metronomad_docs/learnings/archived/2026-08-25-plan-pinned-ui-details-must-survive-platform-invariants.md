# Plan-pinned UI details can violate PLATFORM invariants — verify them against framework/DOM semantics at test-construction time

**Date:** 2026-08-25
**Context:** Metronomad CR 001 Phase 5 (canvas scrub + keyboard replaces the offset range). Two plan-pinned UI details were not implementable as written — neither was caught by the plan's spot-verification (which checked file:line anchors) and neither shows up as a failing test; each was discovered at construction time by asking "can the platform actually do exactly this?"

1. **Template-scope invariant.** D-H pinned `:aria-valuetext="'Offset ' + formatTime(offset)"`. Vue template expressions resolve identifiers against the component instance plus a fixed whitelist of globals (`Math`, `String`, `Date`, …) — a module-scope `import { formatTime }` in the app factory is **not visible to the template**. The binding as pinned compiles fine (the compiler doesn't know the instance shape) but fails at render time — the expression resolves to `_ctx.formatTime(...)`, i.e. `TypeError: _ctx.formatTime is not a function` the first time the canvas renders.
   **Resolution:** expose the util as a template method at the wiring point — the inline module script in `index.html` merges it into the config: `methodsConfig: { ...createMetronomadMethods(), formatTime }`. The methods factory stays pure; the template dependency is wired where the template's other dependencies are already wired.
2. **DOM-order invariant.** The plan's R-2/keyboard spec prose said the canvas "takes the scrubber's slot" in the exact-Tab-order sequence (between `bpmPlusBtn` and `offsetInput`). Tab order is DOM order for focusable elements, and the canvas lives in the progress block *below* the playback buttons — the slot was unreachable without moving the whole progress region (a layout change the CR never approved). The actual canonical 8-element sequence ends with `waveformCanvas`.
   **Resolution:** re-pin the canonical sequence from the real DOM (`keyboard.spec.cjs`), with a comment naming why; world-review classified it a discussion item, not a defect.

## Rules

1. **At test-construction time, run each plan-pinned UI detail through the platform-invariant checklist for its surface:**
   - Vue template: can the expression see every identifier it names (instance property, computed, method, or whitelisted global)? If it names an imported util, the plan needs a wiring decision (methods/computed exposure) — add it at the wiring point, not inside a factory that should stay pure.
   - Tab/focus order: does the pinned sequence match DOM order of the focusable elements (including `tabindex` flips and `:disabled`/`-1` states)? "Takes X's slot" claims require the element to be in X's DOM neighborhood.
   - Canvas/SVG: can it be `:disabled`? (No — the lock contract is `aria-disabled` + `pointer-events` + `tabindex`.) Can it be focused? (Only with a `tabindex`.)
   - Native inputs being replaced: what do their replaced affordances map to (step → keydown deltas, `max` → `aria-valuemax`, `disabled` → the three-part lock)?
2. **When a pin is impossible, implement the closest possible form of the pinned INTENT, re-pin in place with a dated note, and flag it in the session summary + phase map** — the same discipline the sibling numeric-units learning prescribes for arithmetic pins. Never silently ship a deviation: the exact-Tab-order test and the aria bindings here were re-pinned *with comments citing the invariant*, so the next reader sees the supersession, not a mystery.
3. **Spot-verification of anchors does not verify semantics.** The plan's planning pass verified `file:line` locations exactly and still shipped both of these. The invariant check is cheap (a minute of "can Vue/DOM actually do this?") and is the only gate that catches this class — it belongs to the test-construction step, because that is when the pin is materialized into real markup.

## Why it matters

An unimplemented-as-pinned binding either fails loudly at template compile (template-scope case — caught on first load) or, worse, tempts a workaround that drifts from the pinned contract (e.g., binding `offsetText` instead of `formatTime(offset)` — different behavior mid-draft). The tab-order case is the silent one: the plan's prose reads as an implementation instruction, and a builder who "just makes the test pass" could move the canvas in the DOM to satisfy it — a layout regression no scenario pins.

## Skill mapping (landed 2026-08-25)

- [x] `building-web-apps` → `references/testing-e2e.md`, new "Plan-Pinned UI Details vs. Platform Invariants" section (per-surface invariant checklist: Vue template scope, tab/focus order, canvas/SVG, replaced native inputs; re-pin-with-cited-invariant discipline); summarized in `SKILL.md` gotchas alongside the sibling numeric-units rule.
