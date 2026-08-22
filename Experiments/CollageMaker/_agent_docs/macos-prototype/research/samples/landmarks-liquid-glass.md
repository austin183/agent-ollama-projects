# Landmarks: Building an App with Liquid Glass - Research Document

**Source**: Apple Developer Documentation — SwiftUI Sample Code
**URL**: https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass
**Platform**: iOS 26.0+, iPadOS 26.0+, macOS 26.0+, Mac Catalyst 26.0+, Xcode 26.0+
**Date Researched**: 2026-05-11

---

## Summary

Landmarks is Apple's reference SwiftUI sample app demonstrating Liquid Glass design patterns. It uses a `NavigationSplitView` to organize content with a sidebar, detail column, and inspector panel. The app explores national parks and landmarks, with features for favorites, collections, and activity badges. It runs on iPad, iPhone, and Mac with adaptive layouts.

**Key Liquid Glass features demonstrated:**
1. Background extension effect — images blur and extend under sidebar/inspector
2. Horizontal scrolling under sidebar/inspector — scroll views extend behind panels
3. System-provided glass effect in toolbars — automatic Liquid Glass on toolbar items
4. Custom Liquid Glass elements — badges with morphing animations

---

## Architecture Overview

### Three-Column NavigationSplitView

The app is structured around `NavigationSplitView` with three columns:

| Column | Content | Purpose |
|--------|---------|---------|
| Sidebar | Continent/category list | Navigate landmark categories |
| Detail | Landmark cards, featured image, horizontal scroll lists | Browse and select landmarks |
| Inspector | Landmark details, metadata | View/edit selected landmark info |

### Key Views

- **`LandmarksView`** — Main detail column. Contains:
  - `LandmarkFeaturedItemView` — Featured landmark with background extension effect
  - `LazyVStack` — Vertical scrollable content, edge-aligned (no padding)
  - `ScrollView` — Outer scroll container, `showsIndicators: false`
  - `LandmarkHorizontalListView` — Horizontal scroll per continent, extends under sidebar/inspector

- **`LandmarkDetailView`** — Selected landmark detail view. Contains:
  - Main image with `.backgroundExtensionEffect()`
  - `ScrollView` + `VStack` with no padding for edge alignment
  - Toolbar with share, favorites, collections, and inspector toggle

- **`CollectionsView`** — Collections management with `.showsBadges()` modifier

---

## Key SwiftUI Patterns

### 1. Background Extension Effect

**Purpose**: Extend and blur an image under the sidebar or inspector panel for a seamless edge-to-edge experience.

**How it works:**
1. Align the view to the leading and trailing edges of the containing view (no padding on parent containers)
2. Apply `.backgroundExtensionEffect()` modifier to the image
3. For composite views (image + overlay), apply the modifier to the image *before* adding overlays

**Sidebar extension behavior:**
- System takes a section of the image's leading edge matching sidebar width
- Flips that portion horizontally toward the leading edge
- Applies a blur to the flipped section
- Places the modified section under the sidebar

**Inspector extension behavior:**
- Same process, but on the trailing edge toward the inspector

**Code pattern:**
```swift
// In LandmarksView — no padding on ScrollView or LazyVStack
ScrollView(showsIndicators: false) {
    LazyVStack(alignment: .leading, spacing: Constants.standardPadding) {
        LandmarkFeaturedItemView(landmark: modelData.featuredLandmark!)
            .flexibleHeaderContent()
        // ...
    }
}

// In LandmarkFeaturedItemView — modifier on image BEFORE overlay
Image(decorative: landmark.backgroundImageName)
    // ...
    .backgroundExtensionEffect()
    .overlay(alignment: .bottom) {
        VStack {
            Text("Featured Landmark")
            Text(landmark.name)
            Button("Learn More") {
                modelData.path.append(landmark)
            }
        }
        .padding([.bottom], Constants.learnMoreBottomPadding)
    }

// In LandmarkDetailView — modifier on main image
Image(landmark.backgroundImageName)
    // ...
    .backgroundExtensionEffect()
```

**Key insight for CollageMaker**: Apply `.backgroundExtensionEffect()` to the *image only*, not to composite views with text/buttons. The modifier must come before `.overlay()` so that only the image extends behind panels, not the overlay content.

### 2. Horizontal Scrolling Under Sidebar/Inspector

**Purpose**: Allow horizontal scroll views to scroll underneath the sidebar and inspector panels.

**How it works:**
- Configure the scroll view to touch the leading and trailing edges
- When a scroll view touches the sidebar or inspector, the system automatically adjusts it to scroll under the panel and then off the edge of the screen

**Code pattern:**
```swift
// LandmarkHorizontalListView
ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(spacing: Constants.standardPadding) {
        Spacer()
            .frame(width: Constants.standardPadding)  // Inset to align with title padding
        ForEach(landmarkList) { landmark in
            // ... landmark cards
        }
    }
}
```

**Key insight**: Use a `Spacer()` with a fixed width frame at the beginning of the `LazyHStack` to inset content. The scroll view itself must touch the leading and trailing edges (no padding on the parent). The system handles the rest automatically.

