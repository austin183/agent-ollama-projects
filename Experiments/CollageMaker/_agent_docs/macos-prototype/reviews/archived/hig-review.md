# CollageMaker — Human Interface Guidelines Review

**Date:** 2026-05-18
**Scope:** macOS Human Interface Guidelines compliance across accessibility, windows, commands/menus, settings, sidebars, context menus, progress indicators, undo/redo, keyboard shortcuts, and alerts/feedback

---

## Executive Summary

CollageMaker has a solid structural foundation with a three-column `NavigationSplitView`, proper use of `SidebarCommands`, drag-and-drop image import, and gesture-based crop editing. The app follows modern SwiftUI patterns (`@Observable`, `@Bindable`, `Task.detached` for background work).

However, **significant HIG gaps remain** that affect discoverability, accessibility, user control, and platform consistency. The most impactful issues are the missing Settings scene, absent undo/redo system, no context menus on canvas panels, and lack of accessibility annotations throughout.

| Category | Verdict | Severity |
|----------|---------|----------|
| **Windowing** | Partial | Medium |
| **Commands & Menus** | Partial | Medium |
| **Settings** | Missing | High |
| **Sidebars** | Partial | Medium |
| **Split Views & Inspectors** | Good | Low |
| **Context Menus** | Missing | High |
| **Accessibility** | Missing | High |
| **Undo & Redo** | Missing | High |
| **Progress Indicators** | Partial | Medium |
| **Keyboard Shortcuts** | Partial | Medium |
| **Alerts & Feedback** | Partial | Medium |

---

## 1. Windowing

### HIG Requirements
- Use `WindowGroup` for the primary app window
- Use `Settings` scene for preferences
- Use `@SceneStorage` for per-window ephemeral state
- Provide appropriate `.defaultSize()`

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `WindowGroup` for main window | ✅ | `CollageMakerApp.swift:18` |
| `.defaultSize(width: 1200, height: 750)` | ✅ | `CollageMakerApp.swift:21` |
| `Settings` scene | ❌ Missing | N/A |
| `@SceneStorage` for per-window state | ❌ Missing | N/A |

### Findings

**Missing Settings Scene (High)**

The app has no `Settings` scene. All preferences are stored via manual `UserDefaults` reads/writes in `didSet` hooks inside `CollageViewModel`. HIG requires a dedicated `.settings` scene:

```swift
// Missing from CollageMakerApp.swift:
Settings {
    SettingsView()
}
```

Users expect `CollageMaker` in the menu bar (next to the Apple logo) to have a Settings entry. Without it, there is no standard path to app preferences.

**No `@SceneStorage` (Medium)**

Sidebar expansion state, selection state, and any per-window ephemeral state are not persisted across app launches. If multi-window support is added in the future, all windows would share the same `CollageViewModel` state.

### Recommendation

Add a `Settings` scene with a `TabView` containing at least:
- **General tab:** Default layout style, export quality
- **Appearance tab:** (Future) Theme, accent color

---

## 2. Commands & Menus

### HIG Requirements
- Add `.commands` at the scene level
- Use `CommandGroup` to insert/replace standard menu sections
- Use `CommandMenu` for app-specific actions
- Include `SidebarCommands()` when using a sidebar
- Pair important commands with keyboard shortcuts and visible toolbar affordances

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `SidebarCommands()` | ✅ | `CollageMakerApp.swift:23` |
| Custom `CollageCommands` | ✅ | `CollageCommands.swift` |
| "Add Images..." command | ✅ | `CollageCommands.swift:8` |
| "Export JPEG..." command | ✅ | `CollageCommands.swift:19` |
| Layout menu | ✅ | `CollageCommands.swift:27` |
| Keyboard shortcuts on commands | ⚠️ Partial | `CollageCommands.swift:11,24` |
| Edit menu (Undo/Redo) | ❌ Missing | N/A |
| View menu (Toggle Sidebar) | ❌ Missing | N/A |

### Findings

**Keyboard Shortcuts Incomplete (Medium)**

`CollageCommands.swift` defines keyboard shortcuts for "Add Images" (`Cmd+O`) and "Export JPEG" (`Cmd+S`), but these are bare `.keyboardShortcut("o")` without modifier specification. HIG recommends explicit modifiers:

