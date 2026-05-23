# New Layout Styles Implementation
- Related to plans in `Experiments/CollageMaker/_agent_docs/plans/2026-05-22-new-layout-styles-plan.md`
- Add three new enum cases to `LayoutStyle`: `.doubleExposure`, `.diagonalSlices`, and `.hexagonal`.
- Update `LayoutGenerator.swift` to handle the geometry for these specific styles.
- Will also require thinking about how to show the Panel Editor in the Right Hand Sidebar with various shapes

## Style 1: Double Exposure (Silhouette Mask)
- **Visual Description:** Based on Image 1. This is a standard grid layout (similar to `.uniform` or `.mosaic`) but with a large, semi-transparent silhouette mask (e.g., a human profile or abstract shape) overlaid on top of the entire collage.
- **Implementation:**
    - The layout logic should generate standard rectangular panels for the background images.
    - The rendering engine must support a "Global Mask" or "Overlay" layer that sits on top of the generated panels.
    - The mask should be a predefined asset (e.g., `silhouette_profile.png`).

## Style 2: Diagonal Slices
- **Visual Description:** Based on Image 2. The canvas is divided into angled strips running from top-left to bottom-right (or vice versa), separated by white gutters.
- **Implementation:**
    - This requires changing `ImagePanel` to support polygonal clipping paths (`CGPath`) or `CAShapeLayer` masks, as the panels are parallelograms, not rectangles.
    - **Algorithm:**
        - Calculate the angle of the slice (e.g., 60 degrees).
        - Divide the canvas width/height into $N$ segments based on the number of images.
        - Apply a shear transform or generate specific polygon points for each image frame to create the slanted effect.

## Style 3: Hexagonal / Radial Honeycomb
- **Visual Description:** Based on Image 3. A "Hero" style layout where the first image is placed in the exact center, and subsequent images surround it in a ring, forming a honeycomb/hexagonal pattern.
- **Implementation:**
    - **Algorithm:**
        - Image 0 is centered in the canvas.
        - Remaining images are calculated using trigonometry (sine/cosine) to position them in a circle around the center image.
        - **Clipping:** Unlike the current `CGRect` frames, these panels must be clipped to hexagonal shapes using `UIBezierPath` or `CGPath` to create the distinct honeycomb edges.

## Technical Requirements
- **ImagePanel Update:** The `ImagePanel` struct currently uses `frame: CGRect`. It needs to be updated to optionally accept a `clipPath: CGPath?` or `maskImage: UIImage?` to support the non-rectangular shapes in the Diagonal and Hexagonal styles.
- **Gutter Handling:** The `gutter` parameter in `LayoutGenerator` needs to be applied differently for these styles (e.g., in Diagonal mode, gutters are parallel lines; in Hexagonal mode, gutters are the gaps between hexagons).