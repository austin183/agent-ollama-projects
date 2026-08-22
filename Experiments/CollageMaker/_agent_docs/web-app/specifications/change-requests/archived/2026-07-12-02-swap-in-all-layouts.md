# Duplicate Swap Behavior from Hexagon Layout to All Layouts

## Background & Problem Statement

Currently, the swap behavior (the ability for users to swap images between preview panels) is fully implemented and polished in the Hexagon layout. However, this functionality is not consistently available or behaves differently across other layouts in the CollageMaker web app. This creates an inconsistent user experience where users who start with a hexagonal layout and then switch to a different layout (or vice versa) may find that their ability to swap images between panels changes unexpectedly.

From a UX perspective, image swapping is a core creative workflow. Users frequently want to experiment with which images go in which panels to achieve the best visual composition. When this capability is only available or works differently in certain layouts, it creates friction and confusion in the user journey.

## User Experience Goals

- **Consistent Creative Workflow**: Users should be able to swap images between panels regardless of which layout they're using. The creative process shouldn't be interrupted by layout-specific feature limitations.
- **Predictable Interaction Model**: The gesture or UI pattern for swapping images (e.g., drag-and-drop, tap-to-select then tap-to-swap, dedicated swap button) should work the same way across all layouts.
- **Visual Feedback During Swap**: Users should receive clear visual feedback when they initiate a swap, during the swap animation/movement, and after the swap completes, regardless of layout type.
- **Layout-Aware Swap Validation**: While the core swap interaction should be consistent, the system should still respect layout-specific constraints (e.g., panel sizes, shapes, or positions) when validating whether a swap is valid.

## User Scenarios & Use Cases

### Scenario 1: Cross-Layout Image Experimentation
A user creates a collage using the Hexagon layout and spends time arranging images to their satisfaction. They then decide to try the same images in a Standard Grid layout to see how they look with different panel shapes and arrangements. When they switch layouts, they expect to be able to continue swapping images between panels using the same gestures or UI controls they were already familiar with.

### Scenario 2: Quick Layout Comparison
A user is deciding between two different layouts for their collage. They create a base arrangement in one layout, then quickly duplicate or switch to another layout to compare how the same images look in different geometric arrangements. During this comparison phase, they frequently swap images between panels to test different visual compositions. The swap functionality should be equally accessible and intuitive in both layouts.

### Scenario 3: Fixing a Misplaced Image
A user has placed an image in a panel but realizes it would work better in another panel's position (perhaps due to color contrast, subject matter, or composition). They want to quickly swap that image with the one currently in the target panel without having to re-import or re-select images. This should work seamlessly across all available layouts.

### Scenario 4: Accessibility and Alternative Interaction Methods
Some users may prefer keyboard navigation or screen reader interactions over mouse/touch gestures. The swap functionality should provide consistent alternative interaction methods across all layouts, ensuring that users who rely on assistive technologies can swap images regardless of which layout they're using.

## UX Considerations for Swap Behavior Across Layouts

### Interaction Methods to Standardize
1. **Drag-and-Drop Swapping**: Users drag an image from one panel and drop it onto another panel to swap their positions. This should work consistently across all layouts with visual feedback during the drag (e.g., highlighting the target panel, showing a preview of the swap).

2. **Select-Then-Swap Pattern**: Users tap or click to select a panel/image, then tap a "Swap" button or use a context menu to initiate swapping with another selected panel. This pattern should be available in all layouts with consistent UI placement and behavior.

3. **Keyboard/Accessibility Swapping**: Users should be able to navigate between panels using keyboard controls (arrow keys, tab) and trigger swaps using consistent keyboard shortcuts or accessibility actions.

### Visual Feedback Requirements
- **Hover/Active State Indicators**: When a user hovers over or selects a panel for swapping, the panel should have clear visual feedback (e.g., border highlight, subtle glow, or overlay).
- **Swap Animation**: When a swap is executed, there should be a smooth animation showing the images moving between panels, helping users understand what changed and maintaining spatial awareness.
- **Error/Invalid State Feedback**: If a swap cannot be performed (e.g., due to layout constraints or missing images), users should receive clear, non-disruptive feedback about why the swap didn't occur.

### Layout-Specific Considerations
While the core swap interaction should be consistent, different layouts have unique characteristics that affect the swap experience:

- **Rectangular Grids**: Panels are uniform or predictably sized; swaps are straightforward with clear visual boundaries.
- **Diagonal Slices/irregular shapes**: Panels may have different orientations or overlapping visual areas; swap feedback needs to clearly show which image is moving where despite complex panel geometries.
- **Hexagon layouts**: Panels have a specific radial or honeycomb arrangement; the swap UI should adapt to this geometry while maintaining consistent interaction patterns.
- **Asymmetric layouts**: Panel sizes and positions vary significantly; users need clear visual hierarchy to understand which panels are primary vs. secondary when swapping.

## Success Criteria from a UX Perspective

1. Users can successfully swap images between any two panels in any available layout without encountering layout-specific errors or confusing behavior.
2. The visual feedback during swap interactions (hover, select, drag, animate, complete) is consistent and clear across all layouts.
3. Users who are familiar with the swap behavior in the Hexagon layout can immediately apply that knowledge to other layouts without needing to relearn the interaction pattern.
4. Accessibility users can perform swaps using keyboard or screen reader interactions consistently across all layouts.
5. The swap animations and transitions help maintain user spatial awareness, especially in layouts with complex panel geometries or non-standard arrangements.