```swift
.keyboardShortcut("o", modifiers: .command)
```

Additionally, the Layout menu buttons have no keyboard shortcuts. HIG suggests custom shortcuts for frequently used actions:

| Shortcut | Action | Status |
|----------|--------|--------|
| Cmd+1 | Uniform Layout | Missing |
| Cmd+2 | Hero Layout | Missing |
| Cmd+3 | Mosaic Layout | Missing |
| Cmd+E | Export | Duplicate (Cmd+S already used) |
| Cmd+Option+L | Add Images | Missing (Cmd+O used instead) |

**No Edit Menu (High)**

The Edit menu is the standard macOS location for Undo/Redo. CollageMaker has no `NSUndoManager` integration at all (see section 7). This means users cannot undo layout changes, image removals, crop adjustments, or title edits.

**No View Menu (Medium)**

HIG requires a "Toggle Sidebar" command (Cmd+Option+0) for apps with sidebars. `SidebarCommands()` provides this, but a custom View menu with additional toggle options (e.g., toggle inspector detail panel) would improve discoverability.

### Recommendation

1. Add explicit `.command` modifier to all `.keyboardShortcut()` calls
2. Add keyboard shortcuts to Layout menu buttons (Cmd+1/2/3)
3. Consider `Cmd+E` for export (more discoverable than Cmd+S for a non-document app)
4. Implement NSUndoManager for the Edit menu (see section 7)

---

## 3. Settings

### HIG Requirements
- Declare a dedicated `Settings` scene
- Use `@AppStorage` for user preferences
- Prefer tabs, sections, or split layout over deep push navigation
- Use `SettingsLink` or `OpenSettingsAction` for in-app entry points

### Current State

| Requirement | Status |
|-------------|--------|
| `Settings` scene | ❌ Missing |
| `@AppStorage` usage | ❌ Missing — manual `UserDefaults` only |
| `SettingsLink` / `OpenSettingsAction` | ❌ Missing |
| Tabbed settings layout | ❌ Missing |

### Findings

**No Settings Entry Point (High)**

There is no way for users to access app settings from the UI. The only entry point is through the app's menu bar (which lacks a Settings entry). HIG states: "never bury settings inside the main content flow."

**Manual UserDefaults Instead of `@AppStorage` (Medium)**

All settings use `UserDefaults.standard` with `didSet` hooks. `@AppStorage` would:
- Reduce boilerplate code
- Provide automatic two-way binding
- Enable Settings scene integration
- Handle type safety automatically

