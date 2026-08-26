# DOMParser Testing of Vue Templates: Directive Attribute Gotcha

**Date:** 2026-07-31
**Session:** 2026-07-31-001 (Mobile Touch Enhancements Phase 3: Bottom Sheet Title Controls)

## Summary

When using `DOMParser` to test Vue template structure in unit tests, Vue directive attributes (prefixed with `:`) are parsed as literal attribute names with the colon. Standard `getAttribute()` calls on the directive name (without colon) return `null`.

---

## The Gotcha

When you parse an `index.html` file containing Vue directives using `DOMParser`, the parser treats the HTML literally — it does not evaluate Vue bindings. Vue directive attributes like `:aria-pressed`, `:class`, `:disabled`, and `:value` become literal attribute names with the colon prefix:

```javascript
// index.html contains:
// <button :aria-pressed="isTitleFormatActive('bold')">Bold</button>

const parser = new DOMParser();
const doc = parser.parseFromString(html, 'text/html');
const btn = doc.querySelector('button[title="Bold"]');

// WRONG — returns null because the attribute name is ":aria-pressed", not "aria-pressed"
btn.getAttribute('aria-pressed'); // → null

// CORRECT — use the literal attribute name with colon
btn.getAttribute(':aria-pressed'); // → "isTitleFormatActive('bold')"

// CORRECT — check for attribute presence
btn.hasAttribute(':aria-pressed'); // → true
```

## Why This Happens

`DOMParser` is a standard HTML parser that processes the document as static HTML. It has no knowledge of Vue.js or any framework. The colon prefix (`:`) is a Vue shorthand for `v-bind:`, and the parser treats it as part of the attribute name.

## Testing Strategies

### Strategy 1: Search inner HTML for binding strings

For testing that a specific Vue binding exists:

```javascript
const html = editPanel.innerHTML;
expect(html).to.include('toggleTitleBold');
expect(html).to.include(':aria-pressed="isTitleFormatActive');
```

This is simple and works well for verifying the presence of method references and binding patterns.

### Strategy 2: Use regex on inner HTML

For testing specific binding values:

```javascript
const ariaPressedMatches = html.match(/:aria-pressed="isTitleFormatActive\(['"]bold['"]\)"/g);
expect(ariaPressedMatches).to.not.be.null;
```

### Strategy 3: Query with colon-prefixed attribute names

For testing attribute presence on specific elements:

```javascript
const btn = doc.querySelector('.format-btn[title="Bold"]');
expect(btn.hasAttribute(':aria-pressed')).to.equal(true);
expect(btn.getAttribute(':aria-pressed')).to.equal("isTitleFormatActive('bold')");
```

## What NOT to Do

```javascript
// DON'T — these will always return null on Vue templates parsed by DOMParser
element.getAttribute('aria-pressed');    // Vue uses :aria-pressed
element.getAttribute('class');           // Vue uses :class
element.getAttribute('disabled');        // Vue uses :disabled
element.getAttribute('value');           // Vue uses :value
```

## When This Applies

This gotcha applies whenever you use `DOMParser` to parse Vue template HTML in tests:
- DOM structure tests that verify element attributes
- Accessibility tests checking ARIA attribute presence
- Template parity tests comparing mobile vs desktop controls

It does NOT apply when testing with Playwright (which renders the Vue app in a real browser) or when testing compiled/rendered output.

## File References

- `MyComponents/BottomSheetTitleControlsTest.html` — BSC-05 test demonstrating the gotcha and fix
- `MyComponents/BottomSheetTest.html` — BS-ADJ-DOM-01 through BS-ADJ-DOM-03 use DOMParser for structure tests
