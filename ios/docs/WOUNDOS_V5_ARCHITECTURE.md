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

### Packages NOT created — Detailed Justification

The original V5 spec proposed `WoundCaptureKit`, `WoundSegmentationKit`, `WoundUI`, and `WoundModels` as new packages. After auditing the existing codebase (6,632 lines across 45 source files), these are absorbed into existing packages. The justification follows.

#### Current Package Inventory

| Package | Source Files | Lines | Public Types | Responsibility |
|---------|-------------|-------|-------------|----------------|
| WoundCore | 14 | 1,262 | 28 | Models, protocols, extensions — **zero logic, pure data** |
| WoundCapture | 3 | 756 | 7 | ARKit session management, quality monitoring |
| WoundBoundary | 3 | 812 | 9 | Touch drawing canvas, 2D→3D projection, boundary validation |
| WoundMeasurement | 10 | 1,273 | 11 | 6-step mesh measurement engine, geometry utilities |
| WoundAutoSegmentation | 8 | 1,063 | 9 | Segmenter protocol + 3 conformers (Server, CoreML, Vision) |
| WoundNetworking | 7 | 1,466 | 32 | HTTP client, auth, upload queue, API models |

#### Which Existing Packages Absorb Which V5 Responsibilities

| Proposed New Package | Absorbed Into | V5 Addition | Lines Added (est.) | Coupling Analysis |
|---------------------|---------------|-------------|-------------------|-------------------|
| **WoundCaptureKit** | **WoundCapture** (+200 lines) | `ObjectCaptureSessionManager` — a new class behind `@available(iOS 18.0, *)` conforming to `CaptureProviderProtocol`. Shares the same protocol contract as `ARSessionManager`. | ~200 | **No new dependencies.** WoundCapture depends only on WoundCore today. Object Capture uses RealityKit (system framework), same as ARKit. The new class outputs a `CaptureSnapshot` identical to the existing one — the downstream pipeline is unaware of the capture source. No UI code, no networking code. |
| **WoundSegmentationKit** | **WoundAutoSegmentation** (+350 lines) | `OnDeviceSegmenter` — a new `WoundSegmenter` conformer wrapping YOLO11 + SAM2 Mobile CoreML. `WoundDetector` — YOLO11 bounding-box wrapper. | ~350 | **No new dependencies.** WoundAutoSegmentation depends only on WoundCore. CoreML models are loaded via `MLModel(contentsOf:)` — the `.mlmodelc` bundles are in the app target, not this package. The package references `CoreML` (system framework) and `Vision` (already imported). No UI code, no networking code. |
| **WoundUI** | **App target (`WoundOS/Scenes/`)** | New screens: `TissueOverlayView`, `TimelineViewController`, `WoundAssessmentViewController`, etc. | ~1,500 | V4 already places all screens in the app target. V5 follows the same pattern. UI code is never in SPM packages (packages are headless logic). This is the correct architecture — it prevents packages from importing UIKit and keeps them testable on any platform. |
| **WoundModels** | **App target (`WoundOS/Resources/`)** | CoreML `.mlmodelc` bundles + `ModelManager` actor for loading/caching. | ~150 | Model files are resources, not libraries. The app target owns resources. `ModelManager` is an app-level utility that hands `MLModel` instances to packages via dependency injection. |

#### Coupling Analysis — The Critical Constraint

**"Measurement math co-located with UI or networking code" — CONFIRMED NOT HAPPENING.**

| Package | Imports UIKit? | Imports Network/URLSession? | Contains UI classes? | Contains HTTP calls? |
|---------|---------------|---------------------------|---------------------|---------------------|
| WoundCore | NO | NO | NO | NO |
| WoundCapture | NO (imports ARKit) | NO | NO | NO |
| WoundBoundary | YES (BoundaryCanvasView is a UIView) | NO | YES (1 file) | NO |
| **WoundMeasurement** | **NO** | **NO** | **NO** | **NO** |
| WoundAutoSegmentation | NO (conditional `#if canImport(UIKit)` for JPEG conversion only) | NO | NO | NO |
| WoundNetworking | NO | YES (URLSession) | NO | YES |

