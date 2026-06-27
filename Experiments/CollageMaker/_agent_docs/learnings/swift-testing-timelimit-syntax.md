# Swift Testing Time Limit Syntax

## Overview

Swift Testing's `.timeLimit()` trait requires time values to be specified in **minutes**, not seconds. This is a common source of compilation errors when porting test documentation or plans that specify time limits in seconds.

## Incorrect Usage (Compilation Error)

```swift
@Test(.timeLimit(.seconds(30))) func layoutWithFiftyImages() async throws {
    // ...
}
```

**Error message:**
```
error: 'seconds' is unavailable: Time limit must be specified in minutes
Testing.TimeLimitTrait.Duration.seconds:4:24: note: 'seconds' has been explicitly marked unavailable here
    public static func seconds(_ seconds: some BinaryInteger) -> TimeLimitTrait.Duration  }
```

## Correct Usage

```swift
@Test(.timeLimit(.minutes(1))) func layoutWithFiftyImages() async throws {
    // ...
}
```

For shorter time limits, use fractional minutes:

```swift
// 30 seconds = 0.5 minutes
@Test(.timeLimit(.minutes(0.5))) func quickTest() async throws {
    // ...
}
```

## Reference

- Swift Testing framework `TimeLimitTrait.Duration` API
- Xcode 26.5 / Swift 6.3.2 compiler behavior
