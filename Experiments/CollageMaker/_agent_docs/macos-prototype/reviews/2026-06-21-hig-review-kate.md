# CollageMaker — Human Interface Guidelines Review

**Date:** 2026-06-21
**Reviewer:** Kate
**Scope:** macOS Human Interface Guidelines compliance across windows, commands/menus, settings, sidebars, context menus, accessibility, undo/redo, progress indicators, keyboard shortcuts, drag-and-drop, and alerts/feedback
**Prior review:** 2026-05-18 (archived) — this review reflects changes since that baseline

---

## Executive Summary

Since the May 18 review, **all four critical (P0) findings have been resolved**: Settings scene, `UndoManager` integration, accessibility annotations, and context menus are now implemented. The app has matured significantly — the codebase demonstrates a clear understanding of macOS conventions.

The remaining gaps are primarily polish-level: `reduceMotion` is declared but not wired to animations, minimum window size constraints are absent, and a handful of accessibility labels are missing from the Settings view. No findings rise to "Critical" severity.

| Category | Verdict | Severity |
|----------|---------|----------|
| **Windowing** | Good | Low |
| **Commands & Menus** | Good | Low |
| **Settings** | Good | Low |
| **Sidebars** | Good | Low |
| **Context Menus** | Good | Low |
| **Accessibility** | Partial | Medium |
| **Undo & Redo** | Good | Low |
| **Progress Indicators** | Partial | Low |
| **Keyboard Shortcuts** | Good | Low |
| **Drag and Drop** | Good | Low |
| **Alerts & Feedback** | Good | Low |

---

## 1. Windowing

### HIG Requirements
- Use `WindowGroup` for the primary app window
- Set minimum and maximum window sizes to prevent unusable layouts
- Use `Settings` scene for preferences
- Avoid critical information in bottom bars

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `WindowGroup` for main window | ✅ | `CollageMakerApp.swift:19` |
| `.defaultSize(width: 1200, height: 750)` | ✅ | `CollageMakerApp.swift:30` |
| `Settings` scene | ✅ | `CollageMakerApp.swift:36-38` |
| Minimum window size | ❌ Missing | N/A |
| `@SceneStorage` for per-window state | ❌ Missing | N/A |

### Findings

**No Minimum Window Size (Low)**

The detail column has `.frame(minWidth: 400, minHeight: 300)` at `ContentView.swift:30`, which constrains the editor/drawer area. However, there is no minimum on the `WindowGroup` itself. If the user shrinks the window below the sidebar's comfortable width, the sidebar columns become cramped. HIG recommends `.frame(minWidth:minHeight:)` on the content view or `.defaultSize()` paired with a minimum.

**Recommendation:** Add `.frame(minWidth: 750, minHeight: 500)` on the `NavigationSplitView` or on the `WindowGroup` to prevent unusable window sizes.

---

## 2. Commands & Menus

### HIG Requirements
- Use `.commands` at the scene level
- Use `CommandGroup` to insert/replace standard menu sections
- Use explicit modifier keys in `.keyboardShortcut()`
- Provide `SidebarCommands()` when using a sidebar

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `SidebarCommands()` | ✅ | `CollageMakerApp.swift:32` |
| `CommandGroup(replacing: .newItem)` | ✅ | `CollageCommands.swift:9` |
| `CommandGroup(replacing: .saveItem)` | ✅ | `CollageCommands.swift:20` |
| Explicit `.command` modifier | ✅ | `CollageCommands.swift:13,26,41-51` |
| Cmd+1/2/3 for layouts | ✅ | `CollageCommands.swift:41-51` |
| View menu | ✅ | `CollageCommands.swift:29-35` |

### Findings

**Excellent Improvement**

All prior findings from the May review are resolved:
- Keyboard shortcuts now use explicit `.command` modifiers
- Layout shortcuts (Cmd+1/2/3) are present
- The View menu includes "Show Saliency Overlay" with Cmd+Shift+H

**Minor: No Cmd+E for Export (Low)**

