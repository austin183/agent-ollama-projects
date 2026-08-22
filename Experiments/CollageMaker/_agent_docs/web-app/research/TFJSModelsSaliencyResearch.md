# TensorFlow.js Models — Saliency Detection Research

**Date:** 2026-06-30  
**Source:** Analysis of `@tensorflow-models` repo (`~/workspace/References/tfjs-models`)  
**Target:** Replacing Apple Vision saliency analysis in CollageMaker web port

---

## 1. Executive Summary

**There is no dedicated saliency detection model in the TensorFlow.js models repository.** Apple's `VNGenerateAttentionBasedSaliencyImageRequest` (used in CollageMaker's `SaliencyAnalyzer.swift`) has no direct tfjs equivalent.

However, **four models can serve as saliency proxies** by identifying visually important regions (people, faces, objects) and deriving a focal point from their output:

| Approach | Model | Saliency Signal | Load Size (est.) | Inference Speed |
|----------|-------|-----------------|------------------|-----------------|
| Object detection | `coco-ssd` | Bounding box centers of detected objects | ~6 MB | Fast (~200ms) |
| Semantic segmentation | `deeplab` (PASCAL) | Per-pixel class map, weight "person"/"face"/"animal" pixels | ~10 MB | Slow (~1-2s) |
| Face detection | `face-detection` | Face bounding box centers (faces = highly salient) | ~3 MB | Fast (~100ms) |
| Body segmentation | `body-segmentation` | Person mask centroid | ~5 MB | Medium (~300ms) |

**Recommendation:** Use a **combined heuristic** — coco-ssd for general objects + face-detection for faces — with a center-weighted fallback. This balances coverage, speed, and bundle size.

---

## 2. Repository Overview

The `tfjs-models` repo (`github.com/tensorflow/tfjs-models`) hosts pre-trained TensorFlow.js models available on NPM and CDN (unpkg/jsdelivr). All models accept `<img>`, `<canvas>`, `<video>`, `ImageData`, or `tf.Tensor3D` as input.

### 2.1 Available Models (from repo README)

| Model | NPM Package | Type | Relevance to Saliency |
|-------|-------------|------|----------------------|
| MobileNet | `@tensorflow-models/mobilenet` | Image classification | Low — single label, no spatial info |
| **Coco SSD** | `@tensorflow-models/coco-ssd` | **Object detection** | **High — bounding boxes with spatial location** |
| **DeepLab v3** | `@tensorflow-models/deeplab` | **Semantic segmentation** | **High — per-pixel class labels** |
| **Face Detection** | `@tensorflow-models/face-detection` | **Face detection** | **High — faces are highly salient** |
| **Body Segmentation** | `@tensorflow-models/body-segmentation` | **Body segmentation** | **Medium — person masks** |
| Depth Estimation | `@tensorflow-models/depth-estimation` | Depth map | Low — portrait-only, narrow scope |
| Pose Detection | `@tensorflow-models/pose-detection` | Human pose | Low — skeleton keypoints only |
| Hand Pose | `@tensorflow-models/hand-pose-detection` | Hand tracking | Low — too specific |
| KNN Classifier | `@tensorflow-models/knn-classifier` | Transfer learning utility | N/A |

### 2.2 Models NOT Relevant for Saliency

- **MobileNet** — Returns a single classification (e.g., "Egyptian cat"), no spatial information
- **GPT-2** — Text generation
- **QnA** — Question answering
- **Universal Sentence Encoder** — Text embeddings
- **Toxicity** — Text toxicity scoring
- **Speech Commands** — Audio classification
- **Pose/Hand/Face Landmarks** — Too narrow in scope (only human anatomy)

---

## 3. Detailed Analysis of Saliency-Candidate Models

### 3.1 Coco SSD — Object Detection

**Best general-purpose saliency proxy.**

