# Implement Saliency Model Initialization Timeout

`MyESModules/Saliency/SaliencyAnalyzer.js` defines `INFERENCE_TIMEOUT_MS: 15000` in `SALIENCY_CONFIG` but never uses it. If TF.js models fail to load or the Web Worker hangs, the app will be stuck in `state === 'loading'` indefinitely with no fallback.

## Change

In `createSaliencyAnalyzer`, add a timeout guard in `initModels()`:

- Start a `setTimeout` for `SALIENCY_CONFIG.INFER_TIMEOUT_MS` when model loading begins
- If the timer fires while `state === 'loading'`, transition to `state === 'failed'` and fire `onModelsFailed` with a timeout message
- Clear the timeout in the `MODELS_READY` and `MODELS_FAILED` message handlers
- Clear the timeout in `dispose()` to prevent stale callbacks

## Testing

Add a test to `MyComponents/SaliencyTest.html` that verifies the timeout fires when models never respond.