`Cmd+S` is used for "Export JPEG" (`CollageCommands.swift:26`). HIG notes that `Cmd+S` is the standard "Save" shortcut. For a non-document app that exports JPEGs rather than saving project files, `Cmd+E` (Export) may be more discoverable. This is a judgment call — keeping `Cmd+S` is acceptable if you plan to add a document format later.

---

## 3. Settings

### HIG Requirements
- Dedicated `Settings` scene
- Use `@AppStorage` for user preferences
- Tabbed layout for categories

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `Settings` scene | ✅ | `CollageMakerApp.swift:36-38` |
| `@AppStorage` usage | ✅ | `SettingsView.swift:54-60` |
| Tabbed layout | ✅ | `SettingsView.swift:77-91` |
| `.scenePadding()` | ✅ | `SettingsView.swift:91` |

### Findings

**Well-Implemented**

The Settings view has four tabs (General, Appearance, Text, Export) with proper `@AppStorage` bindings and `.formStyle(.grouped)`. The distinction between Settings defaults (for new sessions) and active collage state is clear from the doc comment at `SettingsView.swift:50-53`.

**Minor: Missing Accessibility Labels in Settings (Medium)**

Several controls in `SettingsView` lack accessibility labels:
- "Default Layout" picker (`SettingsView.swift:99-104`)
- Default Gutter slider (`SettingsView.swift:113`)
- Background Style picker (`SettingsView.swift:125-129`)
- Gradient angle slider (`SettingsView.swift:161`)
- Title `TextEditor` (`SettingsView.swift:180`)
- Font size slider (`SettingsView.swift:193`)
- Quality slider (`SettingsView.swift:248`)
- "Choose Folder" button (`SettingsView.swift:221`)

**Recommendation:** Add `.accessibilityLabel` and `.accessibilityValue` to all interactive controls in `SettingsView`, following the same pattern used in `ExportPanel` and `LayoutConfigSidebar`.

---

## 4. Sidebars

### HIG Requirements
- Use `NavigationSplitView` with sidebar/content/detail
- Show/hide available via View menu
- No more than two levels of hierarchy
- Avoid critical information at the bottom

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `NavigationSplitView` | ✅ | `ContentView.swift:19` |
| `.formStyle(.grouped)` | ✅ | `ContentView.swift:83` |
| `SidebarCommands()` | ✅ | `CollageMakerApp.swift:32` |
| Search field at top | ✅ | `ImageLibrarySidebar.swift:14-28` |
| SF Symbols for icons | ✅ | Throughout |
| `backgroundExtensionEffect()` | ❌ Missing | Sidebar |
| Two-level hierarchy | ✅ | Flat image list |
| Status at bottom | ⚠️ Present | `StatusSidebar.swift` |

### Findings

**Status at Bottom — Acceptable (Low)**

The "Status" section (`StatusSidebar.swift:7-27`) shows processing state and readiness. The prior review flagged this as a concern, but the current content (processing spinner, "Ready" indicator) is non-critical status information. The "Notice" section about unused images (`StatusSidebar.swift:30-38`) uses `info.circle` instead of the prior `exclamationmark.triangle`, which is the correct choice per HIG's caution symbol guidance.

**Recommendation:**
2. Current status placement is acceptable as-is

---

## 5. Context Menus

### HIG Requirements
- Use `.contextMenu` for right-click/secondary-click actions
- Keep menus small (3-5 items max)
- Support consistently across applicable elements
- Use `.role(.destructive)` for destructive items

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Canvas panel context menu | ✅ | `CollageEditorView.swift:308-318` |
| Sidebar image context menu | ✅ | `ImageLibrarySidebar.swift:79-83` |
| `.role(.destructive)` on Remove | ✅ | Both locations |
| Small menu size | ✅ | 2-3 items each |

### Findings

**Well-Implemented**

Canvas panels offer "Reset Crop" and "Remove Image" (destructive). Sidebar images offer "Remove" (destructive). Both menus are small and contextually relevant.

**Minor: Could Add "Replace Image" (Low)**

The HIG reference suggests "Replace Image" as a canvas panel context menu action. This would let users swap an image without removing and re-adding. Not critical, but a useful convenience.

---

## 6. Accessibility

### HIG Requirements
- `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue` on all interactive elements
- Meet WCAG Level AA contrast ratios
- Convey information with more than color alone
- Support Full Keyboard Access
- Respect "Reduce Motion" setting