Current persisted keys that should migrate:
- `layoutStyle`, `gutter`, `backgroundColor`, `exportQuality`, `titleAttrString`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundOpacity`, `customImageOrder`, `titleStyle`

### Recommendation

1. Add `Settings` scene to `CollageMakerApp.swift`
2. Migrate `@Observable` properties with `didSet` UserDefaults persistence to `@AppStorage` where applicable
3. Keep complex types (NSColor, NSAttributedString) in `didSet` hooks — `@AppStorage` only supports `RawRepresentable` types

---

## 4. Sidebars

### HIG Requirements
- Use `NavigationSplitView` with sidebar/content/detail
- Sidebar should use Liquid Glass appearance
- Show/hide available via View menu
- No more than two levels of hierarchy
- Use SF Symbols for icons
- Use accent color for sidebar icons
- Provide succinct, descriptive labels

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `NavigationSplitView` | ✅ | `ContentView.swift:29` |
| Three-column layout | ✅ | sidebar / content / detail |
| `SidebarCommands()` | ✅ | `CollageMakerApp.swift:23` |
| SF Symbols for icons | ✅ | Throughout sidebar |
| Search field in sidebar | ✅ | `ContentView.swift:40-54` |
| `.formStyle(.grouped)` | ✅ | `ContentView.swift:171` |
| `backgroundExtensionEffect()` | ❌ Missing | Sidebar |
| Two-level hierarchy limit | ⚠️ Borderline | Sidebar has 3 sections |
| Status text at bottom | ✅ | `ContentView.swift:142-158` |

### Findings

**Missing `backgroundExtensionEffect()` (Low)**

HIG recommends `backgroundExtensionEffect()` for the sidebar to achieve the Liquid Glass floating appearance. The current sidebar fills the full height of the `NavigationSplitView` without the glass effect at the top/bottom extensions.

**Three Sidebar Sections (Low)**

The sidebar has three sections: "Images", "Layout", and "Status" (conditional). HIG says "no more than two levels of hierarchy." Three sections is acceptable, but the "Status" section at the bottom could be moved to a non-critical area since HIG warns: "avoid critical information at bottom — users often relocate windows hiding the bottom edge."

**Empty AccentColor Asset (Low)**

`AccentColor.colorset/` exists but is empty. The app relies on system accent color, which is fine, but the empty colorset should either be populated or removed to avoid confusion.

### Recommendation

1. Add `.backgroundExtensionEffect()` to the sidebar `Form`
2. Consider consolidating "Status" into the "Layout" section or moving it to the toolbar
3. Populate or remove the empty AccentColor colorset

---

## 5. Split Views & Inspectors

### HIG Requirements
- Prefer `NavigationSplitView` for sidebar-detail layouts
- Use explicit selection state over push-only navigation
- Use `.inspector(isPresented:)` for lightweight detail controls

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `NavigationSplitView` | ✅ | `ContentView.swift:29` |
| Explicit selection state | ✅ | `viewModel.selectedPanelId` |
| Conditional detail panel | ✅ | `ContentView.swift:278-282` |
| Inspector pattern | ⚠️ Detail panel always visible |

### Findings

**Detail Panel Always Visible (Low)**

The detail column is always present and shows the `ExportPanel` at minimum. HIG's `.inspector(isPresented:)` pattern is designed for optional detail panels that complement main content. However, for a collage tool where export settings are always relevant, keeping the detail panel visible is acceptable.

**ScrollView in Detail Panel (Low)**

`ContentView.swift:276` wraps the detail content in a `ScrollView`. HIG recommends that inspector/detail content should scroll naturally — this is correct. However, the detail panel could benefit from `.inspector(isPresented:)` if the crop editor is shown only when a panel is selected.

### Recommendation

Consider using `.inspector(isPresented:)` for the crop editor when no panel is selected, showing only the export panel. When a panel is selected, the inspector expands to show crop controls.

---

## 6. Context Menus

### HIG Requirements
- Use `.contextMenu` for right-click/secondary-click actions
- Keep menus small (3-5 items max)
- Support consistently across applicable elements
- Always expose context menu actions in main UI too
- Hide unavailable items, don't dim them
- Use `.role(.destructive)` for destructive items

### Current State

| Requirement | Status |
|-------------|--------|
| Context menus on canvas panels | ❌ Missing |
| Context menus on sidebar items | ❌ Missing |
| Replace Image action | ❌ Missing |
| Reset Crop action | ❌ Missing |
| Remove Image in context menu | ❌ Missing |

### Findings

**No Context Menys on Canvas Panels (High)**

HIG suggests context menus on canvas panels for: Replace Image, Reset Crop, Remove Image. Users who right-click a panel on the canvas currently get the system context menu with no app-specific actions.

**No Context Menus on Sidebar Items (Medium)**

Right-clicking an image in the sidebar provides no options. Standard macOS pattern would include: Remove, Replace, and potentially Rename.

### Recommendation

Add context menus to canvas panels and sidebar rows:

```swift
// Canvas panel (CollageEditorView):
PanelHitArea(panel: panel, ...)
    .contextMenu {
        Button("Reset Crop") { viewModel.resetCrop(panelId: panel.id) }
        Divider()
        Button("Remove Image", role: .destructive) {
            viewModel.removeImage(at: imageIndex)
        }
    }

// Sidebar row (ContentView):
HStack { ... }
    .contextMenu {
        Button("Remove") { viewModel.removeImage(at: index) }
        Button("Replace") { /* future */ }
    }