### 3. Toolbar Organization with Liquid Glass

**Purpose**: Organize toolbar items into logical groupings with the system-provided Liquid Glass effect.

**How it works:**
- The system applies Liquid Glass to toolbar items automatically
- Use `ToolbarSpacer` with different sizing parameters to create visual groupings
- `.flexible` spacer expands to fill available space
- `.fixed` spacer creates a small gap between related items

**Code pattern:**
```swift
.toolbar {
    ToolbarSpacer(.flexible)

    ToolbarItem {
        ShareLink(item: landmark, preview: landmark.sharePreview)
    }

    ToolbarSpacer(.fixed)

    ToolbarItemGroup {
        LandmarkFavoriteButton(landmark: landmark)
        LandmarkCollectionsMenu(landmark: landmark)
    }

    ToolbarSpacer(.fixed)

    ToolbarItem {
        Button("Info", systemImage: "info") {
            modelData.selectedLandmark = landmark
            modelData.isLandmarkInspectorPresented.toggle()
        }
    }
}
```

**Toolbar item types used:**
- `ToolbarItem` — Single item
- `ToolbarItemGroup` — Group of related items sharing the same glass pill
- `ToolbarSpacer(.flexible)` — Expands to push items apart
- `ToolbarSpacer(.fixed)` — Creates a small gap between groups

**Key insight**: The grouping creates distinct glass "pills" in the toolbar. Use `ToolbarItemGroup` for related actions and `ToolbarItem` for standalone actions.

### 4. Custom Liquid Glass Badges with Morph Animation

**Purpose**: Create custom UI elements with Liquid Glass that animate with the morph effect.

**How it works:**
1. Create a `ViewModifier` to layer badges over any view using `ZStack`
2. Apply `.glassEffect(.regular, in: .rect(cornerRadius: ...))` to each badge
3. Apply `.buttonStyle(.glass)` to the toggle button
4. Organize badges and toggle button into a `GlassEffectContainer`
5. Assign each element a `glassEffectID(_:in:)` for morph animation
6. Wrap state changes in `withAnimation { }` for morph effect

**Code pattern:**
```swift
// Custom modifier to layer badges over any view
private struct ShowsBadgesViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            content
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    BadgesView()
                        .padding()
                }
            }
        }
    }
}

extension View {
    func showsBadges() -> some View {
        modifier(ShowsBadgesViewModifier())
    }
}

// Glass toggle button
Button {
    withAnimation {
        isExpanded.toggle()
    }
} label: {
    ToggleBadgesLabel(isExpanded: isExpanded)
        .frame(width: Constants.badgeShowHideButtonWidth,
               height: Constants.badgeShowHideButtonHeight)
}
.buttonStyle(.glass)
#if os(macOS)
.tint(.clear)
#endif
.glassEffectID("togglebutton", in: namespace)

// GlassEffectContainer for morph animation
GlassEffectContainer(spacing: Constants.badgeGlassSpacing) {
    VStack(alignment: .center, spacing: Constants.badgeButtonTopSpacing) {
        if isExpanded {
            VStack(spacing: Constants.badgeSpacing) {
                ForEach(modelData.earnedBadges) {
                    BadgeLabel(badge: $0)
                        .glassEffect(.regular, in: .rect(cornerRadius: Constants.badgeCornerRadius))
                        .glassEffectID($0.id, in: namespace)
                }
            }
        }
        // ... toggle button with glassEffectID
    }
    .frame(width: Constants.badgeFrameWidth)
}
```

**Key modifiers:**
- `.glassEffect(.regular, in: .rect(cornerRadius: ...))` — Apply Liquid Glass to custom views
- `.buttonStyle(.glass)` — Apply Liquid Glass to buttons
- `.glassEffectID(_:in:)` — Assign unique ID for morph animation within a `GlassEffectContainer`
- `GlassEffectContainer` — Groups elements that should morph together
- `withAnimation { }` — Wraps state changes to trigger morph animation

**macOS-specific note**: The sample uses `#if os(macOS) .tint(.clear) #endif` on the glass button, suggesting macOS may need explicit tint clearing for proper glass rendering.

---

## Selection State Management

The sample uses an `@Observable` class (`modelData`) for state management:

- `selectedLandmark` — Currently selected landmark for inspector display
- `isLandmarkInspectorPresented` — Boolean controlling inspector visibility
- `path` — Navigation path for programmatic navigation
- `earnedBadges` — Collection of earned badge data

Inspector is toggled via toolbar button:
```swift
Button("Info", systemImage: "info") {
    modelData.selectedLandmark = landmark
    modelData.isLandmarkInspectorPresented.toggle()
}
```

Navigation uses `NavigationPath`:
```swift
Button("Learn More") {
    modelData.path.append(landmark)
}
```

---

## Split View Behavior and Inspector Patterns

- The inspector is controlled by `isLandmarkInspectorPresented` boolean state
- Inspector content is driven by `selectedLandmark` — setting this before toggling ensures the correct detail is shown
- The inspector toggle button lives in the toolbar of `LandmarkDetailView`
- Background extension effect automatically extends content under both sidebar and inspector when they're open

