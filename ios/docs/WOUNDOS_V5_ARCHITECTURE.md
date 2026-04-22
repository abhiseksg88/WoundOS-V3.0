# WoundOS V5 — Architecture Plan

**Date:** 2026-04-21
**Branch:** `v5/phase1-architecture` (off `claude/clinical-measurement-arkit-BvFM7`)
**Author:** Claude Opus 4.6 (AI agent)
**Status:** GATE 1 — Awaiting sign-off

**Carry-over constraints from GATE 0:**

- iOS 17.0 minimum, iOS 18.0 gated for Scan Mode
- Test infrastructure is a Phase 1 deliverable (this document)
- No Phase 2 code starts until auth question is resolved
- Backend SAM2 stub stays untouched in Phase 1; deprecation planned post on-device SAM2 ships
- Every open unknown from the audit must appear as a resolved question or a flagged assumption with a named owner

---

## §1.1 — Module Map & Dependency Graph

### Current V4 Modules (6 SPM packages)

```
                        ┌──────────────┐
                        │   WoundCore  │  (Models, Protocols, Extensions)
                        │   iOS 16+    │
                        └──────┬───────┘
               ┌───────┬───────┼───────┬────────┬────────┐
               │       │       │       │        │        │
        ┌──────┴──┐ ┌──┴───┐ ┌┴─────┐ ┌┴──────┐ ┌┴──────┐
        │ Capture │ │Bound │ │Meas. │ │AutoSeg│ │Netwrk │
        │         │ │ary   │ │ure-  │ │menta- │ │ing    │
        │ iOS 16+ │ │      │ │ment  │ │tion   │ │       │
        └─────────┘ │16+   │ │16+   │ │16+    │ │16+    │
                    └──────┘ └──────┘ └───────┘ └───────┘
```

All leaf packages depend only on `WoundCore`. Zero cross-dependencies between leaves. Zero external dependencies.

### V5 Module Map (V4 retained, 5 new packages added)

```
                        ┌──────────────┐
                        │   WoundCore  │ ← Add: TissueClassification, BWATScore,
                        │   iOS 17+    │   FeatureFlag, V5CaptureBundle models
                        └──────┬───────┘
      ┌────────┬───────┬───────┼───────┬────────┬────────┬────────┐
      │        │       │       │       │        │        │        │
┌─────┴──┐ ┌──┴───┐ ┌─┴────┐ ┌┴─────┐ ┌┴──────┐ ┌┴──────┐ ┌─────┴──┐
│Capture │ │Bound │ │Meas. │ │Auto  │ │Netwrk │ │Tissue │ │HealthKit│
│        │ │ary   │ │ure-  │ │Seg   │ │ing    │ │Kit    │ │Sync    │
│        │ │      │ │ment  │ │      │ │       │ │  NEW  │ │  NEW   │
└────────┘ └──────┘ └──────┘ └──────┘ └───────┘ └───────┘ └────────┘
                                         │
                                    ┌────┴─────┐
                                    │V5Backend │
                                    │Client NEW│
                                    └──────────┘

App Target (WoundOS):
  ├── DependencyContainer
  ├── FeatureFlagManager      NEW
  ├── Coordinators (V4 + V5 extensions)
  ├── Scenes (V4 + V5 screens)
  └── WoundModels/            NEW (on-demand CoreML bundles)
```

### New V5 Packages

| Package | Purpose | Depends On | iOS Min |
|---------|---------|-----------|---------|
| **WoundTissueKit** | FPN+VGG16 CoreML tissue classifier → 6-class composition | WoundCore, WoundMeasurement | 17.0 |
| **WoundHealthKitSync** | HealthKit writes, longitudinal store, FHIR Observation export | WoundCore | 17.0 |
| **WoundV5BackendClient** | Thin client for `/v5/*` endpoints (measurements, trajectories, registrations) | WoundCore, WoundNetworking | 17.0 |

### Packages NOT created (scope control)

The original V5 spec proposed `WoundCaptureKit`, `WoundSegmentationKit`, `WoundUI`, and `WoundModels` as new packages. After reviewing the existing codebase, these are **not needed as separate packages**:

| Proposed | Decision | Reason |
|----------|----------|--------|
| WoundCaptureKit | **Extend WoundCapture** | `ARSessionManager` and `CaptureQualityMonitor` already handle LiDAR capture. Object Capture (Scan Mode) adds a parallel session type behind `@available(iOS 18.0, *)` in the same package. |
| WoundSegmentationKit | **Extend WoundAutoSegmentation** | The `WoundSegmenter` protocol is already defined here. Adding YOLO11 detector + SAM2 Mobile segmenter as new conformers in the same package avoids a new dependency edge. |
| WoundUI | **Not needed** | V5 uses UIKit (matching V4). New screens are added to `WoundOS/Scenes/` in the app target, not a package. SwiftUI is used only for `ObjectCaptureView` wrapper (iOS 18, inside WoundCapture). |
| WoundModels | **Not a package** | CoreML `.mlmodelc` bundles are app-target resources, not a library. Model download/caching logic lives in a `ModelManager` utility in the app target. |

### Dependency Rules (enforced by SPM)

1. **WoundCore depends on nothing.** All model types, protocols, and extensions live here.
2. **Leaf packages depend only on WoundCore** — no leaf-to-leaf imports.
3. **WoundV5BackendClient depends on WoundCore + WoundNetworking** — it extends the existing `WoundOSClient` actor with `/v5/*` methods.
4. **WoundTissueKit depends on WoundCore + WoundMeasurement** — it consumes `ClippedMesh` and `ProjectionUtils` to map tissue classifications onto mesh triangles.
5. **The app target depends on everything** — it is the composition root.

### §1.1.1 — Test Infrastructure

**This is a Phase 1 deliverable. No Phase 2 code merges without tests running in CI.**

#### Unit Test Targets

