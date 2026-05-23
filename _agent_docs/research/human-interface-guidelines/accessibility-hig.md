# Apple HIG — Accessibility Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/accessibility

## Overview

An accessible interface is:
- **Intuitive**: Uses familiar, consistent interactions
- **Perceivable**: Doesn't rely on any single method to convey information
- **Adaptable**: Adapts to how people want to use their device

Use Accessibility Inspector to highlight issues and understand how your app represents itself to assistive technologies.

## Vision

### Text Size
- Support text enlargement by at least 200%
- Adopt Dynamic Type for systemwide font size adjustment
- Thicker font weights are easier to read at smaller sizes
- Increase font size when using thin weights

### Color Contrast
- Meet WCAG Level AA minimum contrast ratios:
  - Up to 17pt text: 4.5:1 minimum contrast ratio
  - 18pt+ text: 3:1 minimum contrast ratio
- Provide higher contrast when "Increase Contrast" system setting is on
- Check contrast in both light and dark appearances

### Color Usage
- **Prefer system-defined colors** — they have accessible variants that adapt to user preferences
- **Convey information with more than color alone** — provide visual indicators (shapes, icons) in addition to color for state changes and functional differences
- Red-green and blue-orange pairings are particularly problematic for color blind users

### VoiceOver
- Describe interface and content for VoiceOver screen reader
- Label all interactive elements with descriptive accessibility labels

## Hearing

- Support text-based alternatives for audio/video: captions, subtitles, audio descriptions, transcripts
- Use haptics in addition to audio cues
- Augment audio cues with visual cues, especially for off-screen content

## Mobility

### Control Sizes
- macOS: 60x60pt default, 28x28pt minimum control size
- Include sufficient padding between elements (12pt with bezel, 24pt without)

### Gestures
- Support simple gestures for common interactions
- Offer alternatives to gestures (onscreen buttons)
- Avoid custom multifinger and multihand gestures

### Keyboard Access
- Support Full Keyboard Access for keyboard-only navigation
- Support system-defined keyboard shortcuts
- Integrate with Voice Control for verbal commands

## Cognitive

- Keep actions simple and intuitive
- Minimize time-boxed interface elements (auto-dismissing views)
- Let people control audio/video playback (no autoplay without controls)
- Allow opting out of flashing lights
- Be cautious with fast-moving and blinking animations
- Respond to "Reduce Motion" setting: reduce automatic/repetitive animations, tighten springs, track with gestures, avoid z-axis animations, replace transitions with fades

## Relevance to CollageMaker

Accessibility improvements to prioritize:

1. **Accessibility labels**: All interactive elements need labels:
   - Panel selection: "Panel 1, contains [image name]"
   - Layout picker: "Layout style: Uniform"
   - Gutter slider: "Gutter spacing: 5 points"
   - Color pickers: "Background color", "Title color"
   - Export button: "Export collage as JPEG"

2. **Color contrast**: Audit all UI text and controls against WCAG AA. The dark canvas background needs sufficient contrast with any overlaid text.

3. **Non-color indicators**: Don't rely solely on color for:
   - Selected panel highlight (white border is good, already non-color)
   - Drag-and-drop target indication (add visual indicator beyond color change)
   - Error states (add icon, not just red text)

4. **System colors**: Use system-defined colors (`.red`, `.blue`, etc.) instead of hardcoded `Color(red:green:blue:)` for UI elements.

5. **Keyboard navigation**: Ensure all inspector controls are keyboard-navigable. Slider, picker, and button controls should respond to Tab/arrow keys.

6. **Reduce motion**: Respect the Reduce Motion setting for any animations (panel transitions, export progress animations).

Key implementation notes:
- Use `.accessibilityLabel()` for descriptive labels
- Use `.accessibilityHint()` for additional context
- Use `.accessibilityValue()` for dynamic values (slider positions)
- Use `.accessibilityAddTraits()` for state information
- Test with VoiceOver enabled
- Use Accessibility Inspector for auditing
