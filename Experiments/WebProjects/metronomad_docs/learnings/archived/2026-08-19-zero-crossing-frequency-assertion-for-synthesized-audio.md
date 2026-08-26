# Asserting Synthesized Audio Frequency via Zero-Crossing Count

**Date:** 2026-08-19
**Context:** Metronomad Phase 4 — H-03: `renderClickBuffers(ctx)` must produce an accent (1568 Hz) and a regular (1047 Hz) click buffer that are *audibly and measurably different*, testable in-browser without an FFT or any new tooling

## The Problem

"Assert the buffers are different" is weak — a test that only checks `accent !== regular` (object identity) passes even if both buffers encode the same frequency. A meaningful assertion needs to recover the dominant frequency from raw samples. Options considered:

- **FFT** — overkill for a single pure tone; ~40 lines or a new dependency.
- **Autocorrelation** — same overkill.
- **Zero-crossing count** — ~10 lines, exact for pure tones (which click buffers are).

## The Pattern

```javascript
const dominantFreq = (buf) => {
    const data = buf.getChannelData(0);
    let crossings = 0;
    for (let i = 1; i < data.length; i++) {
        if ((data[i - 1] < 0 && data[i] >= 0) || (data[i - 1] >= 0 && data[i] < 0)) crossings++;
    }
    return crossings / 2 / buf.duration; // full cycles per second
};
expect(dominantFreq(accent)).to.be.within(1400, 1700);   // ~1568 Hz
expect(dominantFreq(regular)).to.be.within(900, 1200);   // ~1047 Hz
```

Assert with **tolerance bands**, not exact values: a 60 ms window at 44.1 kHz contains ~94 cycles (accent), so the count estimate is accurate to roughly ±1 cycle (~±10 Hz) — and the attack ramp + decay envelope slightly distort edge crossings. Bands of ±10–15% keep the test deterministic while still failing if the frequency constant is wrong or the buffers are swapped.

## Why It's Worth a Note

- **Pure tones are the only case where this is reliable** — click buffers, beeps, and test sines qualify; anything harmonic or noisy needs real spectrum analysis.
- **It tests the artifact, not the configuration.** Asserting `CLICK.ACCENT_FREQ === 1568` (the constant) pins the *intent*; the zero-crossing assertion pins that the *render actually used it*. Both are in H-03 for the same reason the "Testing Default Behavior Explicitly" skill rule exists — the constant can drift from the render.
- Pairs with a **tail-silence assertion** for click artifacts: `max(abs(last N samples)) < 0.001` catches a missing decay (audible click-on at buffer end).

## When It Does NOT Work

- Multi-tone or shaped content (chords, speech, music) — zero-crossings conflate all partials.
- Very short buffers (< ~2 cycles) — too few crossings for a stable estimate.
- Buffers with DC offset — crossings no longer mark cycle midpoints.

## Skill Mapping

- **`building-web-apps` → `references/testing-unit.md`** (or the audio reference being planned, see `2026-08-19-terminal-event-before-poll-transition-race.md`): short "Testing Synthesized Audio" note — zero-crossing frequency bands + tail-silence check + the H-03 real-AudioContext-isolate pattern (one `new AudioContext()` in `before`/`after` for the render test; the *engine* tests stay at zero real contexts).
- **CollageMaker/Metronomad test pages** — reuse as-is; the helper is self-contained and needs no page wiring.

---
**Status:** Closed (pattern landed in Phase 4 H-03)
**Follow-up:** done — pattern included in `building-web-apps/references/audio-scheduling.md` (2026-08-19)
