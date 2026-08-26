# Input handlers: test the keystroke sequence, not one-shot values

**Date:** 2026-08-22
**Context:** Metronomad Phase 1 (C-1) — the v1 CRITICAL defect: typing `120` into the BPM field left `2500` in the field while the model held `250` (a per-keystroke clamp corrupted text the user was mid-typing). The unit suite was green, because it never tested *typing*.

## Why the defect slipped

The v1 BPM handler clamped on **every** `input` event. The unit tests were **one-shot**: set a value, read the result.

```js
vm.onBpmInput('251');  expect(vm.bpm).to.equal(250);   // pass
vm.onBpmInput('10');   expect(vm.bpm).to.equal(30);    // pass
vm.onBpmInput('180');  expect(vm.bpm).to.equal(180);   // pass
```

Each input (`251`, `10`, `180`) is a **complete** number, so clamping it is correct and the test passes. But real typing is a **sequence**: `1` → `12` → `120`. The intermediate `1` is out of range (BPM min 30), so a per-keystroke clamp rewrites it to `30`; subsequent keystrokes append to the *clamped* text → `300`, `3002`, … The one-shot tests can't see this, because they never feed an intermediate draft.

## Rule

For a handler that **parses / clamps / commits** a text input, the regression test must replay the **keystroke sequence** (each intermediate draft) and assert the invariant at *every* step — not only on the final value:

```js
// C-1: the draft (bpmText) absorbs every keystroke; the model moves only on commit.
for (const draft of ['9', '90', '190']) {
    vm.bpmText = draft;                 // simulate one keystroke — no commit
    expect(vm.bpm).to.equal(120);       // model unchanged at every intermediate step
    expect(vm.bpmClamped).to.equal(false);
}
vm.commitBpmEntry();
expect(vm.bpm).to.equal(190);           // model moves on commit (190 is in range)
```

This per-keystroke shape (R-C1.1) is the exact test class whose *absence* let C-1 slip — the review calls it the flagship regression. When fixing an input-handling defect, write the per-keystroke test **first**.

## Generalization

Wherever a handler's correctness depends on the **sequence of intermediate states** — text inputs, incremental parsers, accumulators, undo stacks, streaming decoders — a one-shot endpoint test is insufficient. Feed the intermediate states and assert the invariant holds throughout: the defect lives in the **transitions**, not the endpoints. One-shot tests pin the endpoints and are blind to the path between them.