### Current State

| Requirement | Status |
|-------------|--------|
| `.accessibilityLabel` on buttons | ✅ Most |
| `.accessibilityValue` on sliders | ✅ Most |
| `.accessibilityHint` on key actions | ✅ Export, Add Images |
| `.accessibilityAddTraits(.isSelected)` | ✅ `CollageEditorView.swift:307` |
| `.accessibilityAddTraits(.isHeader)` | ✅ `PanelCropEditor.swift:37` |
| System-defined colors | ✅ Throughout |
| Non-color state indicators | ✅ White stroke for selected panels |
| `reduceMotion` declared | ✅ `CollageEditorView.swift:13` |
| `reduceMotion` used in animations | ❌ Not wired |
| Settings view labels | ❌ Missing |

### Findings

**Significant Progress, Minor Gaps Remain (Medium)**

Compared to the May review (zero accessibility annotations), the app now has 62 accessibility modifier calls across 8 files. Export panel, layout sidebar, image library, crop editor, and status sidebar are all annotated.

**`reduceMotion` Declared But Unused (Medium)**

`CollageEditorView.swift:13` declares `@Environment(\.accessibilityReduceMotion) private var reduceMotion` but never references it. The only animation in the codebase is `.transition(.opacity)` in `ExportPanel.swift:249`. This transition should be conditional:

```swift
.transition(reduceMotion ? .identity : .opacity)
```

**Settings View Missing Labels (Medium)**

As noted in section 3, `SettingsView` has no accessibility annotations on its controls.

**Panel Accessibility Labels Could Be More Descriptive (Low)**

`CollageEditorView.swift:306` uses `.accessibilityLabel("Image panel")` for all panels. HIG recommends specificity: "Panel 1, contains photo.jpg" would help VoiceOver users distinguish panels.

**Recommendation:**
1. Wire `reduceMotion` to the `.transition(.opacity)` in `ExportPanel`
2. Add accessibility labels to all `SettingsView` controls
3. Consider making panel labels include the image filename or panel index

---

## 7. Undo & Redo

### HIG Requirements
- Integrate `NSUndoManager` for undoable actions
- Use descriptive action names
- Batch related continuous adjustments
- Place undo/redo in Edit menu (automatic with `NSUndoManager`)

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `UndoManager` instance | ✅ | `CollageViewModel.swift:34` |
| `levelsOfUndo = 60` | ✅ | `CollageViewModel.swift:435` |
| Descriptive action names | ✅ | "Remove Image", "Change Layout", etc. |
| Gesture batching | ✅ | `beginGestureUndo()`/`endGestureUndo()` |
| Undo on image removal | ✅ | `CollageViewModel.swift:596-602` |
| Undo on image reorder | ✅ | `CollageViewModel.swift:605-612` |
| Undo on layout change | ✅ | `CollageViewModel.swift:148-153` |
| Undo on crop reset | ✅ | `CollageViewModel.swift:698-709` |
| Undo on clear all | ✅ | `CollageViewModel.swift:561-593` |
| Undo on title edits | ✅ | `CollageViewModel.swift:48-52` |
| Undo on background changes | ✅ | Multiple setters |

### Findings

**Excellent Implementation**

The undo system is comprehensive. Every mutating action has an undo registration with a descriptive name. Gesture-based crop adjustments are properly batched with `beginUndoGrouping()`/`endUndoGrouping()`. The `registerUndo` helper at `CollageViewModel.swift:392-399` provides a clean pattern.

**Minor: `UndoManager` vs `NSUndoManager` (Low)**

