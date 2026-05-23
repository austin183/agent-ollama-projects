# Apple HIG — Feedback Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/feedback

## Overview

Clear, consistent feedback makes an app feel intuitive and encourages exploration. Feedback communicates:
- Current status of something
- Success or failure of an important task
- Warnings about actions with negative consequences
- Opportunities to correct mistakes

Effective feedback matches the significance of information to its delivery method.

## Best Practices

- **Make all feedback accessible.** Use multiple channels: color, text, sound, and haptics. People can receive feedback whether they silence their device, look away, or use VoiceOver.

- **Integrate status feedback into the interface.** When status feedback is near the items it describes, people get information without leaving context. For example, displaying update time and unread count in a toolbar.

- **Use alerts for critical, actionable information only.** Alerts disrupt context — match importance to interruption level. Alerts lose impact when overused.

- **Warn for unexpected, irreversible data loss.** Don't warn when data loss is the expected result of an action (e.g., throwing away a file).

- **Confirm significant completed actions.** Reserve confirmation for sufficiently important activities. People expect actions to succeed — they only need to know when they don't.

- **Show when commands can't be carried out and why.** For example, "Can't provide directions to and from the same location."

## watchOS-Specific

- Avoid indeterminate progress indicators on watchOS. Animated indicators make people think they need to keep watching. Instead, reassure they'll receive a notification when complete.

## Relevance to CollageMaker

Feedback strategies for the collage maker:

1. **Status feedback in sidebar**: Show processing status ("Analyzing 3 images..."), image count, and export readiness in the sidebar status area. This is non-intrusive and contextually relevant.

2. **Export completion feedback**: After successful export, briefly show "Collage saved to [location]" in the status area. No alert needed for expected success.

3. **Export failure feedback**: Use an alert with specific error message for export failures. This is unexpected and actionable (retry, choose different location).

4. **Saliency analysis feedback**: Show indeterminate progress during analysis. Switch to determinate if tracking image count. No need for completion confirmation — the updated canvas is the confirmation.

5. **Drag-and-drop feedback**: Visual feedback during drag operations (highlight drop targets, show drag images). Already covered in drag-and-drop HIG.

6. **No feedback for undoable actions**: Common actions like removing images, changing layout, or adjusting crops don't need confirmation — they're undoable.

Key implementation notes:
- Use sidebar status text for passive feedback
- Use `.overlay()` for inline success messages
- Reserve `.alert()` for errors and unexpected conditions
- Keep success messages brief and auto-dismissing
- Never block the user workflow with informational alerts
