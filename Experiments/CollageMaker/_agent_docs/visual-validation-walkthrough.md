🎨 CollageMaker Visual Validation Walkthrough

Phase 1: Asset Ingestion & Initial Layout
Goal: Verify that adding images triggers the correct layout regeneration and initial rendering.

1. Image Loading: Add a small batch of images (3-5), then a large batch (20+).
   • Verify: Does the layout regenerate instantly? Is there any "hitch" in the UI during regenerateLayout?
2. Initial Fit: Check the initial crop of each image.
   • Verify: Do images fill their panels correctly without stretching?
3. Saliency Trigger: Run analyzeSaliency().
   • Verify: If a saliency overlay is active, does it appear accurately over the images?

Phase 2: Structural Manipulation
Goal: Test the layout engine's flexibility and the "Live" feel of structural changes.

1. Layout Style Rotation: Cycle through every LayoutStyle (Grid, Diagonal, Hexagonal, etc.).
   • Verify: Do panels snap to the new positions? Do existing crops attempt to persist (preserveCrops: true)?
2. The Gutter Stress Test: Rapidly slide the Gutter value from $0$ to max.
   • Verify: Is the feedback "live" and smooth? (Tests the gutter debouncer).
3. Style-Specific Tweaks:
   • Diagonal: Change diagonalSliceAngle.
   • Hexagonal: Change hexagonalSpacing.
   • Verify: Do these changes update the preview without needing a manual refresh?
4. Image Reordering: Drag images to change their order in the library.
   • Verify: Do the images swap positions in the collage immediately?

Phase 3: Precision Cropping & Gestures
Goal: Ensure the most high-frequency interactions are performant and intuitive.

1. Pan & Zoom:
   • Perform a slow pan $\rightarrow$ verify live update.
   • Perform a rapid flick pan $\rightarrow$ verify the debounced "catch-up" render.
   • Perform a pinch-zoom $\rightarrow$ verify the image scales within the panel.
2. The "Reset" Cycle: Zoom/Pan an image to an extreme, then call resetCrop(panelId:).
   • Verify: Does it snap back to the original center?
3. Overlay Adjustment: If using a Panel Editor, drag the crop handles.
   • Verify: Does the image inside the panel update in real-time as the handle moves?
4. Scroll-Pan: Use the scroll wheel/trackpad to pan a selected panel.
   • Verify: Is the scrollSensitivity feeling natural?

Phase 4: Aesthetic & Background Layers
Goal: Verify that the background doesn't interfere with the foreground panels.

1. Background Styles: Switch between Solid $\rightarrow$ Gradient $\rightarrow$ Image.
   • Verify: Does the transition happen smoothly?
2. Gradient Tuning: Change gradientStartColor, gradientEndColor, and gradientAngle simultaneously.
   • Verify: Does the background update without lagging the main UI thread?
3. Opacity Blend: Slide backgroundOpacity from $0%$ to $100%$.
   • Verify: Does the background disappear/appear without affecting the panels?
4. Double Exposure Mask: Upload a mask image and adjust doubleExposureMaskOpacity.
   • Verify: Does the mask correctly clip the layout?

Phase 5: Typography & Title Management
Goal: Ensure the title layer is independent and correctly positioned.

1. Content & Style: Change the title text, font family, and size.
   • Verify: Does the text wrap or clip correctly?
2. Visual Styling: Toggle showBackground and change the title background color.
   • Verify: Does the background box resize to fit the text?
3. Spatial Movement: Drag the title around the canvas.
   • Verify: Does it move at 60fps? Does it stay on the top-most layer?
4. Alignment: Cycle through Left, Center, and Right alignment.

Phase 6: The "Destruction" & Recovery Cycle
Goal: Ensure the Undo system and "Clear All" don't leave the app in a zombie state.

1. The Undo Gauntlet:
   • Change Layout $\rightarrow$ Pan Image $\rightarrow$ Change Title $\rightarrow$ Change Background $\rightarrow$ Remove Image.
   • Action: Undo every single step in reverse.
   • Verify: Does the app return exactly to the starting state?
2. Clear All: Populate a complex collage, then call clearAll().
   • Verify: Are all managers (Crop, Title, Background) reset to defaults?
   • Action: Undo the "Clear All".
   • Verify: Does the entire complex state return instantly?

Phase 7: Export & Final Quality
Goal: Verify that the "Final" render matches the "Preview" render.

1. Quality Shift: Change exportQuality from $0.1$ to $1.0$.
2. The Export Test: Run exportCollage().
   • Verify: Does the exported file match the visual state of the preview exactly?
   • Verify: Does the isProcessing state correctly block/indicate work to the user?