The code uses `UndoManager()` (Foundation's type alias). This is correct — it automatically integrates with the Edit menu.

---

## 8. Progress Indicators

### HIG Requirements
- Use determinate progress when duration is known
- Use indeterminate progress when duration is unknown
- Be specific with labels
- Include Cancel when interrupting has no negative side effects

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Indeterminate progress (saliency) | ✅ | `StatusSidebar.swift:10-11` |
| Specific label with image count | ✅ | `StatusSidebar.swift:14-15` |
| Export progress spinner | ✅ | `ExportPanel.swift:226-228` |
| Export progress label | ✅ | `ExportPanel.swift:231` |
| Cancel during export | ❌ Missing | N/A |
| Determinate export progress | ❌ Missing | N/A |

### Findings

**Good Improvement (Low)**

The "Analyzing N image(s)..." label (`StatusSidebar.swift:15`) addresses the prior "generic Processing..." finding. The export button now shows a spinner and "Exporting collage..." text.

**No Cancel During Export (Low)**

Once export starts, there is no way for the user to cancel. The `ExportManager` supports cancellation internally (`exportTask?.cancel()`), but there is no UI affordance. HIG recommends a Cancel button when "interrupting has no negative side effects."

**Recommendation:** Add a Cancel button or change the export button to "Cancel" while exporting.

---

## 9. Keyboard Shortcuts

### HIG Requirements
- Use standard shortcuts (Cmd+Z undo, Cmd+S save, Cmd+O open, etc.)
- Define custom shortcuts only for frequently used actions
- List modifiers in correct order: Control, Option, Shift, Command
- Avoid Control modifier

### Current State

| Shortcut | Action | Status |
|----------|--------|--------|
| Cmd+O | Add Images | ✅ `CollageCommands.swift:13` |
| Cmd+S | Export JPEG | ✅ `CollageCommands.swift:26` |
| Cmd+1/2/3 | Layout switch | ✅ `CollageCommands.swift:41-51` |
| Cmd+Shift+H | Toggle Saliency | ✅ `CollageCommands.swift:34` |
| Cmd+Z / Shift+Cmd+Z | Undo/Redo | ✅ (automatic) |
| Cmd+Option+0 | Toggle Sidebar | ✅ (via `SidebarCommands()`) |
| Cmd+, | Settings | ✅ (automatic) |

### Findings

**Excellent — All Prior Findings Resolved**

All keyboard shortcuts use explicit `.command` modifiers. Layout shortcuts are present. No shortcuts misuse the Control modifier.

**Minor: No Delete Key Support (Low)**

When a panel is selected on the canvas, pressing Delete/Backspace does not remove the image. HIG supports "Delete/Backspace: Remove selected panel's image" as a canvas editing shortcut.

---

## 10. Drag and Drop

### HIG Requirements
- Support drag and drop throughout the app
- Offer alternative ways to accomplish drag-and-drop actions
- Provide visual feedback during drag operations
- Use appropriate pointer appearances

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Finder to sidebar drop | ✅ | `ContentView.swift:99-104` |
| Drop overlay feedback | ✅ | `ContentView.swift:84-97` |
| Canvas panel-to-panel drag | ✅ | `CollageEditorView.swift:149-188` |
| Drag source/target highlights | ✅ | `DropPreviewView.swift` |
| Context menu alternative | ✅ | Canvas panel context menus |
| Sidebar reordering drag | ✅ | `ImageLibrarySidebar.swift:89-91` |

### Findings

**Well-Implemented**

Drag-and-drop is comprehensive: external drops onto the sidebar, panel-to-panel reordering on the canvas, and sidebar image reordering with `.onMove`. The `DropPreviewView` provides cyan/green stroke highlights for source/target panels and a thumbnail cursor during canvas drags.

**Color-Only Drag Feedback (Low)**

The drag feedback uses cyan (source) and green (target) strokes (`DropPreviewView.swift:18,29`). HIG recommends conveying information with more than color alone. Consider adding a dashed vs solid stroke distinction, or a label, for color-blind users.

---

## 11. Alerts & Feedback

### HIG Requirements
- Use alerts for uncommon destructive actions
- Avoid alerts for common, undoable actions
- Use specific titles, never "Error"
- Always use "Cancel" for cancel buttons
- Use `.role(.destructive)` for destructive buttons

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Clear All confirmation | ✅ | `ContentView.swift:63-70` |
| `.role(.destructive)` on Clear All | ✅ | `ContentView.swift:64` |
| `.role(.cancel)` on Cancel | ✅ | `ContentView.swift:67` |
| Export error display | ✅ | `ExportPanel.swift:252-257` |
| Export success feedback | ✅ | `ExportPanel.swift:240-250` |
| Success auto-dismiss | ✅ | `ExportPanel.swift:260-265` |
| Warning triangle replaced | ✅ | `StatusSidebar.swift:30-38` |

### Findings

**All Prior Findings Resolved**

The "Clear All" confirmation alert is properly implemented with destructive/cancel roles. Export success shows a green checkmark with auto-dismiss after 3 seconds. Export errors display as red text. The warning triangle for unused images has been replaced with `info.circle`.

**Minor: Export Errors Are Inline, Not Alerts (Low)**

File system errors (disk full, permission denied) are shown as red text in the export panel. HIG recommends `.alert()` for errors that need user attention. For minor errors this is acceptable, but disk-full errors benefit from a modal alert.

---

## Summary of Findings

### Important (Fix Before Release)

| # | Category | Issue | Impact |
|---|----------|-------|--------|
| 1 | Accessibility | `reduceMotion` declared but not wired to animations | Users with motion sensitivity get no relief |
| 2 | Accessibility | Settings view has no accessibility labels | VoiceOver users cannot navigate Settings |

### Polish (Nice to Have)

| # | Category | Issue | Impact |
|---|----------|-------|--------|
| 3 | Windowing | No minimum window size | Sidebar/editor can become unusable |
| 4 | Accessibility | Panel labels not specific enough | VoiceOver cannot distinguish panels |
| 5 | Progress | No Cancel button during export | User must wait for export to complete |
| 6 | Drag & Drop | Color-only drag feedback (cyan/green) | Color-blind users may confuse source/target |
| 7 | Keyboard | No Delete key to remove selected panel | Missing expected keyboard interaction |
| 8 | Sidebars | Missing `backgroundExtensionEffect()` | Non-native sidebar appearance |
| 9 | Context Menus | No "Replace Image" on canvas panels | Missing convenient action |
| 10 | Alerts | Export errors inline, not modal | Disk-full errors may be overlooked |
| 11 | Commands | Cmd+S for export vs Cmd+E | Minor convention question |

---

## Recommended Implementation Priority

| Priority | Category | Work |
|----------|----------|------|
| P1 | Accessibility | Wire `reduceMotion` to `ExportPanel` transition; add labels to `SettingsView` controls |
| P2 | Windowing | Add `.frame(minWidth: 750, minHeight: 500)` to `NavigationSplitView` |
| P2 | Accessibility | Make panel labels include image name or panel index |
| P2 | Progress | Add Cancel button during export |
| P3 | Drag & Drop | Add non-color distinction to drag feedback (dashed vs solid) |
| P3 | Keyboard | Add Delete key handler for selected panel |
| P3 | Sidebars | Add `.backgroundExtensionEffect()` to sidebar |
| P3 | Context Menus | Add "Replace Image" to canvas panel context menu |

---

## Comparison with Prior Review (2026-05-18)

| Prior Finding | Status |
|---------------|--------|
| P0: No `NSUndoManager` | ✅ Resolved — full implementation with batching |
| P0: No Settings scene | ✅ Resolved — 4-tab Settings with `@AppStorage` |
| P1: No accessibility annotations | ✅ Resolved — 62 modifiers across 8 files |
| P1: No context menus | ✅ Resolved — canvas panels and sidebar |
| P1: Keyboard shortcuts missing explicit modifiers | ✅ Resolved — all shortcuts explicit |
| P1: No layout switching shortcuts | ✅ Resolved — Cmd+1/2/3 |
| P2: No confirmation for "Clear All" | ✅ Resolved — alert with destructive/cancel |
| P2: Generic "Processing..." label | ✅ Resolved — "Analyzing N image(s)..." |
| P2: No export success feedback | ✅ Resolved — green checkmark with auto-dismiss |
| P3: Warning triangle overuse | ✅ Resolved — replaced with `info.circle` |
| P3: Missing `backgroundExtensionEffect()` | ⚠️ Still missing |
| P3: No `@SceneStorage` | ⚠️ Still missing |
| P3: No minimum window size | ⚠️ Still missing |

**Net improvement: 11 of 14 prior findings resolved. 3 carry forward at P3.**