#### How It Works
Detects up to 80 object classes with bounding boxes and confidence scores:
```js
const model = await cocoSsd.load();
const predictions = await model.detect(image);
// Returns: [{ bbox: [x, y, w, h], class: "person", score: 0.84 }, ...]
```

#### 80 COCO Classes (from `coco-ssd/src/classes.ts`)
The most salient classes for collage purposes:
- **People:** person
- **Animals:** cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe, bird
- **Vehicles:** car, bus, truck, airplane, train, motorcycle, bicycle, boat
- **Food:** pizza, cake, donut, sandwich, apple, banana, carrot, etc.
- **Objects:** laptop, cell phone, TV, book, clock, vase, scissors, teddy bear

#### Saliency Derivation
For each detected object, compute a **saliency score**:
```
saliency = score * area_weight * class_weight
```
- `score` = model confidence (0–1)
- `area_weight` = larger objects tend to be more important
- `class_weight` = people/animals get higher weight than inanimate objects

The focal point is the **weighted centroid** of all detected object centers.

#### Loading Options
```js
// Smallest/fastest
cocoSsd.load({ base: 'lite_mobilenet_v2' })  // ~6 MB

// Best accuracy
cocoSsd.load({ base: 'mobilenet_v2' })       // ~13 MB
```

#### CDN Loading (no build step needed)
```html
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs"></script>
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd"></script>
<script>
  cocoSsd.load().then(model => model.detect(img));
</script>
```

#### Pros
- ✅ 80 classes cover most photo subjects
- ✅ Fast inference (~200ms on modern hardware)
- ✅ Reasonable model size (~6 MB for lite variant)
- ✅ Simple bounding box output, easy to compute focal point
- ✅ Works via CDN script tags (no build step)

#### Cons
- ❌ Misses non-COCO objects (landscapes, abstract art, patterns)
- ❌ Bounding boxes are coarse — not pixel-level precision
- ❌ TensorFlow.js core is a large dependency (~400 KB minified)

---

### 3.2 DeepLab v3 — Semantic Segmentation

**Most precise but heaviest option.**

#### How It Works
Assigns a semantic class label to every pixel in the image:
```js
const model = await deeplab.load({ base: 'pascal', quantizationBytes: 2 });
const output = await model.segment(image);
// Returns: { legend, height, width, segmentationMap: Uint8ClampedArray }
```

The `segmentationMap` is a per-pixel color-coded image where each color corresponds to a class.

#### Available Models and Classes

**PASCAL VOC (20 classes)** — Smallest model, recommended:
- background, aeroplane, bicycle, bird, boat, bottle, bus, car, cat, chair, cow, dining table, dog, horse, motorbike, **person**, potted plant, sheep, sofa, train, TV

**Cityscapes (19 classes)** — Street scenes only:
- road, sidewalk, building, wall, fence, pole, traffic light, traffic sign, vegetation, terrain, sky, **person**, rider, car, truck, bus, train, motorcycle, bicycle

**ADE20K (150 classes)** — Most detailed, largest model:
- All PASCAL classes + wall, sky, floor, tree, ceiling, bed, window, grass, cabinet, sidewalk, earth, door, table, mountain, plant, curtain, water, painting, shelf, house, sea, mirror, rug, field, armchair, etc.

#### Saliency Derivation
Create a **saliency heatmap** from the segmentation map:
```js
// Define class saliency weights
const saliencyWeights = {
  'person': 1.0,      // Highest — people are always salient
  'cat': 0.9,         // Pets are salient
  'dog': 0.9,
  'bird': 0.8,
  'horse': 0.8,
  'car': 0.6,         // Vehicles are moderately salient
  'bicycle': 0.5,
  'background': 0.0,  // Background is not salient
  // ... default 0.3 for unlisted classes
};

// For each pixel, look up its class and assign saliency weight
// Then compute weighted centroid of all salient pixels
```

