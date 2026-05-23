# TypeScript Style Guide

## Contents
- Prerequisites
- File structure and imports
- Naming conventions
- Type safety
- Code formatting
- Common pitfalls

## Prerequisites

- Node.js 18+
- TypeScript 5.x
- ESLint with Google TypeScript ruleset
- Prettier configured for TypeScript

## File Structure and Imports

### File Header
```ts
/**
 * @fileoverview Description of file.
 */

import { Foo } from './foo';
import * as bar from './bar';
import 'side-effect-lib';
```

### Import Order
1. Side-effect imports (no exports)
2. Named imports
3. Namespace imports

### Export Patterns
```ts
// ✅ Good - named exports
export class MyClass { /* ... */ }
export const MY_CONST = 42;
export function myFunc(): void { /* ... */ }

// ❌ Avoid - default exports
export default class MyClass { /* ... */ }
```

## Naming Conventions

| Element | Case | Example |
|---------|------|---------|
| Classes, interfaces, enums | `UpperCamelCase` | `UserService`, `UserProfile` |
| Variables, functions, methods | `lowerCamelCase` | `get_user`, `addUser` |
| Constants | `CONSTANT_CASE` | `MAX_RETRIES` |

## Type Safety

### Prefer `unknown` over `any`
```ts
// ❌ Bad
const data: any = fetchData();

// ✅ Good
const data: unknown = fetchData();
```

### Use interfaces over type aliases for objects
```ts
// ✅ Good
interface User {
  id: string;
  name: string;
}

// ⚠️ Use type alias for unions/complex types
type UserID = string;
type UserAction = 'create' | 'read' | 'update' | 'delete';
```

### Use `readonly` for immutable properties
```ts
export class UserService {
  private readonly users: User[] = [];
}
```

## Code Formatting

### String Quotes
```ts
// ✅ Use single quotes
const msg = 'Hello, world!';
```

### JSDoc for Public APIs
```ts
/**
 * Calculates the sum of two numbers.
 * @param a First number.
 * @param b Second number.
 * @returns Sum of a and b.
 */
export function add(a: number, b: number): number {
  return a + b;
}
```

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| `TS2614: Module has no exported member` | Use `import { member } from './module'` for named exports |
| Default export import errors | Import as `import member from './module'` |
| Type widening with `const x = []` | Annotate: `const x: number[] = []` |

## Linting

```bash
npx eslint src/**/*.ts
npx tsc --noEmit
npx eslint src/**/*.ts --fix
```

## Configuration

- **URL**: https://github.com/google/ts-style-guide
- **Command**: `npx eslint src/**/*.ts --fix`
- **Option**: `--max-warnings 0`
