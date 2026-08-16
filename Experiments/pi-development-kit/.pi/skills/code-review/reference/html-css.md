# HTML/CSS Style Guide

## Contents
- HTML structure and semantics
- CSS styling and best practices
- Code formatting and consistency
- Common pitfalls

## HTML Structure

### Doctype and Encoding
```html
<!doctype html>
<meta charset="utf-8">
```

### Tag Naming
- All lowercase
- No uppercase letters

### Optional Tags
Omit for `<link>` and `<script>`:
```html
<!-- ✅ Good -->
<link rel="stylesheet" href="style.css">
<script src="app.js"></script>

<!-- ❌ Avoid -->
<link rel="stylesheet" type="text/css" href="style.css">
<script type="text/javascript" src="app.js"></script>
```

### Semantic Elements
Use `<header>`, `<nav>`, `<article>`, `<footer>` instead of generic `<div>`s.

## CSS Styling

### Selectors
- Use class selectors over IDs
- Avoid `!important` unless absolutely necessary

```css
/* ✅ Good */
.article { margin: 0 1em 2em; }
.title   { font-size: 1.5em; }

/* ❌ Avoid */
#article { margin: 0 1em 2em; }
.title   { font-size: 1.5em !important; }
```

### Indentation
- 2-space indentation

### Commenting
```css
/* Main section styles */
.section-main {
  /* Style properties */
}
```

## Code Formatting

### Attribute Ordering (Recommended)
1. `class`
2. `id`
3. `data-*`
4. `aria-*`
5. Other attributes

### Line Length
- Keep lines under 80 characters when possible

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| Quirks mode rendering | Ensure `<!doctype html>` is first line |
| Inline styles | Use CSS classes instead |
| ID selector pollution | Use classes for reusability |
| !important abuse | Increase specificity naturally |

## Validation

- HTML: W3C HTML Validator
- CSS: W3C CSS Validator

## Linting

```bash
# HTML
npx htmlhint --config .htmlhintrc

# CSS
npx stylelint "**/*.css"
```

## Configuration

- **URL**: https://google.github.io/styleguide/htmlcssguide.html
- **Command**: `npm run lint` (if using a linter)
- **Option**: `--fix` to automatically format code
