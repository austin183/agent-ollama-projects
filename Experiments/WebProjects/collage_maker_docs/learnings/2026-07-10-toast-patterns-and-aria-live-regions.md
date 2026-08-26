# Toast Notification Pattern and ARIA Live Region Choices

**Date:** 2026-07-10
**Session:** 62 (Phase 1 Follow-Up: Saliency Toast + Shortcut Discoverability)

## Summary

Implemented a shared toast notification system for the CollageMaker app, wiring it to the saliency analyzer's `onModelsFailed` callback. Also added keyboard shortcut discoverability hints. Key learnings around toast timer lifecycle management and ARIA live region semantics.

---

## Toast Notification Pattern for Vue 3 Options API

A minimal toast system using reactive state + `setTimeout` for auto-dismiss. No dedicated component — just data, a method, and a template element.

### Reactive State (in `createCollageData.js`)

```javascript
toast: {
    message: '',
    type: '',       // 'info', 'success', 'error'
    visible: false,
    timer: null
},
```

### Method (in `createCollageMethods.js`)

```javascript
showToast(message, type, duration) {
    type = type || 'info';
    duration = duration != null ? duration : 5000;
    if (this.toast.timer) {
        clearTimeout(this.toast.timer);
    }
    this.toast.message = message;
    this.toast.type = type;
    this.toast.visible = true;
    this.toast.timer = setTimeout(() => {
        this.toast.visible = false;
        this.toast.message = '';
        this.toast.timer = null;
    }, duration);
},
```

### Template (in `index.html`)

```html
<div class="toast-notification"
     v-show="toast.visible"
     :class="'toast-' + toast.type"
     role="status"
     aria-live="polite">
    <span class="material-icons" aria-hidden="true">
        {{ toast.type === 'error' ? 'error' : 'info' }}
    </span>
    {{ toast.message }}
</div>
```

### Key Gotchas

1. **Timer cleanup in `beforeUnmount()`** — If the Vue component unmounts while a toast timer is active, the `setTimeout` callback will try to update reactive state on a destroyed instance. Always clear the timer in the cleanup lifecycle hook:

   ```javascript
   beforeUnmount() {
       if (this.toast && this.toast.timer) {
           clearTimeout(this.toast.timer);
           this.toast.timer = null;
       }
   }
   ```

2. **Toast coalescing** — Rapid successive calls to `showToast()` clear the previous timer and overwrite the message. Only the last message is shown. This prevents toast spam but means quick successive errors are lost. Document this behavior.

3. **`v-show` with CSS transitions** — `v-show` toggles `display: none`, which cannot be CSS-transitioned. The `transition: opacity` in the CSS has no effect. For fade animations, use `v-if` with `<transition>` or bind `visibility` + `opacity` via inline styles. For simple toasts, `v-show` is acceptable (instant show/hide).

4. **Mobile safe areas** — Use `calc(16px + env(safe-area-inset-bottom, 0px))` for bottom-positioned fixed elements to avoid iOS home indicator overlap.

---

## ARIA Live Region Selection: `role="status"` vs `role="alert"`

For toast notifications, choosing the right ARIA role matters for screen reader behavior:

| Role | Implicit `aria-live` | Behavior | Use when |
|------|---------------------|----------|----------|
| `role="status"` | `polite` | Announces when user is idle | Info messages, success confirmations |
| `role="alert"` | `assertive` | Interrupts immediately | Critical errors, security warnings |

### Rule of Thumb

- **Info toasts** (like "AI features unavailable — using default focus"): Use `role="status" aria-live="polite"`. The message is informational and doesn't require immediate attention.
- **Error toasts** (like "Export failed: ..."): Consider `role="alert"` for critical errors that block the user's workflow. For non-blocking errors, `role="status"` is fine.
- **Success toasts** (like "Collage exported!"): Use `role="status" aria-live="polite"`.

### Anti-Pattern

Do NOT combine `role="alert"` with `aria-live="polite"` — they contradict each other. `role="alert"` implicitly sets `aria-live="assertive"`. Adding `aria-live="polite"` creates invalid ARIA that may confuse screen readers.

### Decorative Icons

Always add `aria-hidden="true"` to decorative icons inside live regions. Screen readers will read the icon text content ("error" or "info") which duplicates the message meaning.

---

## Deferred Feature Activation Pattern

The saliency analyzer (`createSaliencyAnalyzer`) was created as a deferred feature — the factory existed but wasn't wired into the Vue app. The `beforeUnmount()` lifecycle hook already referenced `this._saliencyAnalyzer.dispose()` as a placeholder.

**Pattern:** When wiring a deferred feature:
1. Check `beforeUnmount()` for existing disposal references
2. Create the instance in `mounted()` with callback wiring
3. The disposal reference in `beforeUnmount()` handles cleanup automatically

**File references:**
- `MyESModules/Saliency/SaliencyAnalyzer.js` — factory
- `MyESModules/App/createCollageLifecycle.js` — wiring point

---

## Testing

Test file: `MyComponents/ToastNotificationTest.html` (10 tests, 23 assertions)

Key test patterns:
- **State initialization**: Verify `toast.message`, `toast.type`, `toast.visible`, `toast.timer` defaults
- **Timer auto-dismiss**: Use real `setTimeout` with short duration (50ms) + async test callback
- **Timer coalescing**: Call `showToast` twice, verify first timer is cleared and only second timer fires
- **Saliency wiring**: Mock `window.Worker` to throw on construction, verify `onModelsFailed` callback fires

## File References

- `MyESModules/App/createCollageData.js` — toast reactive state
- `MyESModules/App/createCollageMethods.js` — `showToast()` method
- `MyESModules/App/createCollageLifecycle.js` — saliency analyzer wiring + timer cleanup
- `index.html` — toast template + layout shortcut hint
- `Style.css` — toast styles + shortcut hint styles
- `MyComponents/ToastNotificationTest.html` — unit tests
