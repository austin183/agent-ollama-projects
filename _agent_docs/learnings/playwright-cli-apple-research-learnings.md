# Playwright-Cli Apple Developer Docs Research — Learnings

## Date
2026-05-13

## Context

Researched Apple Developer documentation pages for scroll-related APIs and HIG guidelines to inform Batch 4 (two-finger scroll pan) implementation. Needed to capture content from 12+ Apple docs pages and the HIG scroll views guide.

## What Worked

### Playwright-cli is Required for Apple Docs

Apple Developer pages are JavaScript-rendered SPAs. `webfetch` returns only the "This page requires JavaScript" noscript placeholder. Playwright-cli with a real browser is the only viable approach for extracting content from these pages.

### Content Extraction Pattern

The most reliable extraction pattern is `--raw eval` with `Array.from` + `querySelectorAll` + `map/filter`:

```bash
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

Key aspects:
- Use `function(el)` syntax, not arrow functions — the eval context doesn't support `const`/`let`/arrow functions reliably
- Filter by `textContent.trim().length > 5` to remove navigation chrome
- Prefix with `tagName` to distinguish headings from body text
- Truncate to 800 chars per element to avoid overwhelming output
- Join with `\\n---\\n` delimiter for easy post-processing

### Sequential Navigation is Fine

Playwright-cli navigates pages sequentially with `goto`. Each `goto` waits for the page to load. No explicit wait was needed for Apple docs pages — they render quickly enough that subsequent `eval` commands work immediately.

### --raw Output Mode is Essential

The `--raw` flag strips page status, generated code, and snapshot sections, returning only the result value. This makes output suitable for capturing and writing to research documents.

## What Was Tricky

### Navigation Chrome Contamination

Apple docs pages have extensive sidebar navigation that gets captured alongside article content. The `querySelectorAll('p, pre, h1, h2, h3')` approach picks up sidebar items. Filtering strategies:
- Filter by minimum text length (> 5 chars removes most nav items)
- Filter by relevance (e.g., `textContent.indexOf('Scroll') >= 0`)
- Target `article` elements specifically when available (but Apple docs don't consistently use `<article>`)

### URL Instability

Some Apple docs URLs redirect or return 404:
- `view/onscrollphasechange(_:_:)` → 404 (double colon in path)
- `view/onscrollphasechange(_:):` → works (single colon)
- `nsevent/mphase` → redirect
- Some property pages redirect to the parent class page

**Lesson:** When a URL 404s, try the parent class page and extract the property from the sidebar/topic list, or try alternative URL formats.

### No Parallel Page Fetching

Playwright-cli operates on a single browser session sequentially. To research 12 pages, you need 12+ sequential `goto` + `eval` round trips. This is slow but reliable. No workaround exists for true parallelism with a single browser.

### Dynamic Content Loading

Some pages loaded navigation but not article content immediately. A `mousewheel` scroll helped trigger lazy-loaded content on the HIG page, but most API reference pages loaded fully on navigation.

## What I'd Do Differently

### Better Content Targeting

Instead of broad `querySelectorAll('p, pre, h1, h2, h3')`, target the main content area more precisely:
- Look for the H1 heading first, then extract siblings/children
- Use `document.querySelector('h1')?.nextElementSibling` traversal for API pages
- For HIG pages, scroll first to trigger lazy loading, then extract

### URL Discovery Strategy

When unsure of the exact URL:
1. Navigate to the parent page (e.g., `NSEvent` overview)
2. Extract the topic list from the sidebar to find correct URLs
3. Navigate to each topic page

This avoids 404s from guessing URL slugs.

### Output Post-Processing

Rather than extracting everything inline, consider:
1. `--raw eval` to dump full page text to a file
2. Post-process the file to extract relevant sections
3. This avoids truncation and allows iterative refinement

## Anti-Patterns to Avoid

- **Don't use `webfetch` for Apple Developer pages** — they're JS-rendered SPAs
- **Don't use arrow functions or `const/let` in `eval`** — use `function()` and `var`
- **Don't assume `<article>` exists** — Apple docs don't consistently use semantic article tags
- **Don't guess Apple docs URLs** — they use encoded signatures that are hard to predict
- **Don't extract without filtering** — navigation chrome will dominate the output

## Reusable Patterns

### Quick Page Content Dump

```bash
playwright-cli goto "https://developer.apple.com/documentation/path"
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

### Topic-Specific Extraction

```bash
playwright-cli --raw eval "Array.from(document.querySelectorAll('p, pre, h1, h2, h3')).filter(function(el) { return el.textContent.trim().length > 5 && el.textContent.trim().indexOf('Scroll') >= 0; }).map(function(el) { return el.tagName + ': ' + el.textContent.trim().substring(0, 800); }).join('\\n---\\n')"
```

### Sidebar Topic Discovery

```bash
playwright-cli goto "https://developer.apple.com/documentation/appkit/nsevent"
playwright-cli --raw eval "Array.from(document.querySelectorAll('li a')).map(function(a) { return a.textContent.trim() + ' → ' + a.href; }).filter(function(s) { return s.indexOf('scroll') >= 0 || s.indexOf('Scroll') >= 0; }).join('\\n')"
```

## Research Output

Produced 5 research documents in `_agent_docs/research/`:
1. `scroll-views-hig.md` — Apple HIG scroll view guidelines
2. `swiftui-scroll-target-behavior.md` — ScrollTargetBehavior protocol and built-in behaviors
3. `swiftui-scroll-phase-geometry.md` — ScrollPhase enum, onScrollPhaseChange, ScrollGeometry
4. `appkit-scrollwheel-events.md` — NSEvent scroll properties, phases, scrollWheel override
5. `appkit-scroll-gesture-recognizers.md` — NSPanGestureRecognizer vs scrollWheel approach comparison
6. `swiftui-scrollview-integration.md` — ScrollView patterns and why they don't apply to canvas pan
