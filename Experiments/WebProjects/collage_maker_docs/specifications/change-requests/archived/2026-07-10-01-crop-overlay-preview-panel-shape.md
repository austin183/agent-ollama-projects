# Preview Panel Shaped Crop Overlay with Resizing and Image Boundaries

## Problem Statement

Right now, the web app uses a rectangular overlay for every preview panel and draws the preview panel's shape inside the rectangle. This creates a disconnect between what users see in the layout grid and what they are actually cropping. When users interact with the crop overlay, they're manipulating a rectangular bounding box rather than the actual visible shape of the panel (e.g., triangles, trapezoids, or irregular polygons).

We want to get the crop overlay to be a 1-to-1 shape match with the preview panel. This means the interactive crop overlay should precisely follow the geometric boundaries of each panel's shape, allowing users to crop exactly within the visible area they see in the collage grid.

Some layouts make this more difficult than others. Especially the Diagonal Slices layout since it introduces new boundary behavior considerations and 3-sided, 4-sided, and 5-sided shapes that require perspective transformation math rather than simple rectangular clipping.

## User Experience Goals

- **Visual Fidelity**: Users should see the crop overlay match exactly what they see in the preview panel shape. When a panel is triangular or diagonally sliced, the crop handles and boundaries should follow those exact edges.
- **Intuitive Cropping**: Users shouldn't have to mentally translate between a rectangular crop box and an irregular panel shape. The cropping experience should feel natural and direct.
- **Predictable Boundaries**: When users drag crop handles or pan within the overlay, they should understand exactly which parts of their image will be included in the final collage based on the visible panel shape.
- **Consistent Interaction Across Layouts**: While some layouts have simple rectangular panels and others have complex polygons, the core interaction model (select, pan, zoom, crop) should feel consistent even if the underlying geometry differs.

## User Scenarios & Use Cases

### Scenario 1: Cropping a Triangular Panel
A user selects a layout with triangular preview panels (like Diagonal Slices). They tap on a panel to enter crop mode and expect to see a triangular crop overlay that matches the triangle's edges exactly. When they pan or zoom, the image should stay within the triangular boundaries, and the corner handles should allow them to adjust the visible area while respecting those angular constraints.

### Scenario 2: Cropping an Irregular Polygon Panel
In layouts with 4-sided or 5-sided irregular shapes (trapezoids, skewed rectangles), users need to be able to see which parts of their image will actually render in that panel. The crop overlay should visually indicate the active cropping area within the polygon shape, and users should be able to adjust it without accidentally including areas that would be clipped by the panel's geometric boundaries.

### Scenario 3: Understanding What Gets Exported
When a user finishes cropping and exits crop mode, they need clear visual feedback about what portion of their image will actually appear in the final exported collage. The preview should accurately reflect the cropped area within the specific panel shape, not just a rectangular subset.

## UX Considerations for Different Layouts

### Rectangular Panels (Standard Grids)
- Simple rectangular crop overlays work as expected
- Standard 4-corner resize handles and pan/zoom interactions
- No special boundary considerations beyond image aspect ratio

### Triangular Panels (Diagonal Slices, some triangle-based layouts)
- Crop overlay must be a triangle matching the panel's vertices
- Users need to understand that dragging outside the triangular area won't affect the crop
- Visual indicators should show the active triangular cropping region clearly
- Corner handles may need to be positioned at the triangle's vertices or along edges

### 4-Sided Irregular Panels (Trapezoids, Skewed Rectangles)
- Crop overlay follows the quadrilateral shape
- Perspective transformation may be needed to properly map the image within the skewed boundaries
- Users should see clear visual feedback about how the skewed shape affects their image

### 5-Sided or Complex Polygon Panels
- More complex boundary behavior considerations
- May require decomposing the polygon into triangles for rendering and cropping logic
- UX needs to clearly communicate which parts of the image are included vs. clipped

## Visual Feedback & Interaction Design Requirements

1. **Overlay Visibility**: The crop overlay should be visually distinct from the background but clearly show the underlying panel shape boundaries (e.g., semi-transparent overlay with highlighted edges).

2. **Handle Placement**: Resize/crop handles should only appear at valid positions that respect the panel's geometric shape (e.g., corners of triangles, midpoints of edges for adjustment).

3. **Panning Constraints**: When users pan within the crop overlay, the image movement should be constrained so they don't accidentally drag visible content outside the panel's shape boundaries in a confusing way.

4. **Zoom Behavior**: Zooming should maintain the center of focus within the panel shape, and zoomed-out states should clearly show which parts of the image fall outside the panel's visible area.

