# Metronomad — v1 Specification

This document specifies what the Metronomad site lets users do and how the product behaves, from a user-facing perspective. It is the baseline specification for the first version; future changes go through change requests in `change-requests/`.

---

## 1. Purpose

Metronomad is a static web tool for musicians. The user loads an mp3 file, sets the song's tempo (BPM) and the point in the song where they want to enter (the **offset**), then plays a **lead-in**: a metronome count-in at the set tempo, followed by the song starting **exactly on the downbeat** at the offset.

The use case: a musician wants to practice joining a song on beat (e.g., starting their part at a specific verse or section) and needs a reliable, in-tempo count-in to land there.

**Non-negotiable property:** timing. The count-in clicks and the song start must be rhythmically exact. A count-in that drifts or lags defeats the purpose of the tool.

Everything runs in the browser. The audio file is never uploaded anywhere.

---

## 2. Core Workflow

1. **Load a song** — drag and drop an mp3 (or browse for one).
2. **Find the entry point** — scrub through the song to locate where the musician wants to start; this sets the offset.
3. **Set the tempo** — enter the BPM.
4. **Play** — the site counts in with metronome clicks at the BPM, then starts the song on the downbeat at the offset.
5. **Stop** at any time, or **Restart** to perform the lead-in again.

---

## 3. File Loading

- A prominent **drop zone** is the primary interaction in the empty state, plus a **Browse** button that opens the file picker.
- Audio files are accepted in any format Howler.js can decode; **mp3 is the primary target format** (the definitive supported-format list is established in `_agent_docs/research/howlerjs-research.md`).
- **One file at a time.** Loading a new file replaces the current one and resets playback state.
- On successful load, the UI shows the **filename** and the **song duration**.
- If the file cannot be decoded, an error message is shown and the app remains in the no-file state.
- The file stays on the user's machine (local object URL / in-memory decode only).

---

## 4. Tempo & Offset Controls

### BPM
- Numeric field, whole numbers, range **30–250**, default **120**.
- Supports direct typing and increment/decrement (±1).
- Out-of-range or invalid input is clamped to the valid range with a subtle indication.

### Offset (start point)
- The offset is the position in the song where playback begins after the count-in.
- Displayed as **mm:ss.t** (tenths of a second).
- Two ways to set it:
  - **Scrubber** — a slider spanning the full song duration; dragging it moves the offset marker.
  - **Direct entry** — the mm:ss.t value is editable as text.

### Offset Preview
- A small **Preview** action plays the song *from the offset* for a few seconds (no count-in) so the musician can confirm the entry point sounds right.
- Stopping the preview returns to the ready state and preserves the offset.

### Count-in Length
- The number of metronome beats played before the song starts.
- Numeric field, range **1–16**, default **4** beats (one bar of 4/4).

---

## 5. Lead-in (Count-in) Behavior

- Pressing **Play** begins the count-in after a short lead time: the first click lands **one beat after** the button press, giving the musician a moment to get ready.
- Clicks sound at the set BPM: beat interval = 60 / BPM seconds.
- **Accent pattern (4/4):** the first beat of every bar is accented (higher-pitched / louder click). If the count-in is longer than four beats, the accent repeats every four beats.
- **Click sound:** short, crisp, woodblock-style. Distinct pitch for the accent vs. the regular beat.
- **Song start:** the song begins at the beat boundary **immediately after the last count-in click**. That boundary is the song's downbeat — for a 4-beat count-in at 120 BPM, clicks land at t+0.5s, t+1.0s, t+1.5s, t+2.0s and the song starts at t+2.5s (i.e., one beat after the last click). The visual beat indicator marks that downbeat (see Section 7). No click sounds at the moment the song starts — the music itself is the downbeat.
- The count-in and the song start are scheduled on the same audio clock (Section 11), so the downbeat is rhythmically exact.

---

## 6. Playback Controls

- **Play** — enabled when a file is loaded. Starts the count-in → song sequence. While the sequence is running, the primary button shows **Stop**.
- **Stop** — stops the song and clicks immediately and returns to the ready state (offset/BPM preserved).
- **Restart** — available during the count-in or while the song is playing. Stops everything and immediately performs the lead-in again; the song starts again from the offset. This is the "let me hear that entry again" button.
- **Parameter locking:** while a sequence is running (count-in or song), the BPM, offset, and count-in controls are locked; changes take effect on the next Play. (No live tempo changes in v1.)

