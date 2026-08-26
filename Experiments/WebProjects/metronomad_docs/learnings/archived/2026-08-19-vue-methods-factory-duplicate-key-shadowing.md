# Vue Methods Factories: Leftover Duplicate Keys Silently Shadow New Methods

**Date:** 2026-08-19
**Context:** Metronomad Phase 5 — `createMetronomadMethods()` replaced Phase 1 stubs (`onPlayToggle`/`onRestart`/`onBpmStep`…). I implemented the real `onRestart` in the middle of the factory but a Phase 1 stub `onRestart()` was still sitting at the bottom. All 4 V-02 tests failed with `expected [] to deeply equal [ ['restart', …] ]` — the handler looked implemented, yet the engine never saw a call.

## The Trap

The factory pattern returns a **plain object literal**. JS object literals resolve duplicate keys by **last occurrence wins** — no error, no warning. A leftover stub below the new implementation silently overrides it, so the app and the tests both run the *old* (empty) method.

This is the mirror image of the barrel trap documented for `MyESModules/index.js` (re-exporting a missing name yields silent `undefined`). Same family — silent failure in the factory plumbing — but the opposite symptom:

| Trap | Symptom |
|---|---|
| Barrel re-export of a missing name | `undefined` import, call throws |
| Duplicate method key in a factory | **Old behavior persists**, tests fail as if nothing was implemented |

## The Rule

After adding or replacing a method in a `*Methods` factory (or any object-literal factory), verify the name appears exactly once in the file:

```bash
grep -c "onRestart" MyESModules/App/createMetronomadMethods.js   # expect 1 (the definition)
```

Or when editing: replace the stub **in place** (include it in the same edit), never insert the real method above an existing stub of the same name.

## Cost

One full RED-GREEN round: 4 failing tests, a file re-read, and the grep that found the duplicate. The failing signature to remember: *tests fail as if the handler is still a stub, even though you can see the implementation in the file.*