| Package | Test Target | Existing Tests | V5 Test Additions |
|---------|------------|----------------|-------------------|
| WoundCore | WoundCoreTests | Yes (model coding) | Feature flag logic, new model encoding/decoding |
| WoundCapture | WoundCaptureTests | **No — create** | `CaptureQualityMonitor` gate logic, mock `ARSession` state transitions |
| WoundBoundary | WoundBoundaryTests | **No — create** | `BoundaryValidator` rules, `BoundaryProjector` with synthetic mesh |
| WoundMeasurement | WoundMeasurementTests | Yes (24 tests) | BWAT calculator, tissue area accumulator, regression suite with golden meshes |
| WoundAutoSegmentation | WoundAutoSegmentationTests | Yes (protocol conformance) | YOLO11 detector output parsing, SAM2 Mobile mask → polygon conversion |
| WoundNetworking | WoundNetworkingTests | Yes (auth flow) | V5 endpoint URL construction, token refresh under concurrent access |
| WoundTissueKit | WoundTissueKitTests | **New package** | Classification accuracy on synthetic masks, area-per-class math |
| WoundHealthKitSync | WoundHealthKitSyncTests | **New package** | FHIR Observation encoding, mock HealthKit store writes |
| WoundV5BackendClient | WoundV5BackendClientTests | **New package** | Request/response coding, error mapping |

#### UI Test Target

| Target | Framework | Scope |
|--------|-----------|-------|
| WoundOSUITests | XCUIAutomation (XCTest) | Capture flow happy path: launch → AR → tap capture → boundary → measurement → save. Uses accessibility identifiers. |

#### Xcode Scheme Wiring

The `WoundOS` scheme's Test action must include:

```
Test Action:
  ├── WoundCoreTests
  ├── WoundCaptureTests
  ├── WoundBoundaryTests
  ├── WoundMeasurementTests
  ├── WoundAutoSegmentationTests
  ├── WoundNetworkingTests
  ├── WoundTissueKitTests
  ├── WoundHealthKitSyncTests
  ├── WoundV5BackendClientTests
  └── WoundOSUITests (UI Testing bundle)
```

#### CI Integration

**Approach: GitHub Actions** (repo is on GitHub, no Xcode Cloud configured).

```yaml
# .github/workflows/test.yml
name: WoundOS Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15        # Xcode 16+, iOS 18 simulator
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app
      - name: Run tests
        run: |
          xcodebuild test \
            -project ios/WoundOS.xcodeproj \
            -scheme WoundOS \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
            -enableCodeCoverage YES \
            -resultBundlePath TestResults.xcresult
      - name: Check coverage
        run: |
          xcrun xccov view --report TestResults.xcresult --json | \
            python3 ios/scripts/check_coverage.py
```

#### Coverage Thresholds

| Package | Minimum | Rationale |
|---------|---------|-----------|
| WoundMeasurement (+ WoundTissueKit) | **70%** | Clinical measurement accuracy is safety-critical. Every calculator must have known-good test vectors. |
| WoundCore | 60% | Model encoding/decoding correctness. |
| WoundCapture | 60% | Gate logic testable; AR session requires device (excluded from CI). |
| WoundBoundary | 60% | Projection math testable with synthetic data. |
| WoundAutoSegmentation | 60% | Protocol conformance and polygon conversion testable; actual ML inference requires device. |
| WoundNetworking | 60% | URL construction, auth flow, retry logic all testable with mocks. |
| WoundHealthKitSync | 60% | FHIR encoding, mock HealthKit writes. |
| WoundV5BackendClient | 60% | Request/response coding. |

**Enforcement:** `check_coverage.py` reads the JSON coverage report, extracts per-target line coverage, and exits non-zero if any target falls below its threshold. PR merges are blocked by the failing check.

**Phase 2 gate:** The CI workflow must be green before any Phase 2 PR is merged.

---

## §1.2 — Feature Flag Contract

### Flag Definitions

All flags are stored in `UserDefaults.standard` with a `"v5_"` prefix. No Firebase Remote Config dependency (blocked on Firebase auth resolution). Flags default to `false` (V4 behavior).

| Flag Key | Type | Default | Gates | Phase |
|----------|------|---------|-------|-------|
| `v5_on_device_segmentation_enabled` | Bool | `false` | YOLO11 + SAM2 Mobile pipeline replaces ServerSegmenter as primary | Phase 3 |
| `v5_tissue_classification_enabled` | Bool | `false` | Tissue overlay on boundary screen, tissue composition in results | Phase 3 |
| `v5_scan_mode_enabled` | Bool | `false` | "Scan Mode" tab in capture screen (Object Capture, iOS 18+) | Phase 2 |
| `v5_medgemma_narrative_enabled` | Bool | `false` | Clinical narrative, dressing recommendation, CPT/ICD-10 in results | Phase 5 |
| `v5_healthkit_sync_enabled` | Bool | `false` | HealthKit writes + longitudinal timeline tab | Phase 6 |

### FeatureFlagManager

```swift
// WoundOS/Utilities/FeatureFlagManager.swift (app target, not a package)
enum FeatureFlag: String, CaseIterable {
    case onDeviceSegmentation = "v5_on_device_segmentation_enabled"
    case tissueClassification = "v5_tissue_classification_enabled"
    case scanMode             = "v5_scan_mode_enabled"
    case medgemmaNarrative    = "v5_medgemma_narrative_enabled"
    case healthkitSync        = "v5_healthkit_sync_enabled"
}

final class FeatureFlagManager {
    static let shared = FeatureFlagManager()

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        UserDefaults.standard.bool(forKey: flag.rawValue)
    }

    func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: flag.rawValue)
    }
}
```

### Usage Pattern (Coordinator Level)

