# Diagonal Slices Preview Adjustments
Currently, when the slice angle is greater than 0 degrees, the panels tilt off the preview image, but I think it needs to remain centered with diagonal slices that always stay within the preview image boundaries.

The idea is that we want all the panels tilted at the angle, but that the panels fully cover the preview image space and clip along the edges so they do not overflow out of the panel window.

Let's say I add one picture.  That one picture should take up the whole space on its own, no matter the angle.
If I add a second picture, I expect the panels to show the angle in the middle, but the two panels would still take up the full space of the preview window without spilling over.  If I add a third picture, I expected the three pictures to appear at the angle, with the first picture wide enough to stretch out to the left, and the third picture wide enough to stretch out to the right.  Then all the pictures get clipped back down to not overflow out of the preview window.

File Reference - `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Services/LayoutGenerator.swift`