# Need to Use Both Background Image and Configured Background Color
## Reproduction Steps
- Select Background Style Gradient and Set a Gradient for the background of any two colors
- Select Backgroud Image
- Set Image Opacity to less than 100%
  - Notice the background color for the translucent image is White 
- Repeat with any other color set and switch to Image to see the background color changes to white

## Desired Outcome
The chosen background color configuration for Solid and Gradient should still be configured for the background of the Image

# UX Design Option for Better Clarity
We could separate the Background Image from the `Solid|Gradient|Image` selection and have it be an independent configuration panel so the user can always set them both.