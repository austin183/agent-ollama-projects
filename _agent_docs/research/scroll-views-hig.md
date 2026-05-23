# Apple HIG — Scroll Views Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/scroll-views

## Scroll Indicator Behavior

The scroll view itself has no appearance, but it can display a translucent scroll indicator that typically appears after people begin scrolling the view's content. Although the appearance and behavior of scroll indicators can vary per platform, all indicators provide visual feedback about the scroll position and the proportion of visible content.

### Key Guidelines

- **Support default scrolling gestures and keyboard shortcuts.** People are accustomed to the systemwide scrolling behavior and expect it to work everywhere. If you build custom scrolling for a view, make sure your scroll indicators use the elastic behavior that people expect.

- **Make it apparent when content is scrollable.** Because scroll indicators aren't always visible, it can be helpful to make it obvious when content extends beyond the view. For example, displaying partial content at the edge of a view indicates that there's more content in that direction.

- **Avoid putting a scroll view inside another scroll view with the same orientation.** Nesting scroll views that have the same orientation can create an unpredictable interface that's difficult to control. It's alright to place a horizontal scroll view inside a vertical scroll view (or vice versa).

- **Consider supporting page-by-page scrolling** if it makes sense for your content. In some situations, people appreciate scrolling by a fixed amount of content per interaction instead of scrolling continuously.

- **In some cases, scroll automatically to help people find their place.** Although people initiate almost all scrolling, automatic scrolling can be helpful when relevant content is no longer in view.

### Automatic Scrolling Triggers

- Your app performs an operation that selects content or places the insertion point in an area that's currently hidden.
- People start entering information in a location that's not currently visible.
- The pointer moves past the edge of the view while people are making a selection.
- People select something and scroll to a new location before acting on the selection.

In all cases, automatically scroll the content only as much as necessary to help people retain context.

### Zoom

If you support zoom, set appropriate maximum and minimum scale values. For example, zooming in on text until a single character fills the screen doesn't make sense in most situations.

### Scroll Edge Effects

In iOS, iPadOS, and macOS, a scroll edge effect is a variable blur that provides a transition between a content area and an area with Liquid Glass controls, such as toolbars. The system applies a scroll edge effect automatically when a pinned element overlaps with scrolling content.

Two styles:
- **Soft edge effect** — Use in most cases, especially in iOS and iPadOS, for a subtle transition that works well for toolbars and interactive elements.
- **Hard edge effect** — Use primarily in macOS for a stronger, more opaque boundary that's ideal for interactive text, backless controls, or pinned table headers.

Only use a scroll edge effect when a scroll view is adjacent to floating interface elements. They aren't decorative — they exist to clarify where controls and content meet.

### macOS Scroll Bars

In macOS, a scroll indicator is commonly called a scroll bar. If necessary, use small or mini scroll bars in a panel when space is tight.

## Relevance to CollageMaker Batch 4

The HIG guidance reinforces that:
1. **Two-finger scroll is the macOS convention** — "Support default scrolling gestures" means using `scrollWheel` events is the right approach for canvas panning.
2. **Elastic behavior is expected** — Any custom scroll behavior should feel natural with momentum and bounce.
3. **Nested same-orientation scroll views are problematic** — The canvas overlay approach with `ScrollPanView` avoids nesting scroll views.
4. **Custom scrolling must feel system-native** — The `ScrollPanView` NSViewRepresentable approach captures native `NSEvent` events, preserving system feel.