---

## Toolbar Patterns

### Automatic Liquid Glass
The system applies Liquid Glass to toolbar items automatically. No explicit modifier needed for standard toolbar items.

### Grouping Strategy
- **`ToolbarSpacer(.flexible)`** — Pushes items to edges or separates major groups
- **`ToolbarSpacer(.fixed)`** — Small gap between adjacent groups
- **`ToolbarItemGroup`** — Multiple items share one glass pill
- **`ToolbarItem`** — Single item in its own glass pill

### Toolbar Items in LandmarkDetailView
From leading to trailing:
1. Back button (system-provided)
2. Share button (`ShareLink` in `ToolbarItem`)
3. Favorite + Collections buttons (`ToolbarItemGroup`)
4. Info/Inspector toggle button (`ToolbarItem`)
5. Search bar (system-provided)

---

## Specific Applicability to CollageMaker

### Three-Column Layout
CollageMaker's three-column layout (Templates | Canvas | Properties) maps directly to the Landmarks pattern:
- **Sidebar → Templates panel**: Category list for browsing templates
- **Detail → Canvas**: Main workspace showing the collage canvas
- **Inspector → Properties panel**: Edit properties of selected elements

### Background Extension for Canvas
The canvas preview image could use `.backgroundExtensionEffect()` to extend behind the templates sidebar and properties inspector, creating a seamless visual experience. Key considerations:
- Apply the modifier to the canvas image *before* any overlay elements
- Ensure `ScrollView` and parent containers have no padding
- The effect works automatically when sidebar/inspector are open

### Horizontal Scroll for Template Thumbnails
Template thumbnail rows can use the horizontal scroll pattern to extend under the sidebar/inspector:
```swift
ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(spacing: padding) {
        Spacer().frame(width: padding)
        ForEach(templates) { template in
            TemplateThumbnailView(template: template)
        }
    }
}
```

### Toolbar for Canvas Actions
CollageMaker's canvas toolbar can follow the grouping pattern:
- Export/Share as standalone `ToolbarItem`
- Undo/Redo as `ToolbarItemGroup`
- Layer management as `ToolbarItemGroup`
- Inspector toggle as standalone `ToolbarItem`

### Liquid Glass for Custom UI Elements
- Custom glass buttons for tool palette: `.buttonStyle(.glass)`
- Glass properties cards: `.glassEffect(.regular, in: .rect(cornerRadius: ...))`
- Animated transitions between tool states using `GlassEffectContainer` + `glassEffectID`

---

## Gotchas and macOS-Specific Considerations

### 1. macOS Glass Button Tint
On macOS, glass buttons may need explicit `.tint(.clear)` to render correctly:
```swift
#if os(macOS)
.tint(.clear)
#endif
```

### 2. Edge Alignment Is Critical
For both background extension and horizontal scroll under panels:
- Parent `ScrollView` must have no padding
- Parent `LazyVStack`/`VStack` must have no padding
- Content must align to leading/trailing edges of the container
- Use `Spacer().frame(width: ...)` for controlled insets within scroll content

### 3. Modifier Order Matters for Background Extension
Apply `.backgroundExtensionEffect()` to the image *before* adding `.overlay()`. If applied after the overlay, the overlay content will also extend under the sidebar/inspector, creating visual artifacts.

### 4. GlassEffectContainer Requires Namespace
The `glassEffectID(_:in:)` modifier requires a namespace parameter. All elements in a `GlassEffectContainer` must share the same namespace for morph animation to work correctly.

### 5. Platform Availability
All Liquid Glass features require:
- macOS 26.0+ (Sequoia 26 / Tahoe)
- Xcode 26.0+
- These are forward-looking APIs not available on current stable macOS

### 6. showsIndicators: false
Both the vertical and horizontal scroll views in the sample use `showsIndicators: false`. This is likely important for the visual effect, as scroll indicators would break the seamless edge-to-edge appearance.

### 7. flexibleHeaderContent()
The sample uses `.flexibleHeaderContent()` on the featured item view. This appears to be a custom modifier that enables the header to participate in the scroll extension behavior. CollageMaker may need a similar approach for the canvas view.

---

## Key API Reference

| API | Purpose |
|-----|---------|
| `backgroundExtensionEffect()` | Extends and blurs content under sidebar/inspector |
| `glassEffect(_:in:)` | Applies Liquid Glass to custom views |
| `buttonStyle(.glass)` | Applies Liquid Glass to buttons |
| `GlassEffectContainer` | Groups elements for morph animation |
| `glassEffectID(_:in:)` | Assigns ID for morph animation tracking |
| `ToolbarSpacer(.flexible)` | Expanding toolbar spacer |
| `ToolbarSpacer(.fixed)` | Fixed-width toolbar spacer |
| `ToolbarItemGroup` | Groups related toolbar items |
| `NavigationSplitView` | Three-column layout container |
| `@Observable` | State management class |

---

## Download

The full sample code is available for download:
https://docs-assets.developer.apple.com/published/5494b10f5cc7/LandmarksBuildingAnAppWithLiquidGlass.zip
