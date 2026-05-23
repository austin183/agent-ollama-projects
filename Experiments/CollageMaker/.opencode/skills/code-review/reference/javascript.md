# JavaScript Style Guide

## Contents
- Prerequisites
- File structure and formatting
- Naming conventions
- Code patterns
- Common pitfalls

## Prerequisites

- A JavaScript environment (Node.js or browser)
- Optional: `clang-format` configured for JavaScript
- Optional: Closure Compiler linter (`jslint` or `eslint` with Google style rules)

## File Structure

### File Naming
- Lowercase with optional underscores or dashes
- End in `.js`

```bash
touch src/utils/math_helpers.js
```

### File Header
```js
/**
 * @fileoverview Utility functions for math operations.
 * @package
 */
goog.module('src.utils.math_helpers');
```

## Formatting Rules

### Braces
- Use K&R style (opening brace on same line)

```js
function add(a, b) {
  return a + b;
}
```

### Indentation
- Two-space indentation
- No tabs

### Semicolons
- Always end statements with semicolons

### Line Length
- Follow project conventions (typically 80-120 chars)

## Naming Conventions

| Element | Case | Example |
|---------|------|---------|
| Functions, variables | `lowerCamelCase` | `add`, `getUser` |
| Constants | `UPPER_CASE` | `MAX_SIZE` |
| Classes | `UpperCamelCase` | `UserService` |

## Code Patterns

### Exports
```js
// goog.module style
exports.add = add;
exports = {add, subtract};

// ES module style
export function add(a, b) {
  return a + b;
}
```

### JSDoc Comments
```js
/**
 * Adds two numbers.
 * @param {number} a First operand.
 * @param {number} b Second operand.
 * @return {number} Sum of a and b.
 */
function add(a, b) {
  return a + b;
}
```

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| Missing semicolons | Run `eslint --fix` |
| Uppercase file names | Rename to lowercase |
| Missing `@fileoverview` | Add file documentation |

## Linting

```bash
eslint src/utils/math_helpers.js
eslint src/utils/math_helpers.js --config .eslintrc.js
```

## Configuration

- **URL**: https://google.github.io/styleguide/jsguide.html
- **Command**: `eslint src/**/*.js --config .eslintrc.js`
