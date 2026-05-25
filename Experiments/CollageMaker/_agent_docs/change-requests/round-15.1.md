# Cannot Zoom out to edges with 2 finger zoom gesture
## Reproduction
- Select a Panel to show the Image in the Panel Editor
- Drag the bottom right corner to the bottom right edge of the picture as far as possible
- Use 2 finger gesture over panel to zoom with that input

Notice the panel snaps back to a smaller portion of the image and will not zoom further out to where the corner could be stretched.  

The Zoom should be able expand to encompass as much of the image as there is image to zoom out to.  On the opposite side though, there should be a maximim zoom in of something like 2x.  Let's say we had an image, 400 x 300, and the panel was 100 x 100.  We should be able to zoom out to a 300 x 300 section of the image to go edge to edge.  Then we should be able to zoom into a section of 50 x 50 to get to a 2x zoom of the image.