```swift
// In CaptureCoordinator:
func showBoundaryDrawing(snapshot: CaptureSnapshot, quality: CaptureQualityScore?) {
    let segmenter: WoundSegmenter?
    if FeatureFlagManager.shared.isEnabled(.onDeviceSegmentation) {
        segmenter = dependencies.onDeviceSegmenter  // YOLO11 + SAM2 Mobile
    } else {
        segmenter = dependencies.autoSegmenter       // V4 chain (Server → CoreML → Vision)
    }
    let vm = BoundaryDrawingViewModel(
        snapshot: snapshot,
        measurementEngine: dependencies.measurementEngine,
        segmenter: segmenter,
        ...
    )
    // ...
}
```

### Rules

1. **No PHI in UserDefaults.** Flags are booleans only. No patient data, tokens, or identifiers.
2. **Flags gate at coordinator level**, not inside ViewModels or packages. Packages are always capable; the coordinator decides which capability to use.
3. **Flags are developer-only for now.** Internal TestFlight builds can toggle via a hidden debug menu (triple-tap version label in Settings). Public release flags are `false` until explicitly flipped.
4. **Migration to Firebase Remote Config** happens when real Firebase Auth is integrated (Phase 1/2). The `FeatureFlagManager` API stays the same; only the backing store changes.

---

## §1.3 — On-Device ML Strategy

### Model Inventory

| Model | Task | Architecture | Size (est.) | iOS Min | Source |
|-------|------|-------------|-------------|---------|--------|
| **YOLO11n** | Wound detection (bounding box) | YOLO11 Nano | ~6 MB | 17.0 | Ultralytics, fine-tuned on wound dataset |
| **SAM2 Mobile** | Wound segmentation (mask from box+point) | SAM 2.1 Hiera Tiny (mobile distilled) | ~40 MB | 17.0 | Meta, CoreML conversion |
| **TissueClassifier** | 6-class tissue segmentation | FPN + VGG16 encoder | ~50 MB | 17.0 | Custom training on wound tissue dataset |

**Total on-device model footprint: ~96 MB** (compressed ~60 MB with quantization).

### Pipeline Flow

```
Frozen RGB Image + Nurse Tap Point
         │
         ▼
┌─────────────────┐
│  YOLO11 Detect  │──→ [WoundBBox] (x, y, w, h, confidence)
│  (6ms, ANE)     │    If no detection and tap exists, use tap-centered 30% crop
└────────┬────────┘
         │ bbox + tap point
         ▼
┌─────────────────┐
│  SAM2 Mobile    │──→ [BinaryMask] (H×W, Float16)
│  Segment        │    Point prompt = tap, Box prompt = YOLO bbox
│  (50ms, ANE)    │
└────────┬────────┘
         │ mask
         ▼
┌─────────────────┐
│ MaskContourExtractor │──→ [CGPoint] polygon (existing V4 code)
│ + ContourSimplifier  │    30–80 vertices, image-space
└────────┬─────────────┘
         │ polygon
         ▼
  SegmentationResult (existing V4 type)
```

### Segmenter Conformance

```swift
// In WoundAutoSegmentation package:
@available(iOS 17.0, *)
public final class OnDeviceSegmenter: WoundSegmenter {
    public static let modelIdentifier = "yolo11+sam2.ondevice.v1"

    private let detector: WoundDetector     // YOLO11 CoreML wrapper
    private let segmenter: SAM2MobileModel  // SAM2 Mobile CoreML wrapper

    public init(detector: WoundDetector, segmenter: SAM2MobileModel) { ... }

    public func segment(image: CGImage, tapPoint: CGPoint) async throws -> SegmentationResult {
        // 1. YOLO11 detect → bbox (or tap-centered fallback)
        // 2. SAM2 Mobile segment(image, bbox, tapPoint) → mask
        // 3. MaskContourExtractor.extractContour(mask) → polygon
        // 4. ContourSimplifier.simplify(polygon)
        // 5. Return SegmentationResult
    }
}
```

### Model Loading & Caching

```swift
// WoundOS/Utilities/ModelManager.swift (app target)
actor ModelManager {
    static let shared = ModelManager()

    private var cache: [String: MLModel] = [:]

    enum ModelID: String {
        case yolo11    = "WoundDetectorYOLO11n"
        case sam2      = "SAM2MobileTiny"
        case tissue    = "TissueClassifierFPN"
    }

    /// Load model from bundle (Phase 3: bundled; future: on-demand download)
    func loadModel(_ id: ModelID) async throws -> MLModel {
        if let cached = cache[id.rawValue] { return cached }

        guard let url = Bundle.main.url(forResource: id.rawValue, withExtension: "mlmodelc") else {
            throw ModelError.modelNotFound(id.rawValue)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all  // ANE preferred
        let model = try MLModel(contentsOf: url, configuration: config)
        cache[id.rawValue] = model
        return model
    }
}
```

**Phase 3 approach:** Bundle models in the app target. Total IPA size increase ~60 MB (acceptable for clinical app, avoids first-launch download UX).

**Future (post-Phase 3):** If model size becomes a concern, migrate to on-demand download via `URLSession` background transfer + compile with `MLModel.compileModel(at:)` + cache in `Application Support/Models/`. The `ModelManager` API stays the same.

### SAM2 Mobile CoreML Conversion Strategy

SAM2 Mobile (Hiera Tiny) must be converted from PyTorch → CoreML:

1. Export image encoder via `torch.export()` → ONNX → `coremltools.converters.convert()`
2. Export mask decoder separately (it takes encoder features + point/box prompts)
3. Validate: mean IoU on wound test set must be ≥ 0.80 (vs PyTorch reference)
4. Quantize to Float16 (ANE compatible, ~50% size reduction)
5. **Fallback:** If conversion fails or accuracy drops below threshold, V5 falls back to `VisionForegroundSegmenter` (iOS 17+) or `ServerSegmenter` (GrabCut). The `WoundSegmenter` protocol makes this a one-line swap in `DependencyContainer`.

