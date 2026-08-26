# Moving Layout from Right Sidebar to Left Sidebar

## Goal

Move the **Layout** section from the Right Sidebar to the Left Sidebar, and make the Image Library a collapsible section as well. This balances the sidebars and groups related concerns together.

## Current Structure

- **Left Sidebar:** Image Library (always visible, image thumbnails with search)
- **Right Sidebar:** Collapsible sections — Layout, Title, Crop, Background, Overlay, Export

## Proposed Structure

- **Left Sidebar:** Collapsible "Image Library" section + Collapsible "Layout" section
- **Right Sidebar:** Collapsible sections — Title, Crop, Background, Overlay, Export

## Rationale

### Logical grouping
- **Left Sidebar (Image Library + Layout):** Both deal with *multiple images* at the collection level. Layout determines how images are arranged together; Image Library shows the available images to arrange.
- **Right Sidebar (Title, Crop, Background, Overlay, Export):** Canvas-level or per-element editing tools applied after the layout is chosen.

### Workflow alignment
1. Load images → see them in Left Sidebar (Image Library)
2. Choose arrangement → adjust Layout settings (Left Sidebar)
3. Fine-tune individual panels → use Crop (Right Sidebar)
4. Adjust overall styling → Background/Overlay (Right Sidebar)
5. Export → Export (Right Sidebar)

### Why not move Crop instead?
- Crop is a per-panel operation (applied to a selected panel via canvas interaction)
- Layout is a global arrangement concern (applies to all images in the collage)
- Moving Crop to the left would separate it from other per-panel/canvas editing tools
- Moving Layout to the left keeps "image collection" concerns grouped together

## Implementation Notes

- Make Image Library a collapsible section with the same pattern as existing Right Sidebar sections
- Move Layout section HTML and associated controls to the Left Sidebar
- Maintain collapsible section behavior (expand/collapse with chevron, ARIA attributes)
- Consider default expanded/collapsed states for both sections