#### Loading Options
```js
// PASCAL — smallest, 20 classes
deeplab.load({ base: 'pascal', quantizationBytes: 2 })  // ~10 MB

// ADE20K — most detailed, 150 classes
deeplab.load({ base: 'ade20k', quantizationBytes: 2 })  // ~15+ MB
```

#### CDN Loading
⚠️ **DeepLab requires `@tensorflow/tfjs-converter` as a peer dependency**, making CDN loading more complex:
```html
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs"></script>
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-converter"></script>
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/deeplab"></script>
```

#### Pros
- ✅ Per-pixel precision — most accurate saliency map
- ✅ Can weight different classes by importance
- ✅ ADE20K has 150 classes for broad coverage

#### Cons
- ❌ **Heavy** — ~10-15 MB model + TF.js dependencies
- ❌ **Slow** — 1-2 seconds per image on typical hardware
- ❌ **Complex output** — requires interpreting pixel-level segmentation map
- ❌ **Requires build tool** — demo uses Parcel bundler, not pure script tags
- ❌ **Resource-intensive** — repo warns Cityscapes model may crash browsers
- ❌ Older TF.js version (^3.0.0) — may conflict with newer models

---

### 3.3 Face Detection

**Best for portrait photos.**

#### How It Works
Detects faces with bounding boxes and 6 keypoints (eyes, nose, mouth, ears):
```js
const detector = await faceDetection.createDetector(
  faceDetection.SupportedModels.MediaPipeFaceDetector,
  { runtime: 'mediapipe' }
);
const faces = await detector.estimateFaces(image);
// Returns: [{ box: { xMin, yMin, width, height }, keypoints: [...] }, ...]
```

#### Saliency Derivation
Faces are among the most salient features in any image. For each detected face:
- Use the **center of the face bounding box** as a focal point
- If multiple faces, use the **weighted average** of all face centers
- Can use **keypoints** (eyes) for even more precise focal point

#### Loading
```js
// MediaPipe runtime (lighter, faster)
faceDetection.SupportedModels.MediaPipeFaceDetector
// TF.js runtime (heavier)
faceDetection.SupportedModels.MediaPipeFaceDetector with runtime: 'tfjs'
```

#### Pros
- ✅ Faces are universally salient
- ✅ Very fast (~100ms)
- ✅ Small model (~3 MB)
- ✅ Keypoints provide precise focal point (between eyes)
- ✅ Multi-face support

#### Cons
- ❌ Only detects faces — useless for landscapes, objects, abstract art
- ❌ Requires `@mediapipe/face_detection` peer dependency
- ❌ Narrow scope — only useful as part of a combined approach

---

### 3.4 Body Segmentation

**Good for person-centric photos.**

#### How It Works
Segments all pixels belonging to people from the background:
```js
const segmenter = await bodySegmentation.createSegmenter(
  bodySegmentation.SupportedModels.MediaPipeSelfieSegmentation
);
const segmentation = await segmenter.segmentPeople(image);
// Returns: [{ mask: { toImageData(), toTensor(), ... }, maskValueToLabel }]
```

#### Saliency Derivation
- Convert mask to binary (person vs. background)
- Compute **centroid of all person pixels** as focal point
- Can use `toBinaryMask()` utility for clean person silhouette

#### Two Model Options:
- **MediaPipe SelfieSegmentation** — Fast, one mask for all people
- **BodyPix** — Slower, can segment 24 body parts individually

#### Pros
- ✅ Person mask provides precise spatial information
- ✅ Handles multiple people
- ✅ BodyPix can distinguish body parts for finer focal points

#### Cons
- ❌ Only detects people — not useful for landscapes/objects
- ❌ Requires `@mediapipe/selfie_segmentation` peer dependency
- ❌ Medium model size (~5 MB)
- ❌ SelfieSegmentation is optimized for close-range portraits (< 2m)

---

### 3.5 Depth Estimation

**Limited usefulness for saliency.**