5. **Boundary Indicators**: Users should have visual cues (like edge highlights or subtle shading) that indicate where the panel shape ends and where image content would be clipped.

## Some Sample Code
Take this code with a grain of salt, but maybe it could be helpful.
```
// Source - https://stackoverflow.com/a/30566272
// Posted by markE, modified by community. See post 'Timeline' for change history
// Retrieved 2026-07-10, License - CC BY-SA 3.0

var canvas=document.getElementById("canvas");
var ctx=canvas.getContext("2d");
var canvas1=document.getElementById("canvas1");
var ctx1=canvas1.getContext("2d");

// anchors defining the warped rectangle
var anchors={
  TL:{x:70,y:40},      // r
  TR:{x:377,y:30},     // g
  BR:{x:417,y:310},    // b
  BL:{x:70,y:335},     // gold
}

// cornerpoints defining the desire unwarped rectangle
var unwarped={
  TL:{x:0,y:0},        // r
  TR:{x:300,y:0},      // g
  BR:{x:300,y:300},    // b
  BL:{x:0,y:300},      // gold
}

// load example image
var img=new Image();
img.onload=start;
img.src="https://dl.dropboxusercontent.com/u/139992952/multple/skewed1.png";
function start(){

  // set canvas sizes equal to image size
  cw=canvas.width=canvas1.width=img.width;
  ch=canvas.height=canvas1.height=img.height;

  // draw the example image on the source canvas
  ctx.drawImage(img,0,0);

  // unwarp the source rectangle and draw it to the destination canvas
  unwarp(anchors,unwarped,ctx1);

}


// unwarp the source rectangle
function unwarp(anchors,unwarped,context){

  // clear the destination canvas
  context.clearRect(0,0,context.canvas.width,context.canvas.height);

  // unwarp the bottom-left triangle of the warped polygon
  mapTriangle(context,
              anchors.TL,  anchors.BR,  anchors.BL,
              unwarped.TL, unwarped.BR, unwarped.BL
             );

  // eliminate slight space between triangles
  ctx1.translate(-1,1);

  // unwarp the top-right triangle of the warped polygon
  mapTriangle(context,
              anchors.TL,  anchors.TR,  anchors.BR,
              unwarped.TL, unwarped.TR, unwarped.BR
             );

}


// Perspective mapping: Map warped triangle into unwarped triangle
// Attribution: (SO user: 6502), http://stackoverflow.com/questions/4774172/image-manipulation-and-texture-mapping-using-html5-canvas/4774298#4774298
function mapTriangle(ctx,p0, p1, p2, p_0, p_1, p_2) {

  // break out the individual triangles x's & y's
  var x0=p_0.x, y0=p_0.y;
  var x1=p_1.x, y1=p_1.y;
  var x2=p_2.x, y2=p_2.y;
  var u0=p0.x,  v0=p0.y;
  var u1=p1.x,  v1=p1.y;
  var u2=p2.x,  v2=p2.y;

  // save the unclipped & untransformed destination canvas
  ctx.save();

  // clip the destination canvas to the unwarped destination triangle
  ctx.beginPath();
  ctx.moveTo(x0, y0);
  ctx.lineTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.closePath();
  ctx.clip();

  // Compute matrix transform
  var delta   = u0 * v1 + v0 * u2 + u1 * v2 - v1 * u2 - v0 * u1 - u0 * v2;
  var delta_a = x0 * v1 + v0 * x2 + x1 * v2 - v1 * x2 - v0 * x1 - x0 * v2;
  var delta_b = u0 * x1 + x0 * u2 + u1 * x2 - x1 * u2 - x0 * u1 - u0 * x2;
  var delta_c = u0 * v1 * x2 + v0 * x1 * u2 + x0 * u1 * v2 - x0 * v1 * u2 - v0 * u1 * x2 - u0 * x1 * v2;
  var delta_d = y0 * v1 + v0 * y2 + y1 * v2 - v1 * y2 - v0 * y1 - y0 * v2;
  var delta_e = u0 * y1 + y0 * u2 + u1 * y2 - y1 * u2 - y0 * u1 - u0 * y2;
  var delta_f = u0 * v1 * y2 + v0 * y1 * u2 + y0 * u1 * v2 - y0 * v1 * u2 - v0 * u1 * y2 - u0 * y1 * v2;

  // Draw the transformed image
  ctx.transform(
    delta_a / delta, delta_d / delta,
    delta_b / delta, delta_e / delta,
    delta_c / delta, delta_f / delta
  );

  // draw the transformed source image to the destination canvas
  ctx.drawImage(img,0,0);

  // restore the context to it's unclipped untransformed state
  ctx.restore();
}
```