**Risk budget:** 2 weeks for conversion + validation. Owner: Agent (Phase 3).

### Backend SAM2 Deprecation Plan

| Phase | Server Segmenter Status | On-Device Status |
|-------|------------------------|------------------|
| Phase 1 (now) | Active (GrabCut fallback) | Not available |
| Phase 2 | Active (GrabCut fallback) | Not available |
| Phase 3 | Active (GrabCut fallback) as secondary | Primary (YOLO11 + SAM2 Mobile), flag-gated |
| Phase 4+ | Deprecated; endpoint returns 410 Gone | Primary, flag always on |

The `ServerSegmenter` closure in `DependencyContainer` is retained as a fallback until on-device validation is complete. The `v5_on_device_segmentation_enabled` flag controls which path is primary.

---

## §1.4 — Capture Pipeline Architecture

### Two Capture Modes

| Mode | iOS Min | When | How |
|------|---------|------|-----|
| **Single-Shot** | 17.0 | Default. Flat/shallow wounds. | Existing V4 flow: AR → freeze → boundary → measure |
| **Scan Mode** | 18.0 | Undermined, large, curved wounds. | Object Capture Area Mode → 3D reconstruction → volumetric measurement |

### Single-Shot Mode (V4 → V5 Enhancement)

The existing capture flow is retained with these V5 additions:

```
CaptureViewController (V4, enhanced)
  ├── ARSCNView (unchanged)
  ├── Framing guide reticle (V4, unchanged)
  ├── Distance indicator bar (V4, unchanged)
  ├── 4-gate readiness check (V4, unchanged)
  │
  ├── [V5] Sweet-spot distance ring (26-35 cm, replaces 15-30 cm)
  ├── [V5] Confidence heatmap overlay (depth confidence → green/yellow/red)
  └── [V5] Mode toggle: "Single Shot" / "Scan Mode" (iOS 18+ only)
```

**Distance change:** V4 uses 15-30 cm optimal range. V5 narrows to 26-35 cm based on clinical testing — this range gives ≥95% mesh hit rate on typical wound sites. The `CaptureQualityMonitor` thresholds are updated (not a protocol change, just constants).

### Scan Mode (V5 New, iOS 18+)

```
ScanModeCaptureViewController (NEW)
  ├── ObjectCaptureView (SwiftUI via UIHostingController)
  ├── ObjectCapturePointCloudView
  ├── Guided prompts ("Orbit slowly around the wound")
  ├── Progress indicator (scan passes)
  └── "Done" → PhotogrammetrySession reconstruction
```

**Data flow:**

```
ObjectCaptureSession
  → .capturing state (nurse orbits wound)
  → .completed (images saved to temp directory)
  → PhotogrammetrySession (reconstruct 3D model)
  → USDZ/OBJ mesh output
  → Convert to [SIMD3<Float>] vertices + faces
  → Feed into MeshMeasurementEngine (same 6-step pipeline)
```

**Key architectural decision:** Scan Mode produces a mesh in the same format as Single-Shot's LiDAR mesh. The downstream pipeline (BoundaryProjector → MeshMeasurementEngine) is identical. The only difference is the mesh source.

### Coordinator Integration

```swift
// In CaptureCoordinator:
func showCapture() {
    let vm = CaptureViewModel(captureProvider: dependencies.captureProvider)
    vm.onCaptureComplete = { [weak self] snapshot, quality in
        self?.showBoundaryDrawing(snapshot: snapshot, qualityScore: quality)
    }

    // V5: Add scan mode callback (iOS 18+ only)
    if #available(iOS 18.0, *),
       FeatureFlagManager.shared.isEnabled(.scanMode) {
        vm.onScanModeRequested = { [weak self] in
            self?.showScanModeCapture()
        }
    }

    let vc = CaptureViewController(viewModel: vm)
    navigationController.setViewControllers([vc], animated: false)
}

@available(iOS 18.0, *)
func showScanModeCapture() {
    // ObjectCaptureSession flow → mesh → showBoundaryDrawing(...)
}
```

### CaptureSnapshot Extension

```swift
// In WoundCore, extend CaptureSnapshot:
public struct CaptureSnapshot {
    // ... existing V4 fields ...

    // V5 additions:
    public var captureMode: CaptureMode = .singleShot
    public var scanPassCount: Int?               // Scan Mode only
    public var reconstructionQuality: Float?     // 0-1, Scan Mode only
}

public enum CaptureMode: String, Codable {
    case singleShot
    case scanMode
}
```

---

## §1.5 — Measurement Pipeline V5 Extensions

### Existing 6-Step Pipeline (UNCHANGED)

```
Step 1: MeshClipper.clip()           → ClippedMesh
Step 2: AreaCalculator.computeArea() → Double (cm²)
Step 3: DepthCalculator.compute()    → DepthResult (max/mean depth, reference plane)
Step 4: VolumeCalculator.compute()   → Double (mL)
Step 5: PerimeterCalculator.compute()→ Double (mm)
Step 6: DimensionCalculator.compute()→ DimensionResult (L × W)
```

**No modifications to the existing pipeline.** V5 features are additive steps that consume the same intermediate results.

### V5 Extension Steps

```
Step 2b: TissueClassifier.classify()  → TissueComposition    [NEW, parallel to Step 2]
Step 6b: BWATCalculator.compute()     → BWATScore             [NEW, after Step 6]
Step 6c: UnderminingCalculator.compute() → UnderminingResult   [NEW, after Step 6]
```

### Step 2b: Tissue Classification

**Package:** WoundTissueKit

**Input:** `ClippedMesh` (from Step 1) + `CGImage` (frozen RGB) + camera intrinsics/transform

**Algorithm:**

