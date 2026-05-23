# Panel Editor Scroll and Zoom Input Change
## Use click and drag for Panel Editor instead of gestures
- Currently, the Panel Editor uses the same gestures to scroll and zoom as the main image, with pinch and two finger scrolling input.
- We want to chane it so the Panel Editor takes click and drag inputs, with a resizable overlay to determin the zoom level
- Clicking and dragging on the overlay should move the overlay
- Clicking on a corner of the overlay should resize the overlay in proportion to the panel

This change is meant to give the user variety in input methods.

## Overlay Visual Feedback Change
To let the user know they can use the corners of the overlay to resize, the corners should have a bolded effect, similar to the one used for the sides of the Title Image box that lets the user know they can grab the side and drage it.