```

---

## 7. Accessibility

### HIG Requirements
- Use `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue`, `.accessibilityAddTraits`
- Meet WCAG Level AA contrast ratios (4.5:1 for text up to 17pt)
- Prefer system-defined colors (`.red`, `.blue`, etc.)
- Convey information with more than color alone
- Support Full Keyboard Access — all controls must be keyboard-navigable
- Respect "Reduce Motion" setting
- Test with VoiceOver (Cmd+F5)

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| `.accessibilityLabel` | ❌ Missing | Throughout |
| `.accessibilityHint` | ❌ Missing | Throughout |
| `.accessibilityValue` | ❌ Missing | Sliders, toggles |
| `.accessibilityAddTraits` | ❌ Missing | Buttons, selections |
| System-defined colors | ✅ | Uses `.secondary`, `.tertiary`, etc. |
| Color-only state indication | ⚠️ Partial | "Ready" uses green checkmark |
| Reduce Motion | ❌ Missing | N/A |
| Keyboard navigation | ⚠️ Unknown | NSViewRepresentable views may not be keyboard accessible |

### Findings

**No Accessibility Annotations (High)**

Zero views in the app have `.accessibilityLabel`, `.accessibilityHint`, or `.accessibilityValue` modifiers. This means:
- VoiceOver users hear generic descriptions ("Button", "Slider")
- No context about what the button does ("Export collage as JPEG")
- No hints about what happens when activated
- Slider positions are not announced as values

**Specific gaps:**
- Export button: no label explaining it exports the collage
- Add Images button: no accessibility label
- Sliders (gutter, quality, title size, gradient angle, background opacity): no `.accessibilityValue` showing current value
- Panel selection: no `.accessibilityAddTraits(.isSelected)` on selected panels
- Layout picker: no accessibility label
- Crop preview: no description of what the user is looking at
- Progress indicators: no accessibility label for "Processing..." state

**Reduce Motion Not Respected (Medium)**

The app uses animations (`.transition(.opacity)` on export success, gesture animations) but does not check `@Environment(\.accessibilityReduceMotion)`. Users with motion sensitivity may experience discomfort.

**NSViewRepresentable Keyboard Accessibility (Medium)**

`ScrollPanView` and `AttributedStringEditorView` are `NSViewRepresentable` bridges. The `NSTextView` in `AttributedStringEditorView` has `isSelectable = true` but it is unclear if it properly participates in the Tab navigation order. The `NSColorWell` in `NSColorPickerView` should be keyboard accessible by default, but needs verification.

### Recommendation

1. Add `.accessibilityLabel` and `.accessibilityHint` to all buttons
2. Add `.accessibilityValue` to all sliders
3. Add `.accessibilityAddTraits(.isSelected)` to selected panels
4. Add `@Environment(\.accessibilityReduceMotion) var reduceMotion` and use it in animations
5. Verify Tab navigation works through all NSViewRepresentable views
6. Test with VoiceOver enabled (Cmd+F5)

---

## 8. Undo & Redo

### HIG Requirements
- Integrate `NSUndoManager` for undoable actions
- Use descriptive action names (not generic "Undo")
- Batch related continuous adjustments into a single undo unit
- Place undo/redo in Edit menu at top (system handles automatically)
- Command-Z (undo) and Shift-Command-Z (redo) work automatically
- Don't add undo buttons to the UI — rely on Edit menu

### Current State

| Requirement | Status |
|-------------|--------|
| `NSUndoManager` | ❌ Not implemented |
| Edit menu Undo/Redo | ❌ Missing |
| Undoable actions | ❌ None |

### Findings

**No Undo System (High)**

CollageMaker has zero undo support. The following actions should be undoable per HIG:

| Action | Undo Action Name |
|--------|-----------------|
| Image removal | "Remove Image" |
| Image reordering | "Reorder Images" |
| Layout changes | "Change Layout" |
| Crop adjustments | "Adjust Crop" (batched) |
| Title text edits | "Edit Title" |
| Background changes | "Change Background" |
| Panel image swaps | "Swap Images" |

Without undo, users who make a mistake (e.g., clear all images, change layout, adjust crop) have no way to recover. HIG states: "Avoid [alerts] for undoable actions — removing single image, resetting crop, changing layout."

**Crop Adjustments Should Be Batched (High)**

When a user pans or pinches to adjust a crop, each individual movement should NOT create a separate undo entry. HIG recommends batching:

```swift
func beginCropAdjustment() {
    undoManager.beginUndoGrouping()
}