#### How It Works
Estimates per-pixel depth for portrait images:
```js
const estimator = await depthEstimation.createEstimator(
  depthEstimation.SupportedModels.ARPortraitDepth
);
const depthMap = await estimator.estimateDepth(image, { minDepth: 0, maxDepth: 1 });
```

#### Saliency Derivation
Closer objects are typically more salient. The depth map could be inverted to create a saliency heatmap.

#### Cons
- ❌ **Portrait-only** — only works for person photos
- ❌ Narrow scope, not general-purpose
- ❌ Depth ≠ saliency (a small distant object can be highly salient)

**Verdict: Not recommended for CollageMaker saliency.**

---

## 4. Recommended Architecture

### 4.1 Combined Saliency Pipeline

Given that no single model covers all cases, the recommended approach is a **tiered saliency pipeline**:

```
Image Input
    │
    ▼
┌─────────────────────────┐
│  Tier 1: Face Detection │  ← Fastest, most salient
│  (face-detection model) │  ← ~100ms, ~3 MB
└─────────┬───────────────┘
          │
    Faces found?
    ├─ YES → Use face center(s) as focal point(s)
    └─ NO  ▼
┌─────────────────────────┐
│  Tier 2: Object Detect  │  ← General objects
│  (coco-ssd model)       │  ← ~200ms, ~6 MB
└─────────┬───────────────┘
          │
    Objects found?
    ├─ YES → Use weighted centroid of object boxes
    └─ NO  ▼
┌─────────────────────────┐
│  Tier 3: Center Fallback│  ← Pure heuristic, no ML
│  (image center + edge   │  ← Instant, 0 MB
│   weight bias)          │
└─────────────────────────┘
```

### 4.2 Why This Approach?

1. **Faces first** — Faces are the most salient feature in most photos. Face detection is fast and accurate.
2. **Objects second** — For non-portrait photos (landscapes with subjects, product photos, animals), coco-ssd catches 80 common classes.
3. **Center fallback** — For abstract art, patterns, or anything the models miss, the center of the image is a reasonable default (matches human tendency to compose around center).

### 4.3 Total Cost

| Component | Model Size | Load Time (est.) | Inference Time |
|-----------|-----------|------------------|----------------|
| TF.js core | ~400 KB (min+gzip) | ~1s on 3G | — |
| face-detection | ~3 MB | ~2s on 3G | ~100ms |
| coco-ssd (lite) | ~6 MB | ~3s on 3G | ~200ms |
| **Total (lazy load)** | **~9.4 MB** | **~3-6s total** | **~300ms max** |

**Lazy loading strategy:** Only load face-detection on first image. Only load coco-ssd if face detection finds nothing. This means many users never download coco-ssd.

### 4.4 CDN Script Tag Loading

For the static site approach (no build step), all models can be loaded via CDN:

```html
<!-- TensorFlow.js core (required by all models) -->
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0"></script>

<!-- Face detection (loaded on first image) -->
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/face-detection@1.0.3"></script>

<!-- Coco SSD (loaded only if face detection finds nothing) -->
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd@2.2.2"></script>
```

⚠️ **Caveat:** The face-detection model requires `@mediapipe/face_detection` as a peer dependency. This may need to be loaded separately or the TF.js runtime (`runtime: 'tfjs'`) used instead of MediaPipe.

---

## 5. Integration with CollageMaker

### 5.1 Replacing SaliencyAnalyzer.swift

The current macOS `SaliencyAnalyzer` is an actor that:
1. Takes a `CGImage` as input
2. Runs `VNGenerateAttentionBasedSaliencyImageRequest`
3. Returns a `SaliencyResult` with `focusPoint: CGPoint` (normalized 0-1) and `confidence: Float`

