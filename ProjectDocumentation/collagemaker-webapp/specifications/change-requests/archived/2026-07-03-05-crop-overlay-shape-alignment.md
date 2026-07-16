# Current Crop Overlay Behavior
For all layouts, the Crop Overlay displays as a rectangle, even though the preview image is not always rectangular.

# Diagonal Slices Layout
Depending on the Slice Angle and the panels position, the crop overlay will need to somtimes be pentagonal, triangular, or like a parallelogram.  We need to match the crop overlay to the panel's shape so the user experience feels natural.

# Hexagonal Layout
## Replace Gutter Slider with Panel Size Slider
Here every shape will be Hexagonal.  Currently, the Hexagonal Layout has Hex Spacing and Gutter Slider Options, and sometimes the Hexagonal panel sizes leave alot of canvas real estate to fill in.  Can we change the Gutter Slider option to a Hexagon Size slider, with minimum of what it has be default, and maximum of 200% of that?  Even if some of the hexagons fall off the edges, the user should be able to see that and slide back if they desire.

## Panel Switching by Drag and Drop
Since the number of images affects the number of Hexagons that appear in the Hexagon, the user needs to be able to move a panel to any hexagonal grid element as opposed to just swapping positions with another panel.