# Big Idea

A static web app that acts as a **metronome for mp3 files**. A musician provides an mp3 file, sets the **beats per minute** and a **start offset** (the point in the song where they want to join in), and the site performs a **rhythmic lead-in**: a metronome count-in at the set tempo, after which the song starts **exactly on the downbeat** at the offset. This lets a musician rehearse entering a song on beat without a bandmate or a DAW.

Core v1 surface (intentionally small):
- File drop for the mp3
- Start offset control
- Beats-per-minute field
- Play / restart buttons that perform the lead-in

**Key property:** the whole thing runs client-side. The audio file never leaves the machine — no upload, no backend.

**Current location:** `~/workspace/austin183.github.io/Metronomad/`