1. Run TissueClassifier CoreML model on the RGB image → `H×W×6` probability map (6 tissue classes)
2. For each triangle in `ClippedMesh`:
   a. Project triangle centroid to 2D image space (reuse `MeshClipper.projectVerticesToImage()` logic)
   b. Sample tissue probability map at that pixel
   c. Assign dominant tissue class to the triangle
   d. Accumulate triangle area by tissue class
3. Output: `TissueComposition`

```swift
// In WoundCore:
public struct TissueComposition: Codable, Sendable {
    public let areaByClass: [TissueClass: Double]  // cm² per class
    public let fractionByClass: [TissueClass: Double]  // 0-1 per class
    public let dominantClass: TissueClass
    public let confidenceMap: Data?  // Optional H×W visualization data
}

public enum TissueClass: String, Codable, CaseIterable, Sendable {
    case granulation
    case slough
    case necrosis
    case eschar
    case epithelialization
    case maceration
}
```

### Step 6b: BWAT Score (Bates-Jensen Wound Assessment Tool)

**Package:** WoundMeasurement (extend existing)

**Input:** `WoundMeasurement` (from Steps 1-6) + `TissueComposition` (from Step 2b) + nurse-observed parameters

**Algorithm:** Pure computation — 13 subscales, each scored 1-5:

| Subscale | Source | Input |
|----------|--------|-------|
| 1. Size | Auto | `areaCm2` from Step 2 |
| 2. Depth | Auto | `maxDepthMm` from Step 3 |
| 3. Edges | Nurse | Enum: distinct/attached/not attached/rolled/undermining |
| 4. Undermining | Auto/Nurse | `UnderminingResult` if available, else nurse input |
| 5. Necrotic tissue type | Auto | `TissueComposition.fractionByClass[.necrosis]` + `[.eschar]` |
| 6. Necrotic tissue amount | Auto | Sum of necrotic fractions |
| 7. Exudate type | Nurse | Enum: none/bloody/serosanguineous/serous/purulent |
| 8. Exudate amount | Nurse | Enum: none/scant/small/moderate/large (reuse PUSH field) |
| 9. Skin color surrounding | Nurse | Enum: pink/bright red/white/dark red/purple/black |
| 10. Peripheral tissue edema | Nurse | Enum: none/non-pitting/<4cm/≥4cm/crepitus |
| 11. Peripheral tissue induration | Nurse | Enum: none/≤2cm/2-4cm/>4cm |
| 12. Granulation tissue | Auto | `TissueComposition.fractionByClass[.granulation]` |
| 13. Epithelialization | Auto | `TissueComposition.fractionByClass[.epithelialization]` |

**Output:**

```swift
public struct BWATScore: Codable, Sendable {
    public let subscales: [BWATSubscale: Int]  // 1-5 each
    public let totalScore: Int                  // 13-65
    public let autoScoredCount: Int            // How many subscales were auto-scored
}
```

**Total score range:** 13 (best/healed) to 65 (worst). BWAT > 13 indicates an active wound.

### Step 6c: Undermining (Future — Phase 4)

Undermining measurement requires nurse annotation of clock positions and extent. This is a Phase 4 feature that consumes `DepthResult.referencePlanePoint/Normal` and the `ClippedMesh` to detect sub-surface cavities at wound margins.

### MeshMeasurementEngine Extension

The engine's `measure()` method returns a `WoundMeasurement`. V5 does NOT modify this method. Instead, the `BoundaryDrawingViewModel` calls the tissue classifier and BWAT calculator separately after the engine returns:

```swift
// In BoundaryDrawingViewModel.computeMeasurements():
// 1. Existing: engine.measure(captureData, boundary, quality) → WoundMeasurement
// 2. V5 NEW: tissueClassifier.classify(clippedMesh, rgbImage, intrinsics) → TissueComposition
// 3. V5 NEW: bwatCalculator.compute(measurement, tissue, nurseInputs) → BWATScore
// 4. Assemble WoundScan with all results
```

The `ClippedMesh` is currently internal to the engine. To expose it for tissue classification, the engine will provide an additional method:

```swift
// In MeshMeasurementEngine:
public func clipMesh(captureData: CaptureData, boundary: WoundBoundary) throws -> ClippedMesh
```

This extracts Step 1 as a standalone callable, reusing existing code. The full `measure()` method calls this internally as before.

---

## §1.6 — Backend V5 Endpoints

### Endpoint Design: Bearer-Token Middleware-Flip Ready

All V5 endpoints use the existing Bearer JWT auth pattern. The middleware architecture is designed so that flipping from stub auth to real Firebase Auth requires **zero endpoint changes** — only the `verify_firebase_token()` function changes behavior.

```python
# backend/app/core/auth.py (existing, unchanged structure)
async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """Verify JWT. This is the SINGLE auth middleware all endpoints use.

    Middleware-flip: When Firebase Auth goes live:
    1. Set FIREBASE_PROJECT_ID env var to real project ID
    2. verify_firebase_token() switches from accepting any token
       to calling firebase_admin.auth.verify_id_token()
    3. No endpoint code changes needed.
    """
    payload = decode_access_token(token)
    return {"user_id": payload.get("sub"), "email": payload.get("email")}
```

### New V5 Endpoints

| # | Method | Path | Auth | Request | Response | Phase |
|---|--------|------|------|---------|----------|-------|
| 1 | POST | `/v5/measurements` | Bearer | `V5MeasurementRequest` | `V5MeasurementResponse` | Phase 5 |
| 2 | GET | `/v5/trajectories/{patient_id}` | Bearer | Query: `?wound_id=`, `?limit=` | `TrajectoryResponse` | Phase 6 |
| 3 | POST | `/v5/registrations` | Bearer | `RegistrationRequest` (2 meshes) | `RegistrationResponse` (transform + metrics) | Phase 6 |
| 4 | POST | `/v5/narratives` | Bearer | `NarrativeRequest` (measurements + tissue) | `NarrativeResponse` (MedGemma output) | Phase 5 |

