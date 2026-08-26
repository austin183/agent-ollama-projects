# Synopsis
The elements to expand and hide the two sidebars and the hamburger for mobile are all positioned and styled in a way that visually decouples them from what they are meant to do.

## Hamburger change for Mobile
I want to move the hamburger icon down to the bottom of the screen and change its icon for expanding the bottomsheet. That way it does not have to take up space in the top toolbar and it will be coupled with the animation that brings the bottomsheet up from the bottom.

**Review recommendations:**
- Replace the `menu` (hamburger) icon with an upward-pointing chevron (`keyboard_arrow_up` or `expand_less`) to visually couple with the bottom-sheet animation rising from the bottom.
- Implement as a floating circular button (FAB style) with a minimum **48x48px** touch target, positioned bottom-center or bottom-right.
- Use a semi-transparent or solid brand-color background so the button is visible against canvas content.
- Ensure it does not occlude the canvas drop zone or critical touch interactions.

## Sidebar icons
I want these to also move out of the top toolbar and become icons attached to the left and right borders of the screen so that when the sidebar is collapsed, the user can see the icon to expand it as a left or right arrow, depending on which direction the sidebar will animate on the click.

- If the sidebar is on the left and the click will expand, the icon should point to the right. If the click would collapse it, it should point to the left.
- If the sidebar is on the right and the click will expand, the icon should point to the left. If the click would collapse it, it should point to the right.

**Pre-existing bug:** The current left sidebar toggle icon logic is inverted — it shows `chevron_right` when open (should be `chevron_left`) and `chevron_left` when closed (should be `chevron_right`). This change implicitly fixes that bug.

**Review recommendations:**
- Give each floating icon a distinct visual container (rounded circle or pill shape with a solid background color matching the theme) so it stands out against the canvas.
- Implement CSS hover states (background color change, subtle `box-shadow`) to improve discoverability.
- Minimum size: **40x40px** for comfortable mouse targeting.
- Position absolutely on the viewport edges, outside the canvas drop zone, with `z-index: ~200` (above canvas, below modals/toasts).
- Ensure `pointer-events: auto` so the icons remain clickable without intercepting canvas drag-and-drop.
- Add tooltip text for discoverability (e.g., "Expand left sidebar" / "Collapse left sidebar").

## Accessibility Requirements
- Keep `<button>` elements with `aria-expanded="true|false"` on all three toggles (left sidebar, right sidebar, mobile bottom sheet).
- Add `aria-controls` linking each button to its target panel (`sidebar-left`, `sidebar-right`, `bottomSheet`).
- Use dynamic `aria-label` that reflects the current action: "Expand left sidebar" when collapsed, "Collapse left sidebar" when open (and similarly for the right sidebar and bottom sheet).
- Ensure `Enter` and `Space` key operability on all floating icons.
- Consider moving programmatic focus to the first interactive element within the newly expanded panel (e.g., the image library search input) after toggle activation.
