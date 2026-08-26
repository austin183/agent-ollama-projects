# Plan-pinned DSP numbers break in units, not arithmetic — recompute dimensions, bounds, and cross-row consistency when transcribing

**Date:** 2026-08-24
**Context:** Metronomad CR 001, Phases 1–2 (pure Analysis modules). Three plan-time numeric errors in one CR, all caught at build time by test transcription: (1) the sine3s bucket math was *inverted* (132 300 samples @ 4096 buckets = 4096 buckets × ≈32 samples, not "≈32 buckets"); (2) the D-D lag-range illustration `p ∈ [H·60/BPM_MAX, H·60/BPM_MIN] frames (≈123…1024 @ 48 kHz)` was dimensionally wrong — `H·60/BPM` omits `sampleRate`, so it is not a frame count at any rate; (3) TD-1.3 and TD-1.7 pinned **byte-identical Given** (20 clicks at t = 0…19 s, 1 s spacing, 44.1 kHz) with contradictory Then (60 ± 1 vs 120-or-null-never-60) — a pure function cannot satisfy both.

## The trap

Planning-time "worked-example recompute" checks that the plan's own arithmetic is internally consistent *as written*. It does not check that the numbers carry the **right units**, that Given values are **in range**, or that **two rows describing the same input agree** — because those errors are invisible to per-row arithmetic: `512 × 60 / 250 = 122.88` is correct arithmetic for a wrong quantity (it is a *sample* count, not a *frame* count), and each of TD-1.3's and TD-1.7's rows is individually sensible. The failure only surfaces when the test author materializes the Given into real samples and asks "which lag is this, in frames, at this rate?"

## Rules

1. **When transcribing a plan-pinned numeric example into a test or implementation, recompute its dimensions** — write the quantity's units out (samples × rate ÷ hop = frames; samples ÷ rate = seconds; samples ÷ buckets = samples/bucket). If the plan's formula lacks the rate where the units require it (or has it where the units don't), that is a plan bug, not an implementation choice: implement the dimensionally-correct version per the governing constraint (W-8 here: sampleRate explicit), and correct the plan in place with a dated note.
2. **Bounds-check Given values against their containers** (spike index vs buffer length, sample count vs stride, onset count vs window). Phase 1's spike-at-40 000 000-in-a-20 000 001-sample buffer is this class.
3. **Cross-check rows with identical Given.** When two scenario rows materialize to the same input, their Then must agree for any pure function. If they don't, the contradiction is a plan bug: pick the reading the higher-priority/more-specific pin supports (here: the P0 mechanism note over the P1 row's expectation), implement that, assert it in the test with a comment naming the contradiction, surface it in the session summary, and correct both plan files in place.
4. **Build-time test transcription is the backstop — expect it to catch these.** The planning-pass spot-verification (Phase 1/2 "Key Discoveries") corrected *anchors* (file:line) but missed all three numeric errors above; each was found when the test author actually built the input. Do not "fix" the test to match the plan's number — fix the plan.

## Why it matters

A dimensionally-wrong plan pin that slips through produces a wrong *implementation* that passes a wrong *test* — the suite is green and the feature is subtly broken (in the lag case: a 120 BPM train would be unfindable because lag 43 would sit below the "123" floor). The unit recompute costs seconds and is the only check that catches this class at all.