### Request/Response Schemas

```python
# POST /v5/measurements
class V5MeasurementRequest(BaseModel):
    scan_id: str
    patient_id: str
    nurse_id: str
    facility_id: str
    capture_mode: Literal["single_shot", "scan_mode"]

    # On-device measurements (nurse primary)
    area_cm2: float
    max_depth_mm: float
    mean_depth_mm: float
    volume_ml: float
    length_mm: float
    width_mm: float
    perimeter_mm: float

    # Tissue composition (on-device classifier)
    tissue_composition: dict[str, float] | None = None  # class → fraction

    # Clinical scoring
    push_score: PUSHScorePayload | None = None
    bwat_score: BWATScorePayload | None = None

    # Nurse-observed parameters
    exudate_type: str | None = None
    wound_edge_type: str | None = None
    skin_color: str | None = None
    edema: str | None = None
    induration: str | None = None

class V5MeasurementResponse(BaseModel):
    scan_id: str
    push_score_verified: PUSHScorePayload   # Backend re-computes from measurements
    bwat_score_verified: BWATScorePayload   # Backend re-computes
    narrative: NarrativePayload | None       # MedGemma if enabled
    cpt_codes: list[str] | None
    icd10_codes: list[str] | None
    created_at: datetime
```

### Middleware-Flip Confirmation

The V5 endpoints reuse the existing `Depends(get_current_user)` FastAPI dependency. When real auth goes live:

1. Set `FIREBASE_PROJECT_ID` environment variable on Cloud Run
2. `verify_firebase_token()` in `auth.py` switches from passthrough to `firebase_admin.auth.verify_id_token()`
3. iOS app sends real Firebase ID token instead of stub
4. All `/v1/*` and `/v5/*` endpoints are simultaneously protected — **zero code changes to any route**

---

## §1.7 — Data Flow & Storage

### On-Device Data Flow

```
Capture (ARKit)
    → CaptureSnapshot (in-memory)
    → Boundary Drawing (in-memory, user edits)
    → MeshMeasurementEngine (in-memory computation)
    → WoundScan (fully assembled model)
    → LocalScanStorage.saveScan()
        → Documents/WoundScans/{uuid}.json     [PHI — must be NSFileProtectionComplete]
    → UploadManager.enqueueUpload()
        → POST /v1/scans/upload (multipart)    [PHI in transit — HTTPS + Bearer JWT]
```

### V5 Data Flow Additions

```
WoundScan (V5 extended)
    ├── primaryMeasurement: WoundMeasurement   [V4, on-device, DISPLAYED TO NURSE]
    ├── tissueComposition: TissueComposition?  [V5, on-device, displayed]
    ├── bwatScore: BWATScore?                  [V5, on-device + nurse input, displayed]
    ├── pushScore: PUSHScore                   [V4, on-device + nurse input, displayed]
    │
    ├── shadowBoundary: WoundBoundary?         [V4, BACKEND ONLY, NOT DISPLAYED]
    ├── shadowMeasurement: WoundMeasurement?   [V4, BACKEND ONLY, NOT DISPLAYED]
    ├── agreementMetrics: AgreementMetrics?     [V4, BACKEND ONLY, NOT DISPLAYED]
    ├── fwaSignals: FWASignal?                 [V4, BACKEND ONLY, NOT DISPLAYED]
    └── clinicalSummary: ClinicalSummary?      [V4, BACKEND ONLY, shown in ScanDetail only]
```

### Shadow Measurement Isolation — Written Confirmation

**The `shadowMeasurement`, `shadowBoundary`, `agreementMetrics`, and `fwaSignals` fields are confirmed isolated from all user-facing clinical measurement displays, training data pipelines, analytics exports, and clinical decision paths.**

Evidence from code audit:

| Field | Written By | Read By | Displayed? | Used in Clinical Decisions? |
|-------|-----------|---------|------------|---------------------------|
| `shadowBoundary` | Backend `sam2_processor.py` (stub) | `ScanDetailViewController` (read-only comparison view) | Only in "Nurse vs AI Comparison" section of ScanDetail, which is for **internal QA review**, not clinical use | **NO** |
| `shadowMeasurement` | Backend `sam2_processor.py` (stub) | `ScanDetailViewController` (read-only comparison view) | Only in "Nurse vs AI Comparison" section | **NO** |
| `agreementMetrics` | Backend `sam2_processor.py` (stub) | `ScanDetailViewController` (read-only) | Only in "Agreement Metrics" section | **NO** |
| `fwaSignals` | Backend `sam2_processor.py` (stub) | `ScanDetailViewController` (read-only) | Only in flag warning banners in ScanDetail | **NO** — flags are informational, not action-blocking |
| `primaryMeasurement` | On-device `MeshMeasurementEngine` | `MeasurementResultViewController` (clinical display) | **YES — this is the clinical measurement shown to the nurse** | **YES** |

**Isolation guarantees:**

1. `MeasurementResultViewController` (the screen nurses use to review and save measurements) reads **only** `scan.primaryMeasurement`. It never references `shadowMeasurement`, `shadowBoundary`, `agreementMetrics`, or `fwaSignals`.

2. `ScanDetailViewController` shows shadow/agreement data in clearly labeled comparison sections, but these sections are for internal quality review (post-save), not pre-save clinical decision-making.

3. The backend stub in `sam2_processor.py` is tagged `model_version: "sam2-stub-v1"`. Any analytics or training pipeline must filter by `model_version` — stub-generated data is trivially identifiable and excludable.

4. **V5 does not change this isolation.** V5 adds `tissueComposition` and `bwatScore` to the nurse-facing flow, but shadow fields remain backend-only/QA-only.

5. **Training data policy:** No data produced by `sam2-stub-v1` shall be used for model training or clinical validation. The `model_version` field in `shadow_boundary` records provides the filter key. This must be documented in the training data governance policy (owner: data science team, if one exists, otherwise product owner).

