# Mocha/Chai Browser Testing Pattern

**Date:** 2026-07-02
**Session:** 6 (P0 test implementation)

## Summary

The project uses Mocha + Chai loaded via CDN for in-browser unit tests. Test files are standalone HTML pages that import ES modules and run tests in the browser console.

## Pattern

### Test HTML Structure

```html
<!DOCTYPE html>
<html>
<head>
    <script src="https://unpkg.com/mocha@10.2.0/mocha.js"></script>
    <script src="https://unpkg.com/chai@4.3.10/chai.js"></script>
    <link rel="stylesheet" href="https://unpkg.com/mocha@10.2.0/mocha.css">
    <script>
        mocha.setup('bdd');
    </script>
</head>
<body>
    <div id="mocha"></div>
    <script type="module">
        import { FitMath } from '../../MyESModules/Layout/FitMath.js';
        const { expect } = chai;

        describe('FitMath', () => {
            describe('fit()', () => {
                it('landscape image in portrait container', () => {
                    const result = FitMath.fit(
                        { width: 1920, height: 1080 },
                        { width: 400, height: 600 }
                    );
                    expect(result.height).to.equal(600);
                });
            });
        });

        mocha.run();
    </script>
</body>
</html>
```

### Key Points

1. **`type="module"`** — Required to use ES module imports in the test script
2. **CDN loading** — Mocha and Chai are loaded from CDN, no npm install needed
3. **`mocha.setup('bdd')** — Must be called before any `describe`/`it` blocks
4. **`mocha.run()`** — Must be called after all test definitions to execute tests
5. **Relative imports** — ES module imports use relative paths from the test HTML file location

## Test File Organization

Test files live in `MyComponents/` (matching the Midiestro convention):

```
MyComponents/
├── LayoutMathTest.html      # 93 tests — FitMath, SeededPRNG, PolygonClipper, all 5 layouts
├── UndoManagerTest.html     # 20 tests — full lifecycle, batching, stack bounds
└── EdgeCasesTest.html       # 37 tests — edge cases across all modules
```

## Gotchas

1. **CORS for ES modules** — Browsers enforce CORS on ES module imports. Tests must run on a local server (`start-server.sh`), not via `file://` protocol.
2. **`mocha.run()` timing** — If `mocha.run()` is called before all `describe` blocks are defined, those tests won't run. Place it at the end of the script.
3. **No test runner** — There's no `npm test` command. Tests are run by opening the HTML file in a browser or using a headless browser script.
4. **Console output** — Test results appear in the browser console and on the page. Use browser devtools to see failures.

## Running Tests

```bash
# Start dev server
bash start-server.sh

# Open test file in browser
open http://localhost:8000/CollageMaker/MyComponents/LayoutMathTest.html

# Or run via node script (if available)
node scripts/run-tests.js
```
