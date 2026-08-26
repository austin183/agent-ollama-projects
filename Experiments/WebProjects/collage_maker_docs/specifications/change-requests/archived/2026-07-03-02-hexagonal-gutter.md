# Candidate for Removal
When the Hexagonal Layout is selected, the user has sliders for both Hex Spacing and Gutter, but the Gutter does not do anything for this layout.  We should remove it as a field when Hexagonal Layout is selected.

## Other Layouts Should Still Have Gutter Slider
We do not want to remove the Gutter Slider unless the user selects Hexagonal

# Open Closed Principle Opportunity
Each Layout could have a Layout Options definition so the Layout options do not interfere with each other.