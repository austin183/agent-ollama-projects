# Asserting "Callback Fired Before I/O" Without Timer Mocks

**Date:** 2026-08-18
**Context:** Metronomad Phase 3 — F-08: `fileLoader.loadFile()` must fire `onStateChange('decoding', { fileName })` *before* any await so the UI shows "Decoding <name>…" the instant a file drops (U-01)

## The Contract

The production code is an async function:

```javascript
async function loadFile(file) {
    // ... codec check ...
    if (onStateChange) onStateChange('decoding', { fileName: file.name });
    const objectUrl = URL.createObjectURL(file);
    try {
        const bytes = await file.arrayBuffer();   // first await
        // ...
```

The testable claim: the `decoding` event is observable **synchronously** at call time — before `arrayBuffer()` is even read.

## Pattern: Call, Assert, Then Await

An async function executes synchronously up to its first `await`. So calling it and checking the side-effect log *before* awaiting the returned promise proves the callback fired with zero I/O in flight:

```javascript
const events = [];
const onStateChange = (state, detail) =>
    events.push([state, detail ? detail.fileName : null]);

const loader = createFileLoader({ codecs, context, onStateChange });

const promise = loader.loadFile(file);
// No await yet — everything up to file.arrayBuffer() has already run.
expect(events).to.deep.equal([['decoding', 'ok.mp3']]);

await promise;
expect(events).to.deep.equal([['decoding', 'ok.mp3'], ['idle', null]]);
```

Why this is worth a pattern note:

- **No fake timers, no microtask pumping.** The ordering claim ("before the await") is proven by the language's own execution semantics, which is stronger than any timer-injection stub could show.
- **It pins the UX contract, not the implementation.** If someone later "optimizes" by firing `decoding` from inside a `.then()` or after `arrayBuffer()`, the synchronous assertion fails immediately — exactly the regression U-01 depends on.
- **Same shape works for any "synchronous side effect in an async API"** — URL creation ordering, id/generation stamps, "started" events. Assert the log right after the call; `await` only when you need the result.

## When It Does NOT Work

- If the function is wrapped so the interesting work starts in a microtask (e.g. `queueMicrotask`, a leading `await Promise.resolve()`), the pre-await window is empty and the assertion passes trivially with `[]` — then you've asserted nothing. Confirm the test would *fail* under a delayed implementation (mutation testing by hand: move the callback after the first await and watch it break).
- For callbacks that legitimately fire after I/O, use plain `await` + ordered-log assertions instead.

## Skill Mapping

- **`building-web-apps` → `references/testing-unit.md`** — candidate addition near "Testing Default Behavior Explicitly": a short "Asserting synchronous side effects of async APIs" note with the call-assert-await shape. Complements the existing RAF callback-collector pattern (which covers frame ordering; this covers *first-await* ordering).

## Session Note

Manual acceptance for this behavior also passed: a real ~2-minute MP3 dropped onto the live site decoded to Ready with duration shown. The >30-minute `tooLong` path could not be manually exercised (no such file on hand) — it remains unit-only by plan design ("the >30-min … long-file cases exist only as unit fakes"), so no coverage gap.

---
**Status:** Closed
**Follow-up:** Phase 4 engine tests can reuse the pattern for "generation stamped synchronously in startSequence/stop()" (D4 atomicity, P-02/P-03)