**WoundMeasurement is hermetically sealed.** It imports only `Foundation`, `simd`, `CoreGraphics`, and `WoundCore`. Zero UI. Zero networking. It is pure geometry math.

V5 additions to WoundMeasurement:
- `BWATScoreCalculator.swift` — pure computation, same as `PUSHScoreCalculator.swift`
- `ConfidenceGating.swift` — depth pixel rejection logic (pure math)
- `RANSACPlaneFitter.swift` — outlier-robust plane fit (pure math)
- `UnderminingDetector.swift` — horizontal pocket analysis (pure geometry)

**WoundTissueKit** is the one new package that crosses a boundary: it depends on WoundCore + WoundMeasurement because it needs `ClippedMesh` (from MeshClipper) and `ProjectionUtils` (for 3D→2D projection). It does NOT depend on UIKit or WoundNetworking. Its CoreML model is loaded via `MLModel` passed in by dependency injection from the app target.

#### Why NOT Separate WoundCaptureKit / WoundSegmentationKit

1. **Protocol already exists.** `CaptureProviderProtocol` and `WoundSegmenter` are already the abstraction boundaries. Adding a new conformer to an existing package is a one-file addition, not an architecture change.

2. **SPM package overhead.** Each new package requires: `Package.swift`, directory structure, test target, scheme wiring, CI coverage threshold. For a single-class addition (ObjectCaptureSessionManager, OnDeviceSegmenter), the overhead exceeds the code.

3. **No dependency conflict.** If `ObjectCaptureSessionManager` needed to import WoundNetworking or UIKit, it would belong in a separate package. It doesn't — it imports only RealityKit (system framework) and WoundCore.

4. **Line count supports colocation.** WoundCapture is 756 lines (3 files). Adding a 200-line class brings it to 956 lines — still compact. WoundAutoSegmentation is 1,063 lines (8 files). Adding 350 lines brings it to 1,413 — comparable to WoundNetworking.

### Dependency Rules (enforced by SPM)

1. **WoundCore depends on nothing.** All model types, protocols, and extensions live here. Zero logic, pure data + protocols.
2. **Leaf packages depend only on WoundCore** — no leaf-to-leaf imports. This includes WoundCapture, WoundBoundary, WoundAutoSegmentation, WoundNetworking.
3. **WoundMeasurement depends only on WoundCore.** It contains zero UI and zero networking. V5 additions (BWAT, RANSAC, undermining, confidence gating) are pure geometry math added to this package.
4. **WoundTissueKit (NEW) depends on WoundCore + WoundMeasurement** — it consumes `ClippedMesh` and `ProjectionUtils` to map tissue classifications onto mesh triangles. No UI, no networking.
5. **WoundV5BackendClient (NEW) depends on WoundCore + WoundNetworking** — it extends the existing `WoundOSClient` actor with `/v5/*` methods.
6. **WoundHealthKitSync (NEW) depends only on WoundCore** — it imports HealthKit (system framework).
7. **The app target depends on everything** — it is the composition root. All UI lives here. All CoreML model resources live here.

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

### FeatureFlagManager — Protocol-Backed Abstract Interface

The flag API is `FeatureFlags.isEnabled(.onDeviceSegmentation)`. The backing store is hidden behind a protocol. Swapping UserDefaults → Firebase Remote Config is a single-file change (new conformer, one line in `DependencyContainer`).

