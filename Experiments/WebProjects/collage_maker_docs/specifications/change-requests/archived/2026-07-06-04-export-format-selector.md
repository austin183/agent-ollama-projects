# Export Format Selector

The Export button currently exports only as JPEG. The infrastructure already supports both JPEG and PNG via the `ExportManager` registry.

Add a format selector (dropdown or toggle) next to the Export button so the user can choose between JPEG and PNG before exporting.

- Default should remain JPEG (current behavior)
- JPEG should keep the existing quality slider
- PNG is lossless, so the quality slider should be hidden or disabled when PNG is selected
