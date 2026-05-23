---
name: playwright-apple-docs
description: Extract content from Apple Developer documentation pages using playwright-cli. Apple docs are JavaScript-rendered SPAs that require a real browser — webfetch returns only noscript placeholders. Use when researching Apple API references, HIG guidelines, or any developer.apple.com page.
allowed-tools: Bash(playwright-cli:*)
---

# Extracting Apple Developer Docs with playwright-cli

Apple Developer pages are JavaScript-rendered SPAs. `webfetch` returns only the "This page requires JavaScript" noscript placeholder. Use playwright-cli with the patterns below to extract content reliably.

## Quick start

```bash
# Navigate to an Apple docs page
playwright-cli goto "https://developer.apple.com/documentation/appkit/nsevent"

# Extract content (use --raw to strip page status and snapshots)
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

## Content extraction patterns

### General page dump

Extract headings and body text, filtering out short navigation chrome:

```bash
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

### Topic-specific extraction

Filter by keyword to focus on relevant content:

```bash
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5 && el.textContent.indexOf('Scroll') >= 0; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

### Sidebar topic discovery (API reference pages)

Find related topics from a class overview page when the exact URL is unknown:

```bash
playwright-cli goto "https://developer.apple.com/documentation/appkit/nsevent"
playwright-cli --raw eval "Array.from(document.querySelectorAll('li a')).map(function(a) { return a.textContent.trim() + ' | ' + a.href; }).filter(function(s) { return s.indexOf('scroll') >= 0 || s.indexOf('Scroll') >= 0; }).join('\\n')"
```

### Sample Code page section extraction

The Sample Code page (`/documentation/SampleCode`) has a different DOM structure than API reference pages. It uses `<h3>` section headers with sibling `<div class="link-block topic">` elements containing `a.link` links, NOT `<li>` elements. Content is also lazy-loaded, so you must scroll before extracting.

```bash
# Scroll to trigger lazy-loading of sections
playwright-cli goto "https://developer.apple.com/documentation/SampleCode"
playwright-cli mousewheel 0 1000
playwright-cli mousewheel 0 1000

# Extract samples from a specific section (e.g., "AppKit")
playwright-cli --raw eval "(function() { var allH3 = Array.from(document.querySelectorAll('h3')); var targetIdx = -1, nextIdx = -1; for (var i = 0; i < allH3.length; i++) { if (allH3[i].textContent.trim() === 'AppKit') targetIdx = i; if (targetIdx >= 0 && i > targetIdx && nextIdx < 0) nextIdx = i; } var targetParent = allH3[targetIdx].parentElement; var nextParent = nextIdx >= 0 ? allH3[nextIdx].parentElement : null; var links = []; var el = targetParent.nextElementSibling; while (el && el !== nextParent) { Array.from(el.querySelectorAll('a.link')).forEach(function(a) { links.push(a.textContent.trim().substring(0, 150) + ' | ' + a.href); }); el = el.nextElementSibling; } return links.join('\\n'); })()"
```

This iterates siblings between the target `<h3>` header and the next `<h3>` header, collecting `a.link` elements. Replace `'AppKit'` with any section name (e.g., `'SwiftUI'`, `'UIKit'`).

## Critical rules

### JavaScript syntax in eval

The eval context does not support modern JavaScript. Use:
- `function(el)` not `(el) =>`
- `var` not `const`/`let`
- Avoid destructuring and other ES6+ features

### Always use --raw

The `--raw` flag strips page status, generated code, and snapshot sections. Without it, output includes noise unsuitable for capturing into research documents.

### No explicit waits needed

Apple docs pages render quickly. After `goto`, `eval` commands work immediately without explicit waits.

## Handling common issues

### Navigation chrome contamination

Apple docs have extensive sidebar navigation captured alongside article content. Mitigation strategies:
- Filter by minimum text length (`> 5` chars removes most nav items)
- Filter by keyword relevance
- Avoid relying on `<article>` tags — Apple docs don't consistently use them

### URL instability

Apple docs URLs use encoded signatures that are hard to predict:
- `view/onscrollphasechange(_:_:)` may 404 (double colon)
- `view/onscrollphasechange(_:):` works (single colon)
- Some property pages redirect to the parent class page

**When a URL 404s:** Navigate to the parent class page, extract the topic list from the sidebar using the sidebar discovery pattern, then navigate to the correct URL.

### Dynamic content loading

Some pages lazy-load content on scroll. If content appears missing:
```bash
playwright-cli mousewheel 0 500
# then run eval to extract
```

**Sample Code page** (`/documentation/SampleCode`): Content is always lazy-loaded. Multiple `mousewheel 0 1000` calls are required before section content appears in the DOM. Never skip scrolling on this page.

**HIG guides**: Often lazy-load sections on scroll. Use `mousewheel 0 800` before extraction.

### Fragment navigation doesn't auto-scroll

Navigating to a URL with a fragment (e.g., `#AppKit`) loads the page but does NOT scroll to that section. You must manually scroll using `mousewheel` or `scrollIntoView` JS.