func endCropAdjustment() {
    undoManager.setActionName("Adjust Crop")
    undoManager.endUndoGrouping()
}
```

### Recommendation

1. Add `private let undoManager = NSUndoManager()` to `CollageViewModel`
2. Register undo before making changes in: `removeImage`, `moveImages`, `setLayoutStyle`, `swapPanelImages`, `resetCrop`, `exportCollage` (for title changes)
3. Wrap crop pan/pinch operations in `beginUndoGrouping()` / `endUndoGrouping()`
4. The Edit menu with Undo/Redo will appear automatically

---

## 9. Progress Indicators

### HIG Requirements
- Use determinate progress when duration is known
- Use indeterminate progress when duration is unknown
- Be specific with labels ("Analyzing 5 images" not "Processing")
- Keep indicators moving
- Include Cancel when interrupting has no negative side effects
- Consistent location for indicators

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Indeterminate progress during processing | ✅ | `ContentView.swift:145-149` |
| Progress indicator during export | ✅ | `ExportPanel.swift:168-170` |
| Specific labels | ⚠️ Partial | "Processing..." is generic |
| Cancel button | ❌ Missing | Export flow |
| Determinate progress | ❌ Missing | Export has no progress |

### Findings

**Generic "Processing..." Label (Medium)**

`ContentView.swift:148` shows "Processing..." during saliency analysis. HIG recommends being specific: "Analyzing 5 images" instead of "Processing." The app knows the image count and should display it.

**No Export Progress (Medium)**

The export operation (`exportCollage()`) runs in a `Task.detached` but provides no progress feedback to the user beyond the spinner in the Export button. For a potentially long operation (full-resolution rasterization + JPEG encoding), a progress indicator would help users decide whether to wait.

**No Cancel During Export (Low)**

If the user starts an export and changes their mind, there is no way to cancel. `exportTask?.cancel()` is called internally but there is no UI for the user to trigger cancellation.

### Recommendation

1. Update saliency analysis progress to show image count: "Analyzing \(images.count) image(s)..."
2. Add a progress-indicating `ProgressView` during export (even if just indeterminate with a specific label like "Exporting collage...")
3. Add a Cancel button during export

---

## 10. Keyboard Shortcuts

### HIG Requirements
- Use standard shortcuts (Cmd+Z undo, Cmd+S save, Cmd+O open, etc.)
- Define custom shortcuts only for most frequently used actions
- List modifiers in order: Control, Option, Shift, Command
- Avoid Control modifier (system uses it for systemwide features)
- Support Full Keyboard Access

### Current State

| Shortcut | Action | Status |
|----------|--------|--------|
| Cmd+O | Add Images | ✅ (but missing `.command` modifier) |
| Cmd+S | Export JPEG | ✅ (but missing `.command` modifier) |
| Cmd+1/2/3 | Layout switch | ❌ Missing |
| Cmd+E | Export | ❌ Missing |
| Cmd+Z | Undo | ❌ Not implemented |
| Cmd+, | Settings | ❌ Not available (no Settings scene) |
| Cmd+Option+0 | Toggle Sidebar | ✅ (via `SidebarCommands()`) |

### Findings

**Modifier Keys Not Explicit (Medium)**

`CollageCommands.swift:11,24` use `.keyboardShortcut("o")` and `.keyboardShortcut("s")` without the `.command` modifier. While this works (Command is the default), HIG recommends being explicit for clarity and maintainability:

```swift
.keyboardShortcut("o", modifiers: .command)
.keyboardShortcut("s", modifiers: .command)
```

**Missing Layout Shortcuts (Medium)**

The Layout menu has no keyboard shortcuts. HIG suggests Cmd+1/2/3 for switching layouts in collage/photo apps.

**Missing Cmd+E for Export (Low)**

Cmd+E is the standard export shortcut in many macOS apps. Cmd+S is typically reserved for saving documents. Since CollageMaker exports JPEGs rather than saving a project file, Cmd+E may be more appropriate.

### Recommendation

1. Add explicit `.command` modifier to all existing shortcuts
2. Add Cmd+1/2/3 for layout switching
3. Consider Cmd+E for export (and remove Cmd+S, or keep Cmd+S for a future document format)

---

## 11. Alerts & Feedback

### HIG Requirements
- Use alerts for uncommon destructive actions and unexpected errors
- Use inline feedback for common undoable actions and expected success
- Alert titles should be specific, never "Error"
- Always use "Cancel" for cancel buttons
- Support Escape to dismiss alerts
- Keep success messages brief and auto-dismissing

### Current State

| Requirement | Status | Location |
|-------------|--------|----------|
| Alert for destructive actions | ❌ Missing | `clearAll()` |
| Alert for export errors | ⚠️ Inline only | `ExportPanel.swift:180-185` |
| Success feedback | ❌ Missing | After export |
| Specific alert titles | N/A | Not implemented |
| Escape to dismiss | ✅ (built-in) | System default |

### Findings

**No Confirmation for "Clear All" (Medium)**

`CollageCommands.swift:13` calls `viewModel.clearAll()` directly without any confirmation. HIG states: "uncommon destructive action (clear all) — Alert with confirmation." Clearing all images is destructive and uncommon; it should require confirmation.

**Export Error Shown Inline (Low)**

`ExportPanel.swift:180-185` shows export errors as red text below the export button. This is acceptable for minor errors, but file system errors (disk full, permission denied) should use an alert dialog for visibility.

**No Export Success Feedback (Low)**

After a successful export, there is no visual or audible feedback to the user. HIG recommends: "brief inline status message" for expected success.

**Yellow Warning Triangle for Image Count (Low)**

`ContentView.swift:162-167` shows a yellow warning triangle when not all images are in the layout. HIG cautions: "Use exclamationmark.triangle sparingly — only when extra attention is needed for unexpected data loss." This is a normal state (not all images need to be in every layout), so the warning may cause confusion.

### Recommendation

1. Add a confirmation alert for "Clear All"
2. Add a brief success toast/message after export completes
3. Use `.alert()` for export errors that need user attention
4. Replace the yellow warning triangle with a less alarming status indicator (e.g., a simple text note)

---

## Summary of Findings

### Critical (Fix Before Release)

| # | Category | Issue | Impact |
|---|----------|-------|--------|
| 1 | Undo & Redo | No `NSUndoManager` integration | Users cannot recover from mistakes |
| 2 | Settings | No Settings scene | No standard preferences entry point |
| 3 | Accessibility | No accessibility annotations | VoiceOver users have no context |
| 4 | Context Menus | No context menus on panels/sidebar | Missing standard macOS interaction pattern |

### Important (Fix Before Release)

| # | Category | Issue | Impact |
|---|----------|-------|--------|
| 5 | Commands | Keyboard shortcuts missing explicit modifiers | Code clarity and maintainability |
| 6 | Progress | Generic "Processing..." label | Users don't know what's happening |
| 7 | Alerts | No confirmation for "Clear All" | Destructive action without warning |
| 8 | Keyboard | No layout switching shortcuts | Frequently used actions lack shortcuts |

### Polish (Nice to Have)

| # | Category | Issue | Impact |
|---|----------|-------|--------|
| 9 | Sidebars | Missing `backgroundExtensionEffect()` | Non-native sidebar appearance |
| 10 | Progress | No export progress feedback | Users can't gauge wait time |
| 11 | Alerts | No export success feedback | Unclear if export worked |
| 12 | Accessibility | Reduce Motion not respected | May discomfort sensitive users |
| 13 | Settings | Manual UserDefaults instead of `@AppStorage` | More boilerplate, less integration |
| 14 | Windows | No `@SceneStorage` for per-window state | Multi-window support would be broken |

---

## Recommended Implementation Priority

| Priority | Category | Work |
|----------|----------|------|
| P0 | Undo & Redo | Add `NSUndoManager` to `CollageViewModel`, wrap all mutating actions |
| P0 | Settings | Add `Settings` scene, migrate key `@AppStorage` properties |
| P1 | Accessibility | Add `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint` to all interactive elements |
| P1 | Context Menus | Add `.contextMenu` to canvas panels and sidebar image rows |
| P1 | Commands | Add explicit `.command` modifiers, add Cmd+1/2/3 for layouts |
| P2 | Alerts | Add confirmation alert for "Clear All", success feedback for export |
| P2 | Progress | Show image count in processing label, add export progress indicator |
| P3 | Sidebars | Add `.backgroundExtensionEffect()` to sidebar |
| P3 | Accessibility | Add `@Environment(\.accessibilityReduceMotion)` support |
| P3 | Windows | Add `@SceneStorage` for sidebar state |
