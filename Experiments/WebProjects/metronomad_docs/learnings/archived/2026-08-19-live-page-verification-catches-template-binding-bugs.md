# Live-page verification catches template binding bugs that mock-VM unit tests cannot

**Date:** 2026-08-19
**Context:** Metronomad Phase 5 (UI integration) — after 39/39 mock-VM unit tests and 4/4 smoke E2E passed, a one-shot Playwright script driving the real page through the full Play→Stop→Preview→Restart lifecycle found a P0 bug: the Play/Stop button used `:disabled="!isReady"`, and `isReady` is false during `countingIn`/`playing` — so **the button was disabled exactly while it needed to act as Stop**. The user could not stop playback.

## Why the unit suite missed it

Mock-VM tests (`buildVm` = data + methods + computed) exercise the handler logic against a fake engine — they never render the template. The `:disabled` binding in `index.html` is outside their reach. The smoke spec only checks the no-file state (where the binding was correct). The bug lived in the gap between "handlers behave" and "template wires the handlers to the right DOM state" — precisely the layer Phase 5 exists to close.

## The symptom that pointed at it

The verify script's Stop step did not fail where expected: Playwright's click on the (disabled) button auto-waited, the song ended at +3 s and the button *became* enabled, the pending click then **started a new sequence**, and the subsequent `waitForFunction(state === 'ready')` timed out. A timing test failing at the *wrong* step is a strong signal that an interaction never happened — check element enabled/focus state explicitly instead of assuming the click landed.

## Rule

For any phase whose job is UI wiring: after the unit suite is green, drive the **real page** through the P0 user flows (load → run → stop → restart → preview) with a throwaway Playwright script before declaring the phase done. Assert state, labels, enabled/disabled, focus, and announcements — the things the template owns. Cost here: ~40 lines of script in /tmp; value: a P0 found before manual acceptance.

## Secondary findings (same verification)

- Live timing with real audio confirmed the engine's sample-accurate path end-to-end: count-in 2 @ 120 BPM → `playing` at 1541–1556 ms (want ~1500), end at 4541 ms (want ~4500), preview clamped to 2048 ms (D2).
- Focus return to the Play/Stop button after Stop worked end-to-end (`document.activeElement.id === 'playStopBtn'`).