---

## 7. Beat Visualization

- A row of **four beat dots** representing one bar of 4/4; the downbeat (beat 1) is visually distinct (larger / different color).
- **During the count-in:** dots light up in time with each click; the row cycles if the count-in is longer than four beats.
- **During the song:** the dots keep pulsing at the BPM for the entire playback, giving the musician a continuous visual beat reference.
- Visual and audio beat timing are driven by the same clock — no visible drift between the clicks and the dots.

---

## 8. Song Progress

- During playback, a **progress indicator** shows the current song position (mm:ss.t).
- The **offset is marked** on the progress indicator so the user can see where the entry point sits.

---

## 9. States

| State | Description |
|-------|-------------|
| **No file** | Drop zone is the hero; all other controls disabled. |
| **Ready** | File loaded; BPM / offset / count-in controls and Play enabled. |
| **Counting in** | Clicks sounding, beat dots active; Stop and Restart available; parameters locked. |
| **Playing** | Song sounding, beat dots pulsing, progress advancing; Stop and Restart available; parameters locked. |
| **Ended** | The song finished; app returns to Ready automatically (song position reset to the offset). |
| **Error** | e.g., file failed to decode; message shown; app stays in the last valid state. |

---

## 10. Accessibility

- All controls are keyboard operable (Play / Stop / Restart are real buttons; the Browse button covers keyboard users who can't drag and drop; scrubber and numeric fields are natively accessible).
- State changes are announced to assistive technology (e.g., "Count-in started", "Song started", "Stopped") via a live region.
- Beat 1 is distinguishable by size/shape, not color alone.
- Beat-dot animation is a simple opacity/scale pulse (no motion beyond the pulse), keeping it safe for reduced-motion users.

---

## 11. Technical Considerations (inputs to the research phase)

These are product requirements expressed as technical constraints; implementation details belong in the research docs and plans, not here.

1. **Clock:** metronome clicks must be scheduled on the Web Audio clock (lookahead-scheduler pattern), not `setTimeout`/`setInterval` — timer-based clicks drift and jitter, which is unacceptable for this product.
2. **Sample-accurate song start:** the song must begin at a precise time on the same `AudioContext` clock, positioned exactly at the offset.
3. **Howler.js vs. raw Web Audio** (→ `_agent_docs/research/`): evaluate how to start an mp3 at an exact time with an exact seek position:
   - Howler in Web Audio mode (`seek()` + `play()` — how is the seek latency?)
   - Howler in `html5` mode (`HTMLAudioElement` seek/play events — latency and jitter?)
   - Raw Web Audio: `decodeAudioData()` → `AudioBufferSourceNode.start(when, offset)` — a sample-accurate primitive, at the cost of holding the decoded PCM in memory.
   - Click generation (short oscillator or pre-rendered buffer) scheduled with the same lookahead scheduler.
4. **Static hosting:** no build step; follows the repo pattern (single HTML entry point, ES modules, no backend).
5. **Autoplay policy:** all audio begins from a user gesture (the Play click), so `AudioContext.resume()` happens inside a gesture handler.

---

## 12. Non-Goals for v1

- BPM / key detection (any audio analysis)
- Multiple songs / a queue
- Persisting settings between visits
- Time signatures other than 4/4 (accent fixed to every 4th beat)
- Custom click sounds, volume sliders, or click-on/song-on muting
- Looping the song
- Server-side components of any kind
- Mobile-first layout polish (basic responsiveness is fine; not a focus)

---

## 13. Future Ideas (post-v1)

- Tap tempo
- Per-file saved settings (localStorage)
- Looping the song with an automatic re-count-in
- Volume controls (click vs. song)
- Metronome-only mode (no song loaded)
- Offset entry in beats (once BPM is known, snap the offset to the beat grid)
- Configurable time signature / accent pattern

---

## 14. Decisions (resolved 2026-08-17)

1. **Count-in length** — user-settable field; default 4, range 1–16.
2. **First-click lead time** — one beat after the Play press.
3. **Downbeat click** — click-free; the song's start is the downbeat.
4. **Accepted formats** — whatever Howler.js can decode (see `_agent_docs/research/howlerjs-research.md` for the definitive list).
5. **Button layout** — single Play↔Stop toggle plus a separate Restart button.
6. **Display name** — "Metronomad".