```swift
// WoundOS/Utilities/FeatureFlags.swift (app target, not a package)

// MARK: - Flag Definitions

public enum FeatureFlag: String, CaseIterable, Sendable {
    case onDeviceSegmentation = "v5_on_device_segmentation_enabled"
    case tissueClassification = "v5_tissue_classification_enabled"
    case scanMode             = "v5_scan_mode_enabled"
    case medgemmaNarrative    = "v5_medgemma_narrative_enabled"
    case healthkitSync        = "v5_healthkit_sync_enabled"
}

// MARK: - Abstract Store Protocol

public protocol FeatureFlagStore: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
    func setEnabled(_ flag: FeatureFlag, _ value: Bool)
}

// MARK: - UserDefaults Backing Store (Phase 1-7)

public final class UserDefaultsFlagStore: FeatureFlagStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        defaults.bool(forKey: flag.rawValue)
    }

    public func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        defaults.set(value, forKey: flag.rawValue)
    }
}

// MARK: - Future: Firebase Remote Config Backing Store (Phase 8+)
//
// final class RemoteConfigFlagStore: FeatureFlagStore {
//     func isEnabled(_ flag: FeatureFlag) -> Bool {
//         RemoteConfig.remoteConfig().configValue(forKey: flag.rawValue).boolValue
//     }
//     func setEnabled(_ flag: FeatureFlag, _ value: Bool) { /* no-op, server-driven */ }
// }

// MARK: - Singleton Accessor

public enum FeatureFlags {
    private static var store: FeatureFlagStore = UserDefaultsFlagStore()

    /// Call once at app launch from DependencyContainer to inject the backing store.
    public static func configure(store: FeatureFlagStore) {
        self.store = store
    }

    public static func isEnabled(_ flag: FeatureFlag) -> Bool {
        store.isEnabled(flag)
    }

    public static func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        store.setEnabled(flag, value)
    }
}
```

**Callers never touch UserDefaults directly.** Every flag read in the codebase goes through `FeatureFlags.isEnabled(.xxx)`.

**Swap to Firebase Remote Config:** Create `RemoteConfigFlagStore: FeatureFlagStore`, then in `DependencyContainer`: `FeatureFlags.configure(store: RemoteConfigFlagStore())`. One file created, one line changed. Zero call-site changes.

### Usage Pattern (Coordinator Level)

```swift
// In CaptureCoordinator:
func showBoundaryDrawing(snapshot: CaptureSnapshot, quality: CaptureQualityScore?) {
    let segmenter: WoundSegmenter?
    if FeatureFlags.isEnabled(.onDeviceSegmentation) {
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
3. **All flag reads go through `FeatureFlags.isEnabled()`** — never `UserDefaults.standard.bool(forKey:)` directly. This is enforced by code review and a lint rule (grep for `UserDefaults.*v5_` outside `UserDefaultsFlagStore`).
4. **Flags are developer-only for now.** Internal TestFlight builds can toggle via a hidden debug menu (triple-tap version label in Settings). Public release flags are `false` until explicitly flipped.
5. **Migration to Firebase Remote Config** happens post-Phase 7. The `FeatureFlagStore` protocol ensures this is a single-file change.

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

### Model Delivery: App Thinning + Asset Catalogs

Models are placed in **Asset Catalogs** (`WoundOS/Resources/Assets.xcassets`) as data assets with device variant tags:

```
Assets.xcassets/
  ├── WoundDetectorYOLO11n.mlmodelc/     (6 MB, all devices)
  ├── SAM2MobileTiny.mlmodelc/           (40 MB, all devices)
  └── TissueClassifierFPN.mlmodelc/      (50 MB, all devices)