The web replacement (`SaliencyAnalyzer.js`) would:
```js
class SaliencyAnalyzer {
  constructor() {
    this.faceModel = null;
    this.cocoModel = null;
  }

  async analyze(imageElement) {
    // Tier 1: Face detection
    const faceResult = await this.tryFaceDetection(imageElement);
    if (faceResult) return faceResult;

    // Tier 2: Object detection
    const objectResult = await this.tryObjectDetection(imageElement);
    if (objectResult) return objectResult;

    // Tier 3: Center fallback
    return this.centerFallback(imageElement);
  }

  async tryFaceDetection(image) {
    if (!this.faceModel) {
      this.faceModel = await faceDetection.createDetector(
        faceDetection.SupportedModels.MediaPipeFaceDetector,
        { runtime: 'tfjs' }  // Use tfjs runtime to avoid MediaPipe dependency
      );
    }
    const faces = await this.faceModel.estimateFaces(image);
    if (faces.length === 0) return null;

    // Compute weighted center of all faces
    const centerX = faces.reduce((sum, f) => sum + (f.box.xMin + f.box.width / 2), 0) / faces.length;
    const centerY = faces.reduce((sum, f) => sum + (f.box.yMin + f.box.height / 2), 0) / faces.length;

    return {
      focusPoint: {
        x: centerX / image.naturalWidth,   // Normalize to 0-1
        y: centerY / image.naturalHeight
      },
      confidence: 0.9,  // High confidence for face-based saliency
      method: 'face-detection'
    };
  }

  async tryObjectDetection(image) {
    if (!this.cocoModel) {
      this.cocoModel = await cocoSsd.load({ base: 'lite_mobilenet_v2' });
    }
    const detections = await this.cocoModel.detect(image);
    if (detections.length === 0) return null;

    // Weight by confidence * area * class importance
    const salientClasses = new Set(['person', 'cat', 'dog', 'bird', 'horse', 'cow', 'sheep', 'zebra', 'giraffe', 'elephant']);
    let totalWeight = 0;
    let weightedX = 0;
    let weightedY = 0;

    for (const det of detections) {
      const [x, y, w, h] = det.bbox;
      const area = w * h;
      const classWeight = salientClasses.has(det.class) ? 2.0 : 1.0;
      const weight = det.score * area * classWeight;
      weightedX += (x + w / 2) * weight;
      weightedY += (y + h / 2) * weight;
      totalWeight += weight;
    }

    return {
      focusPoint: {
        x: (weightedX / totalWeight) / image.naturalWidth,
        y: (weightedY / totalWeight) / image.naturalHeight
      },
      confidence: 0.7,  // Medium confidence for object-based saliency
      method: 'coco-ssd'
    };
  }

  centerFallback(image) {
    return {
      focusPoint: { x: 0.5, y: 0.5 },
      confidence: 0.3,  // Low confidence for fallback
      method: 'center-fallback'
    };
  }
}
```

### 5.2 Mapping to CollageMaker's Crop System

The `SaliencyResult.focusPoint` is used by `LayoutManager` to position the default crop so the focal region is centered in the panel. The web version would:

1. Load image → get `HTMLImageElement`
2. Run `SaliencyAnalyzer.analyze(image)` → get `{ focusPoint, confidence, method }`
3. Use `focusPoint` to compute `CropInfo.sourceRect` that centers the focal point within the panel frame
4. This is the same math as `FitMath.swift` — pure computation, already portable

### 5.3 Performance Considerations

| Scenario | Images | Analysis Time | Notes |
|----------|--------|---------------|-------|
| Single image | 1 | ~100-300ms | Face or object detected |
| Multiple images | N | ~100-300ms × N | Sequential analysis |
| All center fallback | N | ~0ms | No ML models loaded |
| Lazy loading | First image | +3-6s for model download | One-time cost |

**Optimization ideas:**
- **Web Worker:** Run TF.js inference in a Web Worker to avoid blocking the main thread
- **Caching:** Cache saliency results per image (e.g., in a Map keyed by image data URL hash)
- **Throttling:** Analyze images as they're loaded, not all at once
- **Progressive:** Show center-cropped preview immediately, update to ML-based crop when analysis completes

---

## 6. Alternative: Skip ML Entirely (MVP Approach)

