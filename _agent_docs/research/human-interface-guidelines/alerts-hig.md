# Apple HIG — Alerts Guidelines

## Source
https://developer.apple.com/design/human-interface-guidelines/alerts

## Overview

An alert is a modal view that tells people about a problem, warns when an action might destroy data, or gives an opportunity to confirm an important action. Alerts look different across platforms but share the same purpose.

## Best Practices

- **Use alerts sparingly.** Alerts interrupt the current task. Each one should offer only essential information and useful actions.

- **Avoid using alerts merely for information.** If only communicating information, find an alternative within the relevant context. For example, display an indicator people can choose to learn more.

- **Avoid alerts for common, undoable actions.** Don't alert about data loss for actions people commonly perform with undo available (e.g., deleting an email). Only alert for uncommon destructive actions that can't be undone.

- **Avoid showing alerts at app startup.** If informing about new information, make it discoverable. For startup problems, show cached/placeholder data with a nonintrusive label.

## Anatomy and Content

Alerts display: title, optional informative text, and up to three buttons. macOS alerts can additionally include:
- An icon (app icon by default, or custom)
- An accessory view for additional information
- A suppression checkbox for repeating alerts
- A Help button

### Writing Alert Text

- **Be direct with neutral, approachable tone.** Avoid being oblique, accusatory, or masking severity.

- **Title**: Clearly and succinctly describe the situation. Be complete and specific without being verbose. Describe what happened, the context, and why. Avoid uninformative titles like "Error" or "Error 329347 occurred." Keep to two lines max. Use sentence-style capitalization for complete sentences; title-style for fragments.

- **Informative text**: Include only if it adds value. Keep short, using complete sentences.

- **Avoid explaining buttons.** If alert text and button titles are clear, no explanation needed.

## Buttons

- **Succinct, logical titles.** One or two words describing the result. Prefer verbs: "View All," "Reply," "Ignore." Use "OK" only for purely informational alerts. Always use "Cancel" for cancel buttons.

- **Avoid "OK" as default unless purely informational.** "OK" can be unclear. Use specific titles like "Erase," "Convert," "Clear," or "Delete."

- **Button placement**: Most likely button on trailing side (right) in a row. Cancel on leading side (left). Default button on trailing side.

- **Destructive style**: Identify buttons performing destructive actions people didn't deliberately choose. Don't apply destructive style when the button performs the person's original intent.

- **Always include Cancel with destructive actions.** Never make Cancel the default button.

- **Alternative cancel methods**: Support Escape (Esc) or Command+Period (.) to dismiss alerts.

## macOS-Specific Considerations

- macOS automatically displays app icon in alerts
- Can supply alternative icon or symbol
- Configure repeating alerts with suppression checkbox
- Can append custom accessory view
- Can include Help button to open help documentation

### Caution Symbols

Use caution symbols (e.g., `exclamationmark.triangle`) sparingly. Only when extra attention is really needed, such as confirming actions that might result in unexpected data loss. Don't use for tasks whose purpose is to overwrite or remove data (e.g., save, empty trash).

## Relevance to CollageMaker

Alerts should be used strategically in the collage maker:

1. **"Clear All Images" confirmation**: This is an uncommon destructive action. Should show alert with specific button title ("Clear All" not "OK"), Cancel button, and destructive style on the action button.

2. **Export errors**: If export fails, show alert with specific error message. Not just "Error" but "Couldn't save collage: Disk full."

3. **Undoable actions should NOT alert**: Removing a single image, resetting a crop, or changing layout should not require alerts since they're common and undoable.

4. **Startup issues should NOT alert**: If no images are loaded, show the empty state instead of an alert.

Key implementation notes:
- Use SwiftUI `.alert(isPresented:)` modifier
- Always use specific button titles, not "OK" for actions
- Destructive buttons use `.role(.destructive)`
- Cancel button should not be the default
- Support Escape to dismiss
- Never alert for undoable actions