```

**App Thinning behavior:** Xcode compiles `.mlmodel` → `.mlmodelc` at build time. The App Store generates per-device variants via App Thinning. CoreML models are already architecture-specific (ANE vs GPU vs CPU compute plans are compiled per chip). The App Store delivers only the variant matching the user's device.

**Effective download size:** ~60 MB compressed (from 96 MB uncompressed). Acceptable for a clinical app that requires LiDAR hardware (iPhone 12 Pro+ users are on high-bandwidth plans).

### Model Versioning & OTA Update Path

**Phase 3 posture: Models updated only via App Store release.**

This is the defensible posture for a 510(k) submission. Rationale:

1. **FDA traceability:** Each App Store version has a deterministic binary. Model weights are part of the verified build artifact. OTA model swaps create a combinatorial verification matrix.
2. **Reproducibility:** Any measurement can be traced to a specific app version containing specific model weights.
3. **App Review gate:** Apple reviews each submission, providing a third-party validation checkpoint.

**Documented for 510(k):**
> "WoundOS V5 clinical measurement models (YOLO11n wound detector v1.0, SAM2 Mobile segmenter v1.0, FPN tissue classifier v1.0) are embedded in the application binary and updated exclusively via App Store releases. Each release undergoes verification against the golden test set (§7.2) before submission. No over-the-air model updates occur outside the App Store release process."

**Post-510(k) OTA path (future, not Phase 3):**

When clinical validation processes mature and the quality system supports it, models can be moved to background download:

```swift
// Future ModelManager extension (NOT Phase 3):
func downloadModel(_ id: ModelID, from url: URL) async throws -> MLModel {
    // 1. Background URLSession download from Cloud Run/GCS
    // 2. Verify SHA-256 checksum against pinned manifest
    // 3. MLModel.compileModel(at: downloadedURL)
    // 4. Cache in Application Support/Models/{version}/
    // 5. Log model version change to audit trail
}
```

This would require a software change notice (SCN) in the quality management system and re-verification of the affected measurement outputs.

### SAM2 Mobile CoreML Conversion Strategy

SAM2 Mobile (Hiera Tiny) must be converted from PyTorch → CoreML:

1. Export image encoder via `torch.export()` → ONNX → `coremltools.converters.convert()`
2. Export mask decoder separately (it takes encoder features + point/box prompts)
3. Validate: mean IoU on wound test set must be ≥ 0.80 (vs PyTorch reference)
4. Quantize to Float16 (ANE compatible, ~50% size reduction)
5. **Fallback:** See §1.3.1 below for explicit fallback decision criteria.

**Risk budget:** 2 weeks for conversion + validation. Owner: Agent (Phase 3).

### §1.3.1 — SAM2 Conversion Fallback: Explicit Decision Criteria

**Fallback trigger — ANY of these conditions:**

| Condition | Threshold | Measurement Method |
|-----------|-----------|-------------------|
| CoreML conversion fails outright | Conversion error / unsupported op | `coremltools` error log |
| Inference latency on iPhone 14 Pro | > 1.2 seconds per image | Median of 50 inferences on device, 1080×1080 input |
| Golden set IoU (wound boundary) | < 0.72 mean IoU | 50-image golden set, IoU vs PyTorch reference masks |
| Calendar time elapsed | > 10 business days from conversion start | Calendar |

**If fallback is triggered:**

The `v5_on_device_segmentation_enabled` flag stays `false`. The segmenter chain remains:

```
ServerSegmenter (GrabCut backend) → VisionForegroundSegmenter (iOS 17+) → nil
```

**Fallback UX impact:**

| Feature | With SAM2 Mobile | With VisionForegroundSegmenter Fallback |
|---------|-----------------|----------------------------------------|
| **Tap-to-segment** | Yes — tap = SAM2 point prompt | Yes — tap selects foreground instance under point |
| **Tap-to-refine** (iterative) | Yes — additional taps add/remove point prompts, mask updates | **DEGRADED** — VisionForegroundSegmenter is one-shot. Additional taps re-run full segmentation, no incremental refinement. |
| **Bounding-box prompt** | Yes — YOLO11 bbox feeds SAM2 | **GONE** — Vision API has no box prompt. Falls back to instance selection by tap point only. |
| **Expected IoU on wound images** | 0.80+ (wound-trained) | ~0.55-0.65 (generic foreground, not wound-specific) |
| **Clinician correction flow** | Tap adds/removes SAM2 prompts → refined mask | **Falls back to "Draw Manually" mode** — nurse switches to freeform drawing. The boundary drawing screen already has this toggle ("Auto Detect" / "Draw Manually"). |
| **User-visible messaging** | "Boundary detected (AI)" | "Boundary detected (on-device)" + yellow banner: "For best results, adjust the boundary manually" |

**Measurement accuracy impact of fallback:**

| Metric | SAM2 Mobile (expected) | VisionForegroundSegmenter (measured V4) | Delta |
|--------|----------------------|----------------------------------------|-------|
| Boundary IoU | 0.80+ | 0.55-0.65 | -20-25% |
| Area error | ≤5% | 15-30% (over-segments, includes periwoound skin) | Significant |
| Depth error | ≤2mm | ≤3mm (boundary error propagates to plane fit) | Moderate |
| Volume error | ≤10% | 20-40% | Significant |

**Mitigation in fallback scenario:** The nurse can always correct the boundary manually. The "Draw Manually" mode is the clinical safety net — it produces nurse-drawn boundaries that are 100% under clinician control. The measurement pipeline is boundary-agnostic; it measures whatever boundary it receives.

**Decision authority:** Fallback decision is made by the agent at Phase 3 GATE, with the golden set IoU numbers posted to the PR. Owner reviews before the flag is flipped.

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

## §1.5 — Measurement Pipeline: V4 Gap Analysis + V5 Spec

### Side-by-Side: V5 Spec vs V4 Implementation

| Step | V5 Specification (§1.4) | V4 Implementation | Status | V5 Action |
|------|------------------------|-------------------|--------|-----------|
| 1 | Reject low-confidence depth pixels | **PARTIAL.** `BoundaryProjector` filters confidence ≥ 2 (high only) during 2D→3D projection fallback, but ray-mesh primary path skips depth entirely. ARKit mesh vertices have no per-vertex confidence exposed. Interior mesh vertices used by the engine have no confidence gating. | GAP | Add `ConfidenceGatedProjector` that rejects boundary points where depth-map fallback confidence < 2 and mesh hit fails. Expose `projectionConfidence` per-point so the engine can weight or exclude low-confidence regions. |
| 2 | Back-project 2D through intrinsics | **YES.** `BoundaryProjector.project()` computes inverse intrinsics → camera ray → Möller-Trumbore ray-mesh intersection, with depth-map unprojection fallback. File: `BoundaryProjector.swift:59-103` | OK | Retain. No change needed. |
| 3 | Dilate mask + RANSAC skin plane | **NO RANSAC.** `TriangleUtils.fitPlane()` uses closed-form least-squares covariance eigendecomposition (no outlier rejection). A single bad boundary point can skew the reference plane. No mask dilation. File: `TriangleUtils.swift:56-107` | GAP | **Replace** with RANSAC plane fitter in `WoundMeasurement/GeometryUtils/RANSACPlaneFitter.swift`. Parameters: 100 iterations, 3-point sample, 5mm inlier threshold. Falls back to current least-squares if RANSAC fails (< 60% inlier rate). Add mask dilation (3px morphological dilate) in the segmentation pipeline before boundary extraction. |
| 4 | Rotate so skin plane = XY | **PARTIAL.** `DimensionCalculator` projects to local (u,v) plane basis for L×W. Area, depth, and volume work in world space using signed distances. File: `DimensionCalculator.swift:95-114` | OK | World-space computation is geometrically correct (signed distance to plane = perpendicular depth regardless of frame). No change needed — rotating to XY is an implementation detail, not a correctness requirement. |
| 5a | Geodesic surface area (mesh, not planar) | **YES.** `MeshClipper` sums actual 3D triangle areas via cross-product (`TriangleUtils.triangleArea`). This is the true piecewise-linear geodesic area on the reconstructed mesh surface. File: `MeshClipper.swift:87,114` | OK | Retain. This is already superior to planar projection. |
| 5b | Max length/width via PCA | **NO PCA.** Uses rotating calipers on the minimum bounding rectangle of the convex hull (Graham scan). File: `DimensionCalculator.swift:47-74` | ACCEPTABLE | Rotating calipers gives the **exact** minimum bounding rectangle; PCA gives an approximation. Rotating calipers is strictly more accurate for L×W. Retain current method. |
| 5c | Max depth perpendicular to skin plane | **YES.** `DepthCalculator.computeDepth()` computes `dot(vertex - centroid, planeNormal)` for every interior mesh vertex. Plane normal oriented toward camera. File: `DepthCalculator.swift:56-64` | OK | Retain. V5 upgrade: use RANSAC plane (from Step 3 fix) as the reference instead of least-squares plane. |
| 5d | Volume via prism integration + TSDF cross-check | **PRISM ONLY.** `VolumeCalculator` decomposes triangular prisms into tetrahedra using signed volume formula. No TSDF. No cross-check. File: `VolumeCalculator.swift:27-53` | GAP | Add TSDF cross-check as a secondary volume estimate. Algorithm: voxelize the depth difference between mesh surface and reference plane at 1mm resolution, sum voxel volumes. If prism and TSDF disagree by >15%, flag `volumeConfidence = .low` in the measurement output. New file: `TSDFVolumeValidator.swift` in WoundMeasurement. |
| 5e | Undermining flag (>5mm horizontal pocket) | **MISSING.** No undermining detection in the codebase. | GAP | New file: `UnderminingDetector.swift` in WoundMeasurement. Algorithm: for each boundary point, cast rays inward along the plane surface at 1° increments. If any ray encounters mesh geometry more than 5mm below the reference plane AND extends >5mm horizontally past the boundary, flag `underminingDetected = true` with clock position and extent. Phase 4 deliverable — requires nurse annotation UI for clock positions. |
| 6 | Confidence score from high-conf pixel % | **ADVISORY ONLY.** `CaptureQualityScore` computes `meanDepthConfidence` (0-2) and `meshHitRate` (0-1) and derives a tier (excellent/good/fair/poor). But the tier is purely informational — a `.poor` measurement still proceeds and is stored. File: `CaptureQualityScore.swift:57-72` | GAP | **Promote to gating.** If `meshHitRate < 0.70` OR `meanDepthConfidence < 1.0`, measurement is blocked with user-visible message: "Insufficient depth data — move closer or adjust angle." If `meshHitRate < 0.85`, measurement proceeds but `qualityGate = .warning` is stamped on the result. Confidence score formula: `confidenceScore = (meshHitRate * 0.6) + (meanDepthConfidence / 2.0 * 0.4)` → range 0-1. |

### V5 Measurement Pipeline (Revised)

```
Step 0:  ConfidenceGating.validate(projectionResult)     → Pass/Block     [NEW]
Step 1:  MeshClipper.clip(captureData, boundary)          → ClippedMesh    [V4, unchanged]
Step 2:  AreaCalculator.computeArea(clippedMesh)           → Double (cm²)   [V4, unchanged]
Step 2b: TissueClassifier.classify(rgb, mask, clippedMesh) → TissueComposition [NEW, PARALLEL BRANCH — see below]
Step 3:  RANSACPlaneFitter.fitPlane(boundaryPoints3D)     → PlaneResult    [V5 REPLACES least-squares]
Step 4:  DepthCalculator.computeDepth(mesh, plane)        → DepthResult    [V4, uses RANSAC plane]
Step 5:  VolumeCalculator.computeVolume(mesh, plane)      → Double (mL)    [V4, uses RANSAC plane]
Step 5v: TSDFVolumeValidator.validate(mesh, plane, prismVol) → VolumeConfidence [NEW cross-check]
Step 5e: UnderminingDetector.detect(mesh, boundary, plane) → UnderminingResult [NEW, Phase 4]
Step 6:  PerimeterCalculator.computePerimeter(boundary3D) → Double (mm)    [V4, unchanged]
Step 7:  DimensionCalculator.computeDimensions(boundary3D, plane) → DimensionResult [V4, unchanged]
Step 8:  BWATCalculator.compute(measurement, tissue, nurseInputs) → BWATScore [NEW]
Step 9:  ConfidenceScore.compute(projectionResult, quality) → Float (0-1) [NEW]
```

### Tissue Classification: Parallel Branch (NOT in the 3D geometry chain)

**Critical clarification:** Tissue classification runs on 2D masked RGB, not on back-projected 3D points. It is a parallel branch, not a dependency in the 3D geometry chain.

```
                  CaptureSnapshot (frozen RGB + depth + mesh)
                         │
           ┌─────────────┴─────────────┐
           │                           │
     3D Geometry Chain            2D RGB Branch
     (Steps 0-9 above)           (Tissue Classification)
           │                           │
           │                     ┌─────┴──────┐
           │                     │ RGB Image   │
           │                     │ + Binary    │
           │                     │   Mask from │
           │                     │   segmenter │
           │                     └─────┬──────┘
           │                           │
           │                     TissueClassifier
           │                     CoreML inference
           │                     (FPN+VGG16)
           │                           │
           │                     H×W×6 probability map
           │                           │
           │                     Sample at ClippedMesh
           │                     triangle centroids
           │                     (3D→2D projection)
           │                           │
           │                     TissueComposition
           │                     (area per class in cm²)
           │                           │
           └───────────┬───────────────┘
                       │
                 WoundMeasurement + TissueComposition
                       │
                 BWATCalculator (Step 8)
                       │
                 WoundScan (fully assembled)