For the initial MVP, consider **skipping ML-based saliency entirely**:

### 6.1 Center-Weighted Heuristic

```js
function computeSaliencyFallback(imageWidth, imageHeight) {
  // Human attention tends toward center and upper-third (rule of thirds)
  return {
    focusPoint: { x: 0.5, y: 0.4 },  // Slightly above center
    confidence: 0.3,
    method: 'heuristic'
  };
}
```

### 6.2 Edge Detection via Canvas

A lightweight alternative using Canvas pixel analysis (no ML):
```js
function computeEdgeBasedSaliency(canvas) {
  const ctx = canvas.getContext('2d');
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  // Apply Sobel edge detection
  // Compute gradient magnitude at each pixel
  // Weighted centroid of high-gradient regions = focal point
}
```

This would be ~50 lines of pure JavaScript, zero dependencies, and instant execution.

### 6.3 Recommendation for MVP

**Start with center-weighted heuristic.** Add ML-based saliency as a Phase 4 enhancement. The macOS app's saliency analysis is a "nice-to-have" that improves default crops — the web app can function well without it since users can manually adjust crops.

---

## 7. Comparison with Apple Vision Framework

| Aspect | Apple Vision | TF.js Approach |
|--------|-------------|----------------|
| API | `VNGenerateAttentionBasedSaliencyImageRequest` | Custom pipeline (face + object detection) |
| Output | Per-pixel attention heatmap | Focal point coordinates |
| Speed | Hardware-accelerated, ~50ms | Software, ~100-300ms |
| Model size | Built into OS | 3-9 MB downloaded |
| Coverage | General attention (color, contrast, faces) | Face + object detection proxy |
| Availability | macOS/iOS only | Any modern browser |
| Accuracy | High (trained on attention data) | Medium (proxy, not true saliency) |
| Offline | Always available | Requires initial download |

---

## 8. Decision Matrix

| Factor | coco-ssd | DeepLab | Face Detection | Combined | No ML |
|--------|----------|---------|----------------|----------|-------|
| Coverage | Good (80 classes) | Best (per-pixel) | Narrow (faces only) | Best | None |
| Speed | Fast | Slow | Fast | Medium | Instant |
| Size | ~6 MB | ~10 MB | ~3 MB | ~9 MB | 0 MB |
| CDN support | Yes | Complex | Partial | Complex | N/A |
| Build step | No | Needs Parcel | No | No | No |
| Accuracy | Medium | High | High (for faces) | Good | Low |
| **Overall fit** | **Good** | Too heavy | Too narrow | **Best long-term** | **Best for MVP** |

---

## 9. Files Referenced

- `/Users/austin/workspace/References/tfjs-models/README.md` — Model catalog
- `/Users/austin/workspace/References/tfjs-models/coco-ssd/README.md` — Coco SSD docs
- `/Users/austin/workspace/References/tfjs-models/coco-ssd/src/classes.ts` — 80 COCO classes
- `/Users/austin/workspace/References/tfjs-models/coco-ssd/package.json` — Dependencies
- `/Users/austin/workspace/References/tfjs-models/coco-ssd/demo/index.js` — Usage example
- `/Users/austin/workspace/References/tfjs-models/deeplab/README.md` — DeepLab docs
- `/Users/austin/workspace/References/tfjs-models/deeplab/src/config.ts` — PASCAL/Cityscapes/ADE20K labels
- `/Users/austin/workspace/References/tfjs-models/deeplab/demo/src/index.js` — DeepLab usage example
- `/Users/austin/workspace/References/tfjs-models/face-detection/README.md` — Face detection docs
- `/Users/austin/workspace/References/tfjs-models/body-segmentation/README.md` — Body segmentation docs
- `/Users/austin/workspace/References/tfjs-models/depth-estimation/README.md` — Depth estimation docs
- `/Users/austin/workspace/References/tfjs-models/mobilenet/README.md` — MobileNet (for comparison)
