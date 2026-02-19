# Python Style Guide

## Contents
- Prerequisites
- Import conventions
- Code formatting
- Linting and suppression
- Common pitfalls

## Prerequisites

- Python 3.8+
- `pylint` (`pip install pylint`)
- Optional: `black` or `pyink` for auto-formatting

## Import Conventions

### Import Order
```python
# Standard library
import absl.flags

# Third-party
from doctor.who import jodie

# Local modules
from myapp.utils import helper
```

### Absolute Imports Preferred
```python
# ✅ Good
from myapp.utils import helper

# ⚠️ Avoid (can lead to duplicates)
from . import helper
```

## Code Formatting

### Line Length
- 80 characters per line

```python
# ✅ Good - line continuation
def example_function(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8):
    """Example function."""
    return (
        arg1 + arg2 + arg3
        + arg4 + arg5 + arg6 + arg7 + arg8
    )
```

### Function Arguments
```python
def process_data(data, options=None, debug=False):
    """Process data with optional configuration."""
    pass
```

## Linting and Suppression

### Running Pylint
```bash
pip install pylint
pylint my_module.py
```

### Suppression Comments
```python
def do_PUT(self):  # pylint: disable=invalid-name
    # WSGI name, so pylint: disable=invalid-name
    pass
```

### Suppress Pattern
```python
# 1. Review warning and decide if suppress or fix
# 2. Use # pylint: disable=<msg-id> on specific line
# 3. Add comment explaining false positives
```

## Naming Conventions

| Element | Case | Example |
|---------|------|---------|
| Functions, variables | `lower_snake_case` | `process_data`, `user_id` |
| Classes | `UpperCamelCase` | `UserDataProcessor` |
| Constants | `UPPER_CASE` | `MAX_RETRIES` |

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| Too many warnings | Review each, suppress or fix |
| Relative imports | Use absolute paths |
| Line length exceeded | Use parentheses for continuation |

## Auto-Formatting

```bash
black --line-length 80 .
```

## Configuration

- **URL**: https://google.github.io/styleguide/pyguide.html
- **Command**: `pylint my_module.py`
- **Option**: `--max-line-length 80`
