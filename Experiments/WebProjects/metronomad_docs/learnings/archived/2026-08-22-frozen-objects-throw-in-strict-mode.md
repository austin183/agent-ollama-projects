# Object.freeze in strict-mode modules: writes THROW, they don't no-op — tests and prose must say "throws"

**Date:** 2026-08-22
**Context:** Metronomad review-remediation Phase 3, N-4 (`startSequence` returns a frozen schedule snapshot). The spec prose said "writes are no-ops"; the first test did `result.schedule.clicks[0].scheduled = true; // no-op on the frozen view` and failed with `TypeError: Cannot assign to read only property 'scheduled' of object '#<Object>'`.

## The trap

"No-op" is only true in **sloppy mode**. ES modules are always strict, and so is everything in this repo's test pages (the Mocha suites run inside `<script type="module">`). In strict mode, assigning to a frozen/sealed/readonly property throws `TypeError` instead of silently failing. Code that *catches* the assignment (a `try` wrapper, a Proxy, `Object.defineProperty` with a setter) can still observe a no-op — but a bare write in a test or a strict-mode consumer throws.

The practical consequences are one-directional: code written against the "no-op" assumption either (a) crashes where it expected silence, or (b) passes a test that never actually exercised the freeze (the throw aborts the `it()` before the subsequent assertions run — the test fails for the *wrong* reason and the fix is to the test, not the code).

## Rules

1. **Tests that pin a freeze assert the throw:** `expect(() => { obj.frozenProp = 1; }).to.throw(TypeError);` — and then assert the *unfrozen observable* (here: the engine still schedules click 0 from its internal `_seq`). The throw is the contract; the downstream behavior is why the contract matters.
2. **Prose that describes a frozen API says "writes throw TypeError (strict mode)"**, not "writes are no-ops". "No-op" invites the bare-assignment test shape above and misleads any sloppy-mode reader (bundlers, `eval`, inline classic scripts) about what actually happens.
3. **Distinguish the three immutability verbs when documenting:** frozen = throws on write (strict) / silently fails (sloppy); `Object.isFrozen` = the observable check; "snapshot" = the value was copied, so mutating the *copy's inputs* was never possible anyway. N-4's real protection is the *copy* (the engine's `_seq` is never exposed) — the freeze is the tripwire that tells you someone is trying.