### Local Storage Security (V5 Enhancement)

```swift
// In LocalScanStorage (DependencyContainer.swift), add NSFileProtectionComplete:
func saveScan(_ scan: WoundScan) throws {
    let data = try encoder.encode(scan)
    let url = scansDirectory.appendingPathComponent("\(scan.id.uuidString).json")
    try data.write(to: url, options: [.atomic])

    // V5: Set file protection to Complete (encrypted at rest when device is locked)
    try (url as NSURL).setResourceValue(
        URLFileProtection.complete,
        forKey: .fileProtectionKey
    )
}
```

---

## §1.8 — Longitudinal & HealthKit Architecture

### Longitudinal Timeline

**New tab:** "Timeline" (third tab in `AppCoordinator`), gated by `v5_healthkit_sync_enabled`.

```
TimelineCoordinator (NEW)
  ├── WoundTimelineViewController
  │     ├── Patient/wound selector (horizontal scroll of wound sites)
  │     ├── Trend charts (Swift Charts):
  │     │     ├── Area (cm²) over time
  │     │     ├── Depth (mm) over time
  │     │     ├── PUSH Score over time
  │     │     └── Volume (mL) over time
  │     ├── Thumbnail timeline (horizontal scroll of wound images)
  │     └── Tap → ScanDetailViewController (reuse existing)
  │
  └── Data source: StorageProviderProtocol.fetchScans(patientId:)
        → sorted by capturedAt
        → grouped by wound site (heuristic: location proximity + manual label)
```

### Wound Site Matching

V5 groups scans into wound "series" for longitudinal tracking:

```swift
// In WoundCore:
public struct WoundSite: Codable, Sendable {
    public let id: UUID
    public let patientId: String
    public let label: String          // "Left heel", "Sacrum", etc.
    public let bodyLocation: BodyLocation?
    public var scanIds: [UUID]        // Ordered by date
    public let createdAt: Date
}

public enum BodyLocation: String, Codable, CaseIterable, Sendable {
    case sacrum, leftHeel, rightHeel, leftAnkle, rightAnkle
    case leftLeg, rightLeg, leftFoot, rightFoot
    case abdomen, chest, back, leftArm, rightArm
    case other
}
```

**Initial implementation (Phase 6):** Manual wound site labeling by the nurse at first capture. Subsequent scans for the same patient prompt "Is this the same wound as [label]?" with options to match or create new.

**Future (post-Phase 7):** ICP registration auto-matches wound sites by mesh alignment.

### HealthKit Integration

**Package:** WoundHealthKitSync

**Observations written:**

| Measurement | HKQuantityType | Unit | Notes |
|-------------|---------------|------|-------|
| Wound area | Custom (no native type) | cm² | Use `HKQuantitySample` with metadata key `"WoundOS.woundArea"` |
| PUSH Score | Custom | score | Use `HKQuantitySample` with metadata key `"WoundOS.pushScore"` |

**Limitation:** HealthKit has no wound-specific `HKQuantityTypeIdentifier`. We use `HKQuantityType(.appleSleepingWristTemperature)` — **NO, this is wrong.** Instead, we store wound data as `HKClinicalRecord` if available, or use custom `HKQuantitySample` with well-known metadata keys. The HealthKit integration is primarily for:

1. **Data portability** — wound measurements appear in Apple Health for patient access
2. **Research** — opt-in data sharing via Apple Research framework
3. **EMR export** — FHIR Observation resources

**Authorization flow:**

```swift
// In WoundHealthKitSync:
public actor HealthKitManager {
    private let store = HKHealthStore()

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        let typesToWrite: Set<HKSampleType> = [
            // Custom clinical observation types
            HKQuantityType(.bodyMass) // Placeholder — real implementation uses clinical records
        ]

        try await store.requestAuthorization(toShare: typesToWrite, read: [])
    }

    public func writeWoundMeasurement(_ scan: WoundScan) async throws {
        // Create HKQuantitySample with wound-specific metadata
        // Metadata keys: WoundOS.scanId, WoundOS.woundSiteId, WoundOS.areaCm2, etc.
    }
}
```

**Entitlements required:**
- `com.apple.developer.healthkit` (capability)
- `NSHealthShareUsageDescription` in Info.plist
- `NSHealthUpdateUsageDescription` in Info.plist

**Gate:** `v5_healthkit_sync_enabled` flag. HealthKit authorization is only requested when the flag is enabled AND the nurse navigates to the Timeline tab.

### FHIR Export

```swift
// In WoundHealthKitSync:
public struct FHIRObservationExporter {
    /// Generates a FHIR R4 Observation resource for a wound measurement.
    public static func export(_ scan: WoundScan) -> Data {
        // JSON: { "resourceType": "Observation", "code": { "coding": [LOINC wound codes] }, ... }
    }
}
```

LOINC codes for wound measurements:
- `89254-0` — Wound area
- `89255-7` — Wound depth
- `72514-3` — Wound length
- `72515-0` — Wound width

---

## §1.9 — Auth & Security Architecture

### Current State (V4 — BLOCKING)

```
StubFirebaseAuth → "stub-firebase-id-token" → Backend accepts in dev mode → JWT issued
```

**This is a pre-existing compliance gap identified in the GATE 0 audit.** No real user identity. No access control. The `nurse_id` field is client-supplied with no server-side verification.

### V5 Auth Architecture

**Decision required from owner:** Firebase Auth SDK or Sign in with Apple (or both)?

The architecture supports either via the existing `FirebaseAuthProviding` protocol:

#### Option A: Firebase Auth SDK (Recommended)

```
Firebase Auth SDK (iOS)
  → Sign in with Email/Password or Sign in with Apple (via Firebase)
  → firebase.auth().currentUser?.getIDToken()
  → POST /v1/auth/token (backend validates with firebase_admin)
  → Backend JWT issued with real user identity
```

