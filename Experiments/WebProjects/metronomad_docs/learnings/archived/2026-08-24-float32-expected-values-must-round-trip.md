# Float32Array outputs must be compared against float32-constructed expectations — `expect(x).to.equal(-0.8)` fails

**Date:** 2026-08-24
**Context:** Metronomad CR 001 Phase 1, `MyComponents/WaveformPeaksTest.html` (WF-P1.3, WF-P1.5, WF-P1.8). First test battery in this repo whose production outputs are `Float32Array` (DSP). Phases 2–3 (tempo trains, pooled peaks) hit the same shape.

## The trap

Production DSP returns `Float32Array`. Reading an element back yields a **float64-widened float32 rounding** — `new Float32Array([-0.8])[0] === -0.8` is `false` (it is `-0.800000011920929`). Chai's `equal`/`deep.equal` compare numbers strictly, so the obvious test

```js
expect(result.mins[0]).to.equal(-0.8); // FAILS — even though the module is correct
```

fails for every value that is not exactly representable in binary: 0.1, 0.2, 0.7, 0.8, 0.9, 1.3, 1.7… Only dyadic rationals (0.25, 0.5, 1.0, 0) survive a literal comparison. The failure looks like an implementation bug and sends you debugging a module whose math is right.

## Rules

1. **Build expectations through the same conversion the production code uses.** In the test page:

   ```js
   const f32 = (...values) => Float32Array.from(values);
   // ...
   expect(result.mins).to.deep.equal(f32(-0.8, -0.8)); // exact, no tolerance
   ```

   Array-level `deep.equal` between two `Float32Array`s compares element bits — both sides went through float32, so the comparison is *exact*. Tolerance is not needed and not wanted here.

2. **Reserve `closeTo` for genuine float variation** (e.g., a sum/reduction whose accumulation order the test cannot trivially reproduce, or envelope magnitudes like WF-P1.2's `> 0.99` where the spec itself is a bound). When exact equality is achievable via rule 1, settling for tolerance is strictly weaker: it would let a real off-by-a-bit regression (corrupted pool boundary, wrong bucket) pass silently.

3. **`new Float32Array([x])[0]` is the oracle** for "what this module can represent." If you are unsure whether an expectation is float32-exact, assert against the oracle instead of the literal.

4. **Mixing conventions in one suite is the quiet variant of this bug:** a file where some assertions compare against literals (and happen to use only dyadic values) and others against `f32(…)` will mislead the next author into thinking literals are fine. Pick the convention per suite and state it in a comment where the helper is defined.

## Secondary observation: this is a *test-authoring* trap, not a runtime one

The production code is unaffected — float32 storage is the spec (peaks, channels). The entire failure mode lives in the expectation side of the test. When a DSP test "fails" with a difference of ~1e-7 on an otherwise-exact value, suspect the expectation's number type before the implementation.
