# Playwright E2E: In-Page Timing Measurement and evaluate Closure Gotchas

**Date:** 2026-08-20
**Session:** build-tdd Metronomad Phase 7 E2E suite

## Summary

Three rules from building Metronomad's timing-sensitive E2E suite (±300–500 ms
assertions on audio-clock transitions). The first cost ~3 failing runs and 3
probe scripts to discover; the second failed silently. Neither is covered by
the existing Playwright references, which focus on *waiting* conventions
(`waitForSelector` over `waitForTimeout`) but say nothing about *measuring*
time.

## Rule 1: Measure sub-second timing in-page, not from node-side polls

**Problem:** under machine load, the node-side Playwright polling loop is
starved. `expect.poll`'s 100 ms interval arrived 1–2 s apart, and even single
`page.evaluate` round-trips lagged. A ready-state flip that happened at
**4531 ms** in-page was first observed by the node side at **5410–5447 ms** —
a variable 0.3–0.9 s error that broke ±500 ms assertions run after run, while
a raw in-page probe showed the app was exactly on time.

**Diagnosis signature:** a timing assert fails by a *variable* margin (0.3–0.9 s)
while an in-page logger (or manual probe) shows the app hitting the grid law
within ~30 ms. If that's what you see, the harness is the problem, not the app.

**Fix:** install a 5 ms in-page transition logger before the action, anchor
`t0` in-page at the click instant, and assert on the read-back log. Reserve
node-side expects for state/text *existence* checks with no timing claims.

```javascript
// Install logger + dispatch the click in ONE evaluate: t0 and the transitions
// share the same performance.now() clock.
await page.evaluate((trigger) => {
  window.__t0 = performance.now();
  window.__timeline = [];
  const read = () => [
    document.body.dataset.state,
    document.querySelector('#beatDots').dataset.beat,
    document.querySelector('div[role="status"]').textContent
  ];
  let prev = read();
  const log = (v) => {
    if (v.some((x, i) => x !== prev[i])) {
      window.__timeline.push({ t: performance.now() - window.__t0, state: v[0], beat: v[1], ann: v[2] });
      prev = v;
    }
  };
  window.__tlIv = setInterval(() => log(read()), 5);
  document.querySelector(trigger).click();
}, '#playStopBtn');

// ... wait for completion (node-side, no timing claim), then read back:
await expect.poll(() => page.evaluate(() => document.body.dataset.state), { timeout: 10000 }).toBe('ready');
const timeline = await page.evaluate(() => { clearInterval(window.__tlIv); return window.__timeline; });
const playing = timeline.find((e) => e.state === 'playing');
expect(Math.abs(playing.t - 1500)).toBeLessThanOrEqual(300);
```

Why the in-page clock stays exact while node-side doesn't: the browser's
`setInterval` runs on the page's own event loop against `performance.now()`;
node-side samples are throttled by IPC + the node process's starved timer
queue. The two desynchronize under load.

**Narrow-window actions:** if a test must *act* inside a window shorter than a
node poll can reliably hit (e.g., Stop during a 500 ms count-in), schedule the
action in-page too: `setTimeout(() => btn.click(), 250)` inside an evaluate,
recording `window.__actionT = performance.now() - window.__t0` at fire time.

**Timeline usage gotcha:** the logger records *every* change, so an
`state === 'playing'` entry may be an in-state announcement/position change.
For Nth-occurrence or restart assertions, filter to *transitions*
(`timeline[i-1].state !== e.state`), not first-matches.

## Gotcha 2: `page.evaluate` bodies serialize standalone — node helpers are undefined in-page

Any helper defined in the spec's module scope and referenced inside the
evaluated function does **not** exist in the page. The failure is a
`ReferenceError` *inside the evaluated code* — and if it happens in a
`setInterval` callback (like the 5 ms logger above), it is **silent**: the
first tick throws, no entries are ever pushed, and the test fails later with a
confusing empty-data assertion (`countingIn entry: null`) instead of the
original error.

```javascript
// BAD — timeToSeconds is defined in the spec file, undefined in-page:
await page.evaluate(() => {
  const toSec = timeToSeconds; // ReferenceError on first use
  window.__iv = setInterval(() => { log(toSec(readout())); }, 5); // dies on tick 1, silently
});

// GOOD — define every helper locally inside the evaluated body:
await page.evaluate(() => {
  const toSec = (s) => { const [m, r] = s.trim().split(':'); return Number(m) * 60 + Number(r); };
  window.__iv = setInterval(() => { log(toSec(readout())); }, 5);
});
```

Rule: treat the evaluated function as a separate program. Local definitions
serialize fine; pass data in as `page.evaluate(fn, arg)` arguments.

## Rule 3: File-drop E2E — use a GENUINE `new DataTransfer()`, not a mock

The existing reference says `DragEvent.dataTransfer` "cannot be mocked" —
correct for plain objects (`new DragEvent('drop', { dataTransfer: { files } })`
throws a TypeError in every browser). But Chromium accepts a **real**
`DataTransfer` instance in the constructor dict, which is the missing piece for
testing file-drop handlers end-to-end (the listener-presence workaround in the
reference stays valid for unit tests):

```javascript
await page.evaluate(() => {
  const dt = new DataTransfer();
  dt.items.add(new File(['bytes'], 'song.mp3', { type: 'audio/mpeg' }));
  document.querySelector('#dropZone').dispatchEvent(
    new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt }));
});
```

Verified working in headless Chromium (Metronomad E2E-2.2). `page.setInputFiles`
covers the `<input type="file">` path; this covers the drop-zone path.

## Related

- Session summary: `_agent_docs/sessions/2026-08-20-002-build-tdd-phase7-e2e-suite-tdd.json`
- Working example: `test/e2e/playback.spec.cjs` (`startRecordedSequence`, `scheduleActionAt`, `transitionsTo`)
- Sibling reference: `CollageMaker/_agent_docs/learnings/2026-07-22-playwright-event-simulation-gotchas.md`
