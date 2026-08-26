# Missing ES-module exports fail at link time — the in-browser runner reports a hang, not a failing test

**Date:** 2026-08-22
**Context:** Metronomad review-remediation Phase 3, N-7 (export `ENGINE_EVENTS`). The RED step added `ENGINE_EVENTS` to the *named import list* in `PlaybackEngineTest.html` before the module exported it. The suite didn't show a failing test — it died with `mocha.run() was never reached within the timeout — test page error or hung suite`, and the first instinct (broken harness? hung test? server?) was wrong.

## The trap

A named import of a missing export is a **SyntaxError at module-link time**, not a runtime error. The whole module graph (test script → imports → modules under test) fails to instantiate, so Mocha never registers a single test, so `mocha.run()` never fires, so the runner's timeout fires with a "hang"-shaped message. No per-test error, no console trace in the runner output — just the file failing to reach `mocha.run()`.

Two related but distinct failure shapes exist in this codebase:

| Failure | Where | Symptom |
|---|---|---|
| Re-export of a missing name through the `MyESModules/index.js` **barrel** | barrel | **silent** — `undefined` at the consumer (the barrel header warns about this) |
| Direct **import** of a missing name (or any broken module in the graph) | module link | **loud but misleading** — page never loads, runner reports a timeout |

The RED state "import a name the module doesn't export yet" is therefore a *broken-page* RED, not a *failing-test* RED. It's still a valid TDD RED (nothing passes), but it tells you nothing about which assertion will fail, and it masks other test errors in the same file.

## Rules

1. **For an export-introduction RED, don't touch the import list yet.** Import nothing new; assert the export's absence or the behavior first (`expect(window.__underTest.ENGINE_EVENTS)` via a side channel, or just run the behavior test and let the *implementation* be what's missing). Alternatively, accept the broken-page RED explicitly: when you deliberately make one, expect "mocha.run() never reached" and do not go hunting for a hung test.
2. **When a test file fails with the timeout message, check the page console before suspecting the harness.** In this repo the fastest check is a 10-line Playwright script that captures `page.on('pageerror')` and prints it (verified 2026-08-24: prints `PAGEERROR: The requested module '../MyESModules/index.js' does not provide an export named 'PEAK_BUCKETS_DEFAULT'`); alternatives are opening the `*Test.html` URL directly in a browser, or `node --check` on an extracted `<script type="module">` body copied to a `.mjs`. A link error names the missing export and the module that should provide it. (Playwright is installed at the repo root, not in `Metronomad/` — a script kept in `/tmp` needs `NODE_PATH=<repo root>/node_modules`.)
3. **Keep the two barrel failure shapes straight in docs:** "re-export of a missing name silently yields undefined" (barrel) and "direct import of a missing name fails module linking" (graph). They have opposite symptoms; conflating them sends a debugger looking for the wrong thing.

## Secondary observation: verify a RED is the RED you think it is

After the N-7 import broke the page, the *other* new test in the same file (R-N1.1) was never actually executed until the export existed. When multiple REDs land in one file, a broken-page RED hides the per-test REDs behind it — run the file again after the first fix and confirm the *remaining* failures are the ones you expect before writing more implementation.
