# Apple Sample Code Page Research — Learnings

## Date
2026-05-13

## Context

Researched Apple's Sample Code Library page for gesture/scroll/pan samples relevant to Batch 4 (two-finger scroll pan via `NSViewRepresentable` + `scrollWheel(with:)`).

## What Worked

### Section-Based Extraction Pattern

The Sample Code page structures samples under `<h3>` section headers (e.g., "AppKit", "SwiftUI"), with sample links in sibling `<div>` elements. The working extraction pattern:

```js
(function() {
  var allH3 = Array.from(document.querySelectorAll('h3'));
  var targetIdx = -1, nextIdx = -1;
  for (var i = 0; i < allH3.length; i++) {
    if (allH3[i].textContent.trim() === 'AppKit') targetIdx = i;
    if (targetIdx >= 0 && i > targetIdx && nextIdx < 0) nextIdx = i;
  }
  var targetParent = allH3[targetIdx].parentElement;
  var nextParent = nextIdx >= 0 ? allH3[nextIdx].parentElement : null;
  var links = [];
  var el = targetParent.nextElementSibling;
  while (el && el !== nextParent) {
    Array.from(el.querySelectorAll('a.link')).forEach(function(a) {
      links.push(a.textContent.trim().substring(0, 150) + ' | ' + a.href);
    });
    el = el.nextElementSibling;
  }
  return links.join('\n');
})()
```

This iterates siblings between the target section header and the next section header, collecting `a.link` elements.

### Scroll to Trigger Lazy Loading

The Sample Code page lazy-loads section content. Initial `querySelectorAll` returned only navigation chrome. Multiple `mousewheel 0 1000` calls were needed to trigger rendering of the topic sections before links became available.

### Fragment Navigation Doesn't Auto-Scroll

`goto "https://developer.apple.com/documentation/SampleCode#AppKit"` navigates to the page but doesn't scroll to the `#AppKit` section. Had to use `scrollIntoView` JS or `mousewheel` to reach the section.

## What Didn't Work

### `li a` Selector for Sample Links

The sidebar topic discovery pattern (`querySelectorAll('li a')`) works for API reference pages but returns empty results on the Sample Code page. Sample links use `a.link` class inside `<div class="link-block topic">` elements, not `<li>` elements.

### Searching for Gesture Samples Yields Nothing

Searched AppKit (9 samples), SwiftUI (23 samples), and UIKit (47 samples) sections. No macOS-specific scroll/gesture samples exist:
- AppKit samples cover: toolbar, finder extensions, document-based apps, outline/split views, drag-and-drop file promises
- SwiftUI samples cover: navigation, drag-and-drop, animations, custom layouts — but no low-level gesture handling
- UIKit has "Selecting multiple items with a two-finger pan gesture" but it's iOS-specific (`UITableView` delegate methods)

**Lesson:** Apple doesn't publish sample code for basic AppKit patterns like `scrollWheel(with:)` override. These are considered fundamental enough that the API docs are sufficient.

### `goto` Fragment Doesn't Help Discovery

Navigating to `#AppKit` fragment loads the page but doesn't scroll or expand the section. Still needed to scroll manually and parse the DOM.

## What Was Confusing

### Vue.js DOM Structure

The page uses Vue.js (evident from `data-v-*` attributes). Section structure is:
```
<div>
  <h3 id="AppKit">AppKit</h3>
</div>
<div class="link-block topic">
  <a class="link" href="...">Sample Name</a>
</div>
<div class="link-block topic">
  ...
</div>
```

This is different from API reference pages, which use sidebar `<nav>` with `<li>` items.

## Key Insight

**Sample code ≠ API coverage.** Apple's sample code library covers high-level patterns (navigation, drag-and-drop, state management) but not low-level event handling. For Batch 4's `scrollWheel(with:)` approach:
- Sample code: **no relevant samples exist**
- API docs: sufficient (`NSEvent.scrollingDeltaX/Y`, `NSEvent.phase`, `NSResponder.scrollWheel(with:)`)

When researching AppKit event handling, go directly to the API docs rather than searching sample code.

## Skill Improvements

### Update `playwright-apple-docs` Skill

Add Sample Code page-specific patterns:
1. **Lazy loading**: Always scroll before extracting from `/documentation/SampleCode`
2. **Section extraction**: Use sibling iteration between `<h3>` headers, not `li a`
3. **Link selector**: Use `a.link` not `li a` for sample links

### Update Research Strategy

For future Apple docs research:
1. **Sample code search first** when looking for high-level patterns (navigation, state management, drag-and-drop)
2. **API docs directly** when researching low-level event handling (scroll, gestures, key events)
3. **HIG** when researching UX conventions (scroll behavior, gesture expectations)

## Anti-Patterns

- **Don't use `li a` on Sample Code pages** — sample links use `a.link` in `div.topic` elements
- **Don't assume fragment navigation scrolls** — `#section` in URL doesn't auto-scroll
- **Don't expect samples for basic AppKit patterns** — `scrollWheel`, `keyDown`, `mouseDragged` etc. are documented in API refs, not samples
- **Don't skip scrolling on Sample Code page** — content is lazy-loaded and won't be in the DOM until scrolled into view

## Next Steps

- Update `playwright-apple-docs` skill with Sample Code page patterns
- For Batch 4, rely on API docs (`NSEvent`, `NSResponder`, `NSView`) rather than sample code for implementation guidance

---
**Status**: Closed
**Follow-up**: Update playwright-apple-docs skill