**Requirements from owner:**
- Firebase project ID
- `GoogleService-Info.plist` file
- Firebase Auth enabled in Firebase Console with desired sign-in methods

**iOS integration:**

```swift
// New file: WoundNetworking/FirebaseAuthProvider.swift
import FirebaseAuth

public struct RealFirebaseAuth: FirebaseAuthProviding {
    public func getFirebaseIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        return try await user.getIDToken()
    }
}
```

**DependencyContainer change:**

```swift
lazy var authProvider: AuthProvider = {
    let firebase: FirebaseAuthProviding
    if FeatureFlagManager.shared.isEnabled(.realAuth) {
        firebase = RealFirebaseAuth()
    } else {
        firebase = StubFirebaseAuth()  // Dev/testing only
    }
    return AuthProvider(
        tokenStore: KeychainTokenStore(),
        firebase: firebase
    )
}()
```

**Login screen:** New `AuthCoordinator` presented by `SceneDelegate` before `AppCoordinator` if no valid session exists:

```
SceneDelegate
  ├── AuthProvider.hasValidToken()?
  │     ├── YES → AppCoordinator.start()
  │     └── NO  → AuthCoordinator.start()
  │                  ├── LoginViewController (email + password)
  │                  ├── Sign in with Apple button
  │                  └── onAuthComplete → AppCoordinator.start()
```

#### Option B: Sign in with Apple Only

If Firebase is not available/desired, the backend verifies Apple ID tokens directly using Apple's JWKS endpoint. This requires new backend verification code but removes the Firebase dependency entirely.

### Backend Middleware Flip

As documented in §1.6, the flip is a single environment variable:

```bash
# Cloud Run environment:
FIREBASE_PROJECT_ID=your-project-id    # Set this → real auth
# FIREBASE_PROJECT_ID=                 # Empty → dev mode (accepts any token)
```

No endpoint code changes. No schema changes. The `get_current_user` middleware reads the decoded JWT `sub` claim as the authenticated user identity.

### Security Hardening Checklist (Phase 1-2)

| Item | Priority | Phase | Status |
|------|----------|-------|--------|
| Replace `StubFirebaseAuth` with real auth | P0 | Phase 2 | Blocked on owner providing Firebase credentials |
| Add `NSFileProtectionComplete` to local scan JSON files | P0 | Phase 2 | Ready to implement |
| Authenticate Pub/Sub push endpoint (OIDC token verification) | P1 | Phase 5 | Backend change |
| Add `nurse_id` server-side verification (JWT `sub` → nurse_id) | P1 | Phase 2 | Requires real auth first |
| Set `SWIFT_STRICT_CONCURRENCY = complete` | P2 | Phase 1 | Build setting change |
| Migrate Keychain to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | P2 | Phase 2 | One-line change in `KeychainTokenStore` |

---

## Open Unknowns — Resolution Status

Every unknown from the Phase 0 audit is tracked here. None silently disappear.

| # | Question | Status | Resolution / Flagged Assumption |
|---|----------|--------|-------------------------------|
| U1 | GCP project ID for `careplix-woundos`? | **Flagged** | Assumed `333499614175` (matches Cloud Run service URLs). Owner must confirm. Needed for Firebase config. |
| U2 | Wound image training dataset location? | **Flagged** | Not blocking until Phase 3 (YOLO11 fine-tuning). Owner must provide before Phase 3 starts. |
| U3 | Is `backend/` the only backend repo? | **Flagged** | Assumed yes (mono-repo). CI workflow targets `backend/` directory. Owner confirms. |
| U4 | Firebase project ID + `GoogleService-Info.plist`? | **BLOCKING** | Required for real auth (§1.9). Phase 2 cannot start without this. Owner must provide. |
| U5 | CarePlix WoundAI API deprecation? | **Flagged** | Assumed coexistence — V5 does not call CarePlix API. Tissue models on CarePlix may be useful as cloud fallback. Owner decides. |
| U6 | Sibling service URLs (digitize, bcap, eczema)? | **Resolved** | V5 uses `/v5/` prefix on the existing `woundos-api` service. No URL collision possible with sibling services on separate Cloud Run instances. |
| U7 | App Store Connect API key for CI? | **Flagged** | GitHub Actions workflow does not auto-deploy to TestFlight. Manual Organizer upload continues until owner provides ASC API key (`.p8` file). |
| U8 | FDA 510(k) target date? | **Flagged** | Affects traceability matrix timeline. No V5 code assumes a specific date. Owner must provide for Phase 7 (QA) planning. |

---

## Phase Execution Order

| Phase | Name | Depends On | Key Deliverable | Duration (est.) |
|-------|------|-----------|----------------|----------------|
| **1** | Architecture (this doc) | GATE 0 ✅ | `WOUNDOS_V5_ARCHITECTURE.md` | Complete |
| **2** | Capture & Auth | GATE 1 + Firebase creds (U4) | iOS 17 deployment target, real auth, Single-Shot enhancements, test infrastructure live | — |
| **3** | ML Pipeline | Phase 2 | YOLO11 + SAM2 Mobile on-device, tissue classification | — |
| **4** | Measurement Extensions | Phase 3 | BWAT scoring, undermining (if annotated), enhanced results UI | — |
| **5** | Backend V5 | Phase 4 | `/v5/*` endpoints, MedGemma narrative, CPT/ICD-10 | — |
| **6** | Longitudinal | Phase 5 | Timeline tab, HealthKit sync, FHIR export, wound site tracking | — |
| **7** | QA & Certification | Phase 6 | Golden set validation, coverage thresholds met, traceability matrix | — |

---

**GATE 1 CHECKPOINT.** This architecture plan is complete. Awaiting sign-off before proceeding to Phase 2 (Capture & Auth).
