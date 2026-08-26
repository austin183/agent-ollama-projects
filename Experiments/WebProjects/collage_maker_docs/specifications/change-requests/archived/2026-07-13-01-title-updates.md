# Enhanced Title Features

## Movable Title Box
The Title area should have an outline around it, and the user can click within the outline to grab the Title box and drag it to new areas of the screen.

### UX Details & Requirements:
- **Visual Feedback**: Add hover states (e.g., `cursor: move`, subtle highlight) to indicate the area is draggable before clicking.
- **Edit vs. Drag Distinction**: Users need clear differentiation between "editing text" and "moving the box." The outline should only appear when the title is selected, or a specific handle/icon should be provided for dragging separate from the text editing area.
- **Boundary Constraints**: Ensure the title box cannot be dragged completely off-screen or outside the canvas bounds.

## Resizable Width with Click and Drag Sides
Grabbing the Left and Right hand sides of the title box should allow the user to expand the width of the background and the Width of the Title Lines for purpose of alignment.

### UX Details & Requirements:
- **Resize Handles**: Use clear visual indicators for the resize handles (e.g., vertical double-sided arrows `↔` or subtle drag handle icons) on the left and right edges.
- **Minimum/Maximum Constraints**: Define sensible min/max width limits so titles don't become unreadably narrow or overflow the canvas.
- **Live Preview**: Show the background and title lines expanding/contracting in real-time as the user drags the resize handles.

## Opacity / Alpha for Font and Background Colors
The Font and Background Color Pickers do not allow for opacity settings, so they always appear fully opaque. Can we add opacity sliders for those colors? (Note: Native browser `<input type="color">` has inconsistent alpha channel support across browsers - Chrome supports it with a transparency slider, but Safari/Firefox may not.)

### UX Details & Requirements:
- **UI Organization**: Place each opacity slider directly adjacent to its corresponding color picker (font color + font opacity slider; background color + background opacity slider) to avoid confusion.
- **Visual Feedback**: Show a checkerboard pattern or semi-transparent preview when adjusting opacity so users can see the effect in context over the collage images.

## Alignment Behavioral Changes
The Left, Center, and Right Alignment should work within the user's configured width for the Title and Background.

### UX Details & Requirements:
- **Clear Affordances**: Ensure the Left/Center/Right alignment buttons are visually grouped with other title formatting controls in the UI.
- **Live Preview**: Alignment changes should reflect immediately on the canvas as users click the alignment options.
- **Visual Guides**: Consider showing subtle alignment guides or markers when a user is adjusting width or moving the title box, to help them understand how alignment relates to the background width.