### No parallel fetching

Playwright-cli operates on a single browser session sequentially. Researching multiple pages requires sequential `goto` + `eval` round trips. This is slow but reliable.

## Workflow: researching an API

1. Navigate to the parent class page
2. Use sidebar topic discovery to find correct URLs for the APIs you need
3. Navigate to each API page sequentially
4. Extract content with topic-specific filtering
5. Close the browser when done

```bash
playwright-cli goto "https://developer.apple.com/documentation/swiftui/view"
playwright-cli --raw eval "Array.from(document.querySelectorAll('li a')).map(function(a) { return a.textContent.trim() + ' | ' + a.href; }).filter(function(s) { return s.indexOf('scroll') >= 0 || s.indexOf('Scroll') >= 0; }).join('\\n')"
# Note the URLs from output, then navigate to each
playwright-cli goto "https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:):"
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

## Workflow: researching HIG guidelines

HIG pages often require scrolling to trigger lazy-loaded content:

```bash
playwright-cli goto "https://developer.apple.com/design/human-interface-guidelines/scroll-views"
playwright-cli mousewheel 0 800
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

## Workflow: searching Sample Code

1. Navigate to the Sample Code page
2. Scroll multiple times to trigger lazy-loading of all sections
3. Extract samples from the relevant framework section using the section extraction pattern
4. Filter results by keyword if needed

```bash
playwright-cli goto "https://developer.apple.com/documentation/SampleCode"
playwright-cli mousewheel 0 1000
playwright-cli mousewheel 0 1000
playwright-cli --raw eval "(function() { var allH3 = Array.from(document.querySelectorAll('h3')); var targetIdx = -1, nextIdx = -1; for (var i = 0; i < allH3.length; i++) { if (allH3[i].textContent.trim() === 'SwiftUI') targetIdx = i; if (targetIdx >= 0 && i > targetIdx && nextIdx < 0) nextIdx = i; } var targetParent = allH3[targetIdx].parentElement; var nextParent = nextIdx >= 0 ? allH3[nextIdx].parentElement : null; var links = []; var el = targetParent.nextElementSibling; while (el && el !== nextParent) { Array.from(el.querySelectorAll('a.link')).forEach(function(a) { links.push(a.textContent.trim().substring(0, 150) + ' | ' + a.href); }); el = el.nextElementSibling; } return links.join('\\n'); })()"
```

## Research strategy

Choose the right docs resource based on what you're researching:

| Researching | Use | Why |
|---|---|---|
| High-level patterns (navigation, drag-and-drop, state management) | Sample Code page first | Apple publishes working examples for common patterns |
| Low-level event handling (scroll, gestures, key events) | API docs directly | No sample code exists for basic `scrollWheel`, `keyDown`, `mouseDragged`, etc. |
| UX conventions (scroll behavior, gesture expectations) | HIG guides | Authoritative guidance on platform conventions |

**Key insight:** Apple's sample code covers high-level patterns but not low-level AppKit event handling. For basic patterns like `scrollWheel(with:)`, the API docs are sufficient — no samples exist.

## Anti-patterns

- **Do not use webfetch** for developer.apple.com pages — they are JS-rendered SPAs
- **Do not use arrow functions or const/let in eval** — use function() and var
- **Do not assume article elements exist** — Apple docs don't consistently use semantic article tags
- **Do not guess Apple docs URLs** — use sidebar discovery to find correct URLs
- **Do not extract without filtering** — navigation chrome will dominate the output
- **Do not use `li a` selector on Sample Code pages** — sample links use `a.link` in `div.topic` elements, not `li`
- **Do not skip scrolling on Sample Code page** — content is lazy-loaded and won't be in the DOM until scrolled
- **Do not expect sample code for basic AppKit patterns** — `scrollWheel`, `keyDown`, `mouseDragged` are in API refs, not samples
- **Do not rely on URL fragments to scroll** — `#section` in URL doesn't auto-scroll to the section

## Installation

If global playwright-cli is not available:

```bash
npx --no-install playwright-cli --version
# If that works, use npx playwright-cli in all commands
# Otherwise install globally:
npm install -g @playwright/cli@latest
```