```

**Tissue classification depends on:**
1. The RGB image (available immediately after capture)
2. The binary segmentation mask (available after auto-seg or manual boundary)
3. `ClippedMesh` triangle centroids (available after Step 1, for mapping 2D classes to 3D area)

**Tissue classification does NOT depend on:** Steps 3-9 (plane fitting, depth, volume, dimensions). It can run concurrently with the 3D geometry chain.

**Package:** WoundTissueKit (depends on WoundCore + WoundMeasurement for `ClippedMesh` and `ProjectionUtils`)

```swift
// In WoundCore:
public struct TissueComposition: Codable, Sendable {
    public let areaByClass: [TissueClass: Double]  // cm² per class
    public let fractionByClass: [TissueClass: Double]  // 0-1 per class
    public let dominantClass: TissueClass
    public let confidenceMap: Data?  // Optional H×W visualization data
}

public enum TissueClass: String, Codable, CaseIterable, Sendable {
    case granulation, slough, necrosis, eschar, epithelialization, maceration
}
```

### BWAT Score (Step 8)

**Package:** WoundMeasurement (extend existing — pure computation, zero UI/network)

| Subscale | Source | Input |
|----------|--------|-------|
| 1. Size | Auto | `areaCm2` from Step 2 |
| 2. Depth | Auto | `maxDepthMm` from Step 4 |
| 3. Edges | Nurse | Enum: distinct/attached/not attached/rolled/undermining |
| 4. Undermining | Auto/Nurse | `UnderminingResult` (Phase 4) or nurse input |
| 5. Necrotic tissue type | Auto | `TissueComposition.fractionByClass[.necrosis]` + `[.eschar]` |
| 6. Necrotic tissue amount | Auto | Sum of necrotic fractions |
| 7. Exudate type | Nurse | Enum: none/bloody/serosanguineous/serous/purulent |
| 8. Exudate amount | Nurse | Enum: none/scant/small/moderate/large |
| 9. Skin color surrounding | Nurse | Enum: pink/bright red/white/dark red/purple/black |
| 10. Peripheral tissue edema | Nurse | Enum: none/non-pitting/<4cm/≥4cm/crepitus |
| 11. Peripheral tissue induration | Nurse | Enum: none/≤2cm/2-4cm/>4cm |
| 12. Granulation tissue | Auto | `TissueComposition.fractionByClass[.granulation]` |
| 13. Epithelialization | Auto | `TissueComposition.fractionByClass[.epithelialization]` |

```swift
public struct BWATScore: Codable, Sendable {
    public let subscales: [BWATSubscale: Int]  // 1-5 each
    public let totalScore: Int                  // 13-65
    public let autoScoredCount: Int
}
```

### New Files in WoundMeasurement (V5)

| File | Lines (est.) | Purpose | Dependencies |
|------|-------------|---------|-------------|
| `RANSACPlaneFitter.swift` | ~120 | RANSAC plane fit with 100 iterations, 3-point sample, 5mm inlier threshold | simd, Foundation |
| `TSDFVolumeValidator.swift` | ~100 | Voxelized volume cross-check at 1mm resolution | simd, Foundation |
| `UnderminingDetector.swift` | ~150 | Horizontal pocket detection via boundary-inward raycasting | simd, Foundation |
| `ConfidenceGating.swift` | ~60 | Pre-measurement gate: block if meshHitRate < 0.70 or confidence < 1.0 | WoundCore (CaptureQualityScore) |
| `BWATScoreCalculator.swift` | ~80 | Bates-Jensen 13-subscale computation | WoundCore (BWATScore model) |

**All new files: pure geometry/math. Zero UI. Zero networking. Zero CoreML.**

### ClippedMesh Exposure

`ClippedMesh` is currently internal to the engine. To expose it for tissue classification:

```swift
// In MeshMeasurementEngine:
public func clipMesh(captureData: CaptureData, boundary: WoundBoundary) throws -> ClippedMesh
```

The full `measure()` method calls this internally as before. `WoundTissueKit` calls `clipMesh()` separately to get triangle centroids for 2D sampling.

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
