# WoundOS V5 — Phase 0 Audit Report

**Date:** 2026-04-21
**Branch:** `claude/clinical-measurement-arkit-BvFM7`
**Auditor:** Claude Opus 4.6 (AI agent)
**Status:** GATE 0 — Awaiting sign-off

---

## 0.1 — iOS Codebase Audit

### 0.1.1 Repository Structure (Top 3 Levels)

```
/Users/rentamac/Desktop/WoundOS-V3/
├── .git/
├── .gitignore
├── backend/
│   ├── app/
│   │   ├── api/           # FastAPI routes + Pydantic schemas
│   │   ├── core/          # Auth, config, database
│   │   ├── models/        # SQLAlchemy ORM (scan, patient)
│   │   ├── services/      # SAM 2, clinical summary, storage, pubsub
│   │   ├── workers/       # Async SAM 2 processor, Pub/Sub handler
│   │   └── main.py        # FastAPI entrypoint
│   ├── migrations/        # Alembic DB migrations
│   ├── scripts/           # deploy.sh, setup_gcp.sh, local_setup.sh
│   ├── tests/             # pytest test_api.py
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── requirements.txt
└── ios/
    ├── Packages/
    │   ├── WoundAutoSegmentation/   # On-device + server segmentation
    │   ├── WoundBoundary/           # Canvas drawing, projector, validator
    │   ├── WoundCapture/            # ARSessionManager, quality monitor
    │   ├── WoundCore/               # Models, protocols, extensions
    │   ├── WoundMeasurement/        # 6-step mesh measurement engine
    │   └── WoundNetworking/         # API client, auth, upload manager
    ├── WoundOS/
    │   ├── App/             # AppDelegate, SceneDelegate, DependencyContainer
    │   ├── Coordinators/    # AppCoordinator, CaptureCoordinator, ScanListCoordinator
    │   ├── Scenes/          # Capture, BoundaryDrawing, Measurement, ScanList, ScanDetail
    │   ├── Views/           # HealthStyleComponents, WoundImageOverlayView
    │   ├── Utilities/       # CrashLogger
    │   └── Resources/       # Info.plist, Assets.xcassets
    ├── WoundOS.xcodeproj/
    ├── PLAN.md
    └── docs/                # This audit
```

### 0.1.2 Xcode Project & Targets

| Item | Value |
|------|-------|
| **Project file** | `ios/WoundOS.xcodeproj` (objectVersion 60, Xcode 15+) |
| **Primary target** | `WoundOS` (iOS application) |
| **Test targets** | **None configured in scheme.** The WoundOS scheme has no test action. SPM packages have test targets but they are not wired into the scheme. |
| **Schemes** | 1: `WoundOS` |
| **Package dependencies** | 6 local SPM packages (see below) |
| **CocoaPods / Carthage** | None |

### 0.1.3 Third-Party Dependencies

**iOS: Zero external dependencies.** All 6 packages are local SPM packages under `Packages/`:

| Package | Platform | Depends On | Has Tests |
|---------|----------|-----------|-----------|
| WoundCore | iOS 16+ | — | Yes |
| WoundCapture | iOS 16+ | WoundCore | No |
| WoundBoundary | iOS 16+ | WoundCore | No |
| WoundMeasurement | iOS 16+ | WoundCore | Yes |
| WoundAutoSegmentation | iOS 16+ | WoundCore | Yes |
| WoundNetworking | iOS 16+ | WoundCore | Yes |

**Backend Python dependencies (requirements.txt):**

| Package | Version | Status |
|---------|---------|--------|
| FastAPI | 0.115.6 | Current |
| Uvicorn | 0.34.0 | Current |
| Pydantic | 2.10.4 | Current (v2) |
| SQLAlchemy | 2.0.36 | Current |
| asyncpg | 0.30.0 | Current |
| firebase-admin | 6.6.0 | Current |
| google-cloud-storage | 2.19.0 | Current |
| google-cloud-pubsub | 2.28.0 | Current |
| anthropic | 0.42.0 | Current |
| opencv-python-headless | 4.10.0.84 | Current |
| numpy | >=1.26.0 | Current |
| Pillow | >=10.0.0 | Current |
| PyJWT | 2.10.1 | Current |

**No deprecated or unmaintained dependencies found.**

### 0.1.4 Deployment Target & Toolchain

| Setting | Current | V5 Requirement | Status |
|---------|---------|----------------|--------|
| `IPHONEOS_DEPLOYMENT_TARGET` | **16.0** | **17.0** (18.0 preferred) | MUST BUMP |
| `SWIFT_VERSION` | **5.0** (pbxproj) | **5.9+** | MUST BUMP |
| Swift tools version | 5.9 (Package.swift) | 5.9+ | OK |
| Xcode | 15+ (objectVersion 60) | 15+ | OK |
| SPM platform | `.iOS(.v16)` (all packages) | `.iOS(.v17)` | MUST BUMP |

**Mismatch:** The pbxproj says `SWIFT_VERSION = 5.0` but packages declare `swift-tools-version: 5.9`. The project should be updated to `SWIFT_VERSION = 5.0` → `6.0` (or at minimum `5.9`) for consistency and to unlock Swift Concurrency strict checking.

### 0.1.5 Framework Usage

| Framework | Files | Usage |
|-----------|-------|-------|
| **ARKit** | 4 | `ARSCNView`, `ARSession`, `ARWorldTrackingConfiguration`, scene depth, mesh anchors |
| **CoreML** | 1 | `WoundAmbitSegmenter` (FUSegNet model — model file NOT bundled, commented out) |
| **Vision** | 4 | `VNGenerateForegroundInstanceMaskRequest` (iOS 17+), `VNDetectContoursRequest`, contour extraction |
| **AVFoundation** | 0 | Not used — ARKit provides the camera feed directly |
| **RealityKit / SceneKit** | 0 | Not used (ARSCNView for display only, not scene building) |
| **Metal / MPS** | 0 | Not used |
| **HealthKit** | 0 | Not used |
| **Combine** | 10 | State management, publisher-subscriber bindings throughout |
| **SwiftUI** | 0 | Pure UIKit + Combine |
| **simd** | 11 | 3D geometry, matrix math, SIMD3/SIMD2 throughout measurement pipeline |
| **Security** | 1 | Keychain token storage |

**Networking:** Custom `WoundOSClient` actor wrapping `URLSession.shared`. Bearer auth via `AuthProvider` actor with Keychain persistence, coalesced token refresh, exponential backoff retry.

**Authentication:** `StubFirebaseAuth` returns hardcoded `"stub-firebase-id-token"` → backend exchanges for JWT. **No real Firebase SDK integrated on iOS side.** Firebase Admin SDK is server-side only.

### 0.1.6 Wound Capture Flow (Screen-by-Screen)

**Tab 1: Scans** (ScanListCoordinator)

| Screen | ViewController | Purpose |
|--------|---------------|---------|
| Scan List | `ScanListViewController` | Lists saved scans, pull-to-refresh, crash log export |
| Scan Detail | `ScanDetailViewController` | Read-only view of scan measurements + image |

**Tab 2: Capture** (CaptureCoordinator) — Primary Clinical Workflow

| Step | Screen | ViewController | ViewModel | What Happens |
|------|--------|---------------|-----------|--------------|
| 1 | AR Capture | `CaptureViewController` | `CaptureViewModel` | Full-screen ARSCNView with LiDAR. 4-gate readiness check (tracking, stability, distance 15-30cm, mesh quality). Distance indicator bar. Framing guide reticle. Tap → freeze AR frame → `CaptureSnapshot`. |
| 2 | Boundary Drawing | `BoundaryDrawingViewController` | `BoundaryDrawingViewModel` | Frozen image + BoundaryCanvasView overlay. Toggle: "Auto Detect" / "Draw Manually". Auto: tap center → ServerSegmenter (SAM 2 backend, fallback → VisionForegroundSegmenter). Manual: freeform trace. Polygon area sanity check (reject >40% of image). Pulsing ring animation during detection. |
| 3 | Measurement Results | `MeasurementResultViewController` | `MeasurementResultViewModel` | 6-step MeshMeasurementEngine: clip → area → depth → volume → perimeter → dimensions. Displays: area (cm²), perimeter (cm), L×W (cm), max/mean depth (mm), volume (mL), PUSH Score 3.0. "Save & Upload" button → local JSON + UploadManager queue. |

### 0.1.7 Calibration Sticker Workflow

**FINDING: No sticker-based calibration exists in the current codebase.**

Searched for: "sticker", "calibration", "fiducial", "marker", "19.05", "Avery", "ppc" (pixels-per-cm). Zero results in iOS code.

The current pipeline uses **ARKit LiDAR + camera intrinsics** as the metric anchor. Depth comes from `ARDepthData` (scene depth frame semantics). Scale comes from the calibrated intrinsics matrix stored in `CaptureSnapshot.cameraIntrinsics`.

**The sticker workflow lives on the separate CarePlix WoundAI API** (`wound-ai-api-...run.app`), which accepts `frontend_ppc` (pixels per cm from sticker detection) in its `/analyze` endpoint. The iOS app does NOT call this API — it calls `woundos-api-...run.app` (the V4 backend) which has no sticker flow.

**V5 blast radius for sticker replacement: ZERO.** The current iOS app already uses LiDAR. The sticker flow is a separate product/API.

### 0.1.8 API Endpoints Called by iOS App

**Base URL (staging):** `https://woundos-api-333499614175.us-central1.run.app`
**API version prefix:** `/v1`
**Auth:** Bearer JWT (obtained via Firebase ID token exchange)

| # | Method | Path | Request | Response | Screen(s) |
|---|--------|------|---------|----------|-----------|
| 1 | GET | `/health` | — | `{"status":"ok","service":"woundos-api"}` | App launch (connectivity check) |
| 2 | POST | `/v1/auth/token` | `{"firebase_token":"..."}` | `{"token":"jwt...","expires_in":3600}` | AuthProvider (on demand) |
| 3 | POST | `/v1/segment` | Multipart: image (JPEG), tap_point, image_width, image_height | `{"polygon":[[x,y],...],"confidence":0.85,"model_version":"sam2.1-hiera-large"}` | BoundaryDrawing (Auto Detect) |
| 4 | POST | `/v1/scans/upload` | Multipart: rgb_image, depth_map, mesh, metadata (JSON) | `{"scan_id":"uuid","upload_status":"pending","gcs_paths":{...}}` | MeasurementResult (Save & Upload) |
| 5 | GET | `/v1/scans/{scanId}` | — | Full `ScanResponse` with backend-computed fields | ScanDetail |
| 6 | GET | `/v1/scans/{scanId}/status` | — | `{"scan_id":"...","processing_status":"completed|processing|pending|failed",...}` | UploadManager polling (5s × 18 = 90s) |
| 7 | GET | `/v1/patients/{patientId}/scans` | — | `{"scans":[...],"total":N}` | ScanList |
| 8 | PATCH | `/v1/scans/{scanId}/review` | `{"review_status":"...","reviewer_id":"...","notes":"..."}` | Updated scan | (Not yet exposed in UI) |

### 0.1.9 Build, Signing & TestFlight Configuration

| Setting | Value |
|---------|-------|
| Bundle ID | `com.woundos.clinical` |
| Development Team | `829CPR87G4` |
| Code Sign Style | Automatic |
| Current Version | **4.0.0** |
| Current Build | **5** |
| App Store Connect | Active (TestFlight uploads successful via Xcode Organizer) |
| TestFlight Track | Internal (no external testers configured) |
| `ITSAppUsesNonExemptEncryption` | `false` |
| Supported Orientations | Portrait only |
| Required Capabilities | `arkit` |

### 0.1.10 Test Suite

**Result: No tests configured in the Xcode scheme.**

```
xcodebuild test → "Scheme WoundOS is not currently configured for the test action."
```

The SPM packages declare test targets (WoundCoreTests, WoundMeasurementTests, WoundAutoSegmentationTests, WoundNetworkingTests) but they are **not wired into the WoundOS scheme's Test action**. Coverage: unknown / 0%.

---

## 0.2 — Backend Audit

### 0.2.1 WoundOS Backend API (`woundos-api-...run.app`)

**Health:** `GET /health` → `{"status":"ok","service":"woundos-api"}`
**OpenAPI:** Available at `/openapi.json` (3.1.0)
**Docs:** Disabled in production (`DEBUG=false`)

| # | Method | Path | Auth | Purpose | Latency (est.) |
|---|--------|------|------|---------|----------------|
| 1 | GET | `/health` | None | Health probe | <100ms |
| 2 | GET | `/` | None | Root info | <100ms |
| 3 | POST | `/v1/auth/token` | None | Firebase→JWT exchange | ~200ms |
| 4 | POST | `/v1/segment` | Bearer | Real-time SAM 2 segmentation | 2-8s (SAM 2) / <1s (GrabCut fallback) |
| 5 | POST | `/v1/scans/upload` | Bearer | Multipart scan upload → GCS + DB + Pub/Sub | 1-3s |
| 6 | GET | `/v1/scans/{scan_id}` | Bearer | Fetch full scan + backend fields | ~200ms |
| 7 | GET | `/v1/scans/{scan_id}/status` | Bearer | Poll processing status | ~100ms |
| 8 | GET | `/v1/patients/{patient_id}/scans` | Bearer | List patient scans | ~200ms |
| 9 | PATCH | `/v1/scans/{scan_id}/review` | Bearer | Submit clinician review | ~200ms |
| 10 | POST | `/pubsub/push` | **None (VULNERABILITY)** | Pub/Sub push handler for async processing | N/A |

### 0.2.2 Models Loaded on WoundOS Backend

| Model | Status | Location | Notes |
|-------|--------|----------|-------|
| **SAM 2.1 Hiera Large** | **Code exists, model NOT deployed.** Checkpoint expected at `/app/models/sam2.1_hiera_large.pt`. `segment_anything_2` not in requirements.txt. | `sam2_service.py` | Falls back to GrabCut (OpenCV) when unavailable. |
| **Claude Haiku 4.5** | **Integrated and functional.** Requires `ANTHROPIC_API_KEY` env var. | `clinical_summary.py` | Generates narrative, trajectory, key findings, recommendations. |
| **OpenCV GrabCut** | **Active fallback.** CPU-only heuristic segmentation. | `sam2_service.py` | Used when SAM 2 unavailable. |

**SAM 2 async worker is STUBBED:** `sam2_processor.py` returns the nurse boundary with ±2% random perturbation — NOT real SAM 2 inference. Agreement metrics and FWA signals are meaningless until real model is wired.

### 0.2.3 CarePlix WoundAI API (`wound-ai-api-...run.app`) — Separate Service

**Health:** `{"status":"healthy","version":"3.2.0","project":"careplix-woundos","foot_model":true,"multi_model":true,"tissue_model":true}`

| # | Method | Path | Auth | Purpose |
|---|--------|------|------|---------|
| 1 | GET | `/health` | None | Health + model status |
| 2 | GET | `/wound_types` | None | Supported wound type classifications (7 types) |
| 3 | POST | `/analyze` | None (!) | Upload image + metadata for AI analysis |
| 4 | GET | `/history/{patient_id}` | None | Patient history |

**`/analyze` request schema:**
- `file` (image upload)
- `wound_type` (string, default "unknown") — options: diabetic_foot, venous_leg, pressure, surgical, arterial, burn, unknown
- `patient_id` (string)
- `visit_note` (string)
- `frontend_ppc` (float) — **pixels-per-cm from sticker detection. THIS IS THE STICKER FLOW.**

**Models deployed:**
- `foot_model` — Diabetic foot ulcer segmentation (Dice 0.85, this is `boundary_seg.onnx`)
- `multi_model` — General wound segmentation (Dice 0.69)
- `tissue_model` — Tissue classification (mIoU 0.3172, this is `tissue_seg.onnx`)

**V5 note:** This service is the sticker-based V2 pipeline. V5 replaces the need for `frontend_ppc` with LiDAR depth. The models here (`boundary_seg.onnx`, `tissue_seg.onnx`) are candidates for cloud fallback in V5's tissue classification pipeline.

### 0.2.4 Related GCP Services

| Service | URL | Purpose | V5 Collision Risk |
|---------|-----|---------|-------------------|
| WoundOS Backend | `woundos-api-...run.app` | V4 scan pipeline | V5 adds `/v5/*` endpoints — NO collision |
| CarePlix WoundAI | `wound-ai-api-...run.app` | V2 sticker pipeline | Separate service — NO collision |
| Digitize (Qwen2.5-VL) | Unknown URL | Document digitization | Different service — NO collision |
| BCAP API | Unknown URL | Unknown | Different service — NO collision |
| Eczema AI API | Unknown URL | Eczema analysis | Different service — NO collision |

### 0.2.5 GCS Buckets

| Bucket | Purpose | Confirmed |
|--------|---------|-----------|
| `woundos-scans-dev` | V4 scan storage (staging) | Referenced in code |
| `woundos-scans-prod` | V4 scan storage (production) | Referenced in code |

**Could not inspect `gs://careplix-*` directly** — requires `gcloud` auth which is not available in this session. This is a risk/unknown.

### 0.2.6 MedGemma 4B

**NOT deployed.** Zero references in either backend codebase. This is a V5 dependency that must be stood up (likely Vertex AI endpoint or dedicated Cloud Run with GPU).

---

## 0.3 — Data Audit

### 0.3.1 Firebase / Firestore

**FINDING: No Firebase SDK on iOS. No Firestore anywhere.**

The backend uses `firebase-admin` SDK (Python) for **token verification only** — it validates Firebase ID tokens sent by the iOS app. There is no Firestore database. All structured data lives in **Cloud SQL (PostgreSQL 16)**.

The iOS app has a `StubFirebaseAuth` that returns `"stub-firebase-id-token"`. In staging, the backend accepts any token when `FIREBASE_PROJECT_ID` is empty. In production, real Firebase Auth would be needed.

### 0.3.2 Current Schema for Wound Records

**PostgreSQL tables (2):**

**`patients`** — Lightweight patient reference
| Column | Type | Notes |
|--------|------|-------|
| id | String (PK) | Patient identifier |
| facility_id | String (indexed) | Healthcare facility |
| created_at | DateTime(TZ) | Row creation |

**`scans`** — Comprehensive wound capture record (29+ columns)

| Category | Columns |
|----------|---------|
| Identity | `id` (UUID PK), `patient_id` (FK indexed), `nurse_id` (indexed), `facility_id` (indexed), `captured_at` |
| Processing | `upload_status` (enum: pending/processing/completed/failed) |
| GCS paths | `rgb_image_path`, `depth_map_path`, `mesh_path`, `metadata_path` |
| Camera | `image_width`, `image_height`, `depth_width`, `depth_height`, `camera_intrinsics` (Float[]), `camera_transform` (Float[]), `device_model`, `lidar_available` |
| Boundary | `boundary_type`, `boundary_source`, `boundary_points_2d` (JSONB), `tap_point` |
| Measurements | `area_cm2`, `max_depth_mm`, `mean_depth_mm`, `volume_ml`, `length_mm`, `width_mm`, `perimeter_mm`, `processing_time_ms` |
| PUSH Score | `push_total_score`, `push_length_width_cm2`, `exudate_amount`, `tissue_type` |
| Quality | `tracking_stable_seconds`, `capture_distance_m`, `mesh_vertex_count`, `mean_depth_confidence`, `mesh_hit_rate`, `angular_velocity` |
| Backend AI (JSONB) | `shadow_boundary`, `shadow_measurement`, `agreement_metrics`, `clinical_summary`, `fwa_signals` |
| Review | `review_status`, `reviewer_id`, `review_notes`, `reviewed_at` |
| Timestamps | `created_at`, `updated_at` |

### 0.3.3 Authentication Provider & Token Flow

```
iOS StubFirebaseAuth → "stub-firebase-id-token"
       ↓
POST /v1/auth/token  (firebase_token → JWT exchange)
       ↓
Backend verify_firebase_token()
  - Production: firebase_admin.auth.verify_id_token()
  - Development: accepts any token (FIREBASE_PROJECT_ID empty)
       ↓
Backend create_access_token() → HS256 JWT (3600s)
       ↓
iOS AuthProvider caches in Keychain
  - Service: "com.woundos.api"
  - Account: "bearer-token"
  - Accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
       ↓
All API calls: Authorization: Bearer <jwt>
```

### 0.3.4 HealthKit

**Not used.** Zero references to `HKHealthStore`, `HKSampleType`, or HealthKit entitlements in the entire codebase. This is entirely greenfield for V5.

---

## iOS Data Models (WoundCore Package)

| Model | Key Fields | Notes |
|-------|-----------|-------|
| `WoundScan` | id, patientId, nurseId, facilityId, capturedAt, captureData, nurseBoundary, primaryMeasurement, pushScore, shadowBoundary?, shadowMeasurement?, agreementMetrics?, fwaSignals?, clinicalSummary?, uploadStatus, reviewStatus | Top-level aggregate |
| `CaptureData` | rgbImageData, depthMapData, confidenceMapData, meshVerticesData, meshFacesData, meshNormalsData, cameraIntrinsics, cameraTransform, deviceModel, lidarAvailable | Frozen ARKit frame |
| `WoundBoundary` | boundaryType (polygon/freeform), source (nurse_drawn/auto_vision/sam2/clinician_review), points2D, projectedPoints3D?, tapPoint? | 2D+3D boundary |
| `WoundMeasurement` | areaCm2, maxDepthMm, meanDepthMm, volumeMl, lengthMm, widthMm, perimeterMm, qualityScore?, source, computedOnDevice, processingTimeMs | Clinical measurements |
| `PUSHScore` | lengthTimesWidthCm2, exudateAmount, tissueType, totalScore (0-17) | PUSH 3.0 scoring |
| `CaptureQualityScore` | trackingStableSeconds, captureDistanceM, meshVertexCount, meanDepthConfidence, meshHitRate, angularVelocityRadPerSec, tier | Quality metadata |
| `AgreementMetrics` | iou, diceCoefficient, areaDeltaPercent, depthDeltaMm, volumeDeltaMl, centroidDisplacementMm, samConfidence, isFlagged | Nurse vs AI comparison |
| `ClinicalSummary` | narrativeSummary, trajectory, keyFindings, recommendations, modelVersion | Claude-generated |
| `FWASignal` | nurseBaselineAgreement, woundSizeOutlier, copyPasteRisk, longitudinalConsistency, overallRiskScore, triggeredFlags | Fraud detection |

---

## V5 Blast Radius

### Files That MUST Change

| File / Module | Change Required |
|--------------|-----------------|
| `WoundOS.xcodeproj/project.pbxproj` | Bump deployment target 16→17, Swift version 5.0→5.9+, add new package references |
| All 6 `Package.swift` files | Bump `.iOS(.v16)` → `.iOS(.v17)` |
| `Info.plist` | Add HealthKit usage description, bump version to 5.0.0, add `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` |
| `DependencyContainer.swift` | Add feature flag checks, wire new modules (WoundTissueKit, HealthKit, etc.) |
| `CaptureCoordinator.swift` | Add Scan Mode flow (Object Capture Area Mode), consent screen routing |
| `CaptureViewController.swift` | Add sweet-spot distance ring (26-35cm), confidence heatmap overlay, scan mode toggle |
| `CaptureViewModel.swift` | Add scan mode state, Object Capture session management |
| `BoundaryDrawingViewController.swift` | Add tap-to-refine (SAM2 point prompts), tissue overlay toggle |
| `BoundaryDrawingViewModel.swift` | Wire YOLO → SAM2 on-device pipeline, tap-to-refine logic |
| `MeasurementResultViewController.swift` | Add tissue composition display, BWAT score, MedGemma narrative, undermining flag |
| `MeasurementResultViewModel.swift` | Add tissue classification call, backend narrative request, BWAT calculation |
| Backend `routes.py` | Add `/v5/measurements`, `/v5/trajectories/{patient_id}`, `/v5/registrations` |
| Backend `schemas.py` | Add V5 Pydantic models |
| Backend `requirements.txt` | Add MedGemma client, Open3D (ICP registration) |

### Files That SHOULD NOT Change (Stable)

| File / Module | Why |
|--------------|-----|
| `WoundCore` models | Extend, don't mutate. Add new fields as optional. |
| `WoundNetworking/APIClient.swift` | Add new methods, don't change existing ones. |
| `WoundNetworking/AuthProvider.swift` | Auth flow unchanged. |
| `WoundNetworking/UploadManager.swift` | Upload flow unchanged (V5 captures use same upload path). |
| `WoundBoundary/BoundaryCanvasView.swift` | Drawing mechanics unchanged. |
| `WoundBoundary/BoundaryProjector.swift` | 2D→3D projection unchanged. |
| `WoundMeasurement/MeshMeasurementEngine.swift` | Existing 6-step pipeline unchanged (V5 adds new steps alongside). |
| Backend existing endpoints | V5 uses `/v5/` prefix — no collision with `/v1/`. |

---

## V5 Greenfield (New Files / Modules / Services)

### New Swift Packages

| Package | Purpose | Key Types |
|---------|---------|-----------|
| `WoundCaptureKit` | ARKit session wrapper, guided capture UI, CaptureBundle | `LiDARCaptureSession`, `CaptureBundle`, `GuidedCaptureView` |
| `WoundSegmentationKit` | On-device YOLO11 + SAM2 Mobile pipeline | `WoundDetector`, `WoundSegmenter2`, `SegmentationResult` |
| `WoundTissueKit` | Tissue classification (FPN+VGG16 CoreML) | `TissueClassifier`, `TissueComposition` |
| `WoundSyncKit` | Cloud upload, longitudinal storage, HealthKit | `WoundSyncManager`, `HealthKitWriter`, `TrajectoryStore` |
| `WoundUI` | SwiftUI screens (capture, results, timeline, assessment) | `CaptureView`, `ResultsView`, `TimelineView`, `ConsentView` |
| `WoundBackendClient` | Thin client for V5 Cloud Run endpoints | `V5Client`, `V5Measurement`, `V5Trajectory` |
| `WoundModels` | On-demand CoreML model bundle | YOLO11.mlpackage, SAM2Mobile.mlpackage, TissueClassifier.mlpackage |

### New Backend Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/v5/measurements` | Accept capture bundle + measurements, return PUSH/BWAT scores, MedGemma narrative, CPT/ICD-10 |
| GET | `/v5/trajectories/{patient_id}` | Longitudinal wound series |
| POST | `/v5/registrations` | ICP-based wound registration (mesh alignment) |

### New Backend Services

| Service | Technology | Purpose |
|---------|-----------|---------|
| MedGemma 4B | Vertex AI or dedicated Cloud Run (GPU) | Clinical narrative + dressing recommendation + CPT/ICD-10 |
| ICP Registration | Open3D (CPU Cloud Run) | Longitudinal wound alignment |
| PUSH Scorer | Pure Python | PUSH 3.0 (0-17) |
| BWAT Scorer | Pure Python | Bates-Jensen (13-65) |

### New iOS Files

| File | Purpose |
|------|---------|
| `FeatureFlagManager.swift` | Firebase Remote Config wrapper (5 flags) |
| `ConsentViewController.swift` | Pre-capture consent screen |
| `TissueOverlayView.swift` | 6-class tissue heatmap overlay |
| `TimelineViewController.swift` | Horizontal scroll of historical captures |
| `TrendChartView.swift` | Swift Charts for area, depth, PUSH over time |
| `WoundAssessmentViewController.swift` | Clinical assessment form (location, type, exudate, etc.) |
| `FHIRExporter.swift` | FHIR Observation export for EMR |

---

## Risks and Unknowns

### Critical

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| 1 | **SAM 2 not deployed on backend.** The async worker is stubbed. Real-time `/v1/segment` falls back to GrabCut. | Auto-detection quality is poor (user-reported: selects wrong objects). | Must deploy SAM 2 checkpoint to Cloud Run (GPU instance) or convert to CoreML for on-device. |
| 2 | **MedGemma 4B not deployed anywhere.** Zero references in codebase. | V5 narrative/dressing/CPT features blocked. | Must provision Vertex AI endpoint or GPU Cloud Run. Need model access from Google. |
| 3 | **Firebase Auth is stubbed on iOS.** `StubFirebaseAuth` always returns a hardcoded token. | Real user authentication does not work. | Must integrate Firebase Auth SDK or Sign in with Apple before V5 production. |
| 4 | **No test suite runs.** Xcode scheme has no test action. SPM test targets exist but aren't wired. | No regression safety net. | Wire test targets into scheme before any V5 code lands. |

### High

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| 5 | **Pub/Sub push endpoint is unauthenticated.** Anyone can trigger scan reprocessing. | DoS / data manipulation risk. | Add OIDC token verification before production. |
| 6 | **GCS bucket contents unknown.** Could not inspect `gs://careplix-*` without gcloud auth. | May miss existing model artifacts or patient data buckets. | Need GCP console access or `gcloud` auth to enumerate. |
| 7 | **No `NSFileProtectionComplete` on local scan storage.** JSON files in Documents/ use default iOS protection. | PHI at rest may not meet HIPAA encryption requirements. | Must add explicit file protection or migrate to encrypted CoreData/SwiftData. |
| 8 | **SWIFT_VERSION mismatch.** pbxproj says 5.0, packages say 5.9. | Potential build issues with strict concurrency checking. | Align to 5.9 or 6.0. |

### Medium

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| 9 | **CarePlix WoundAI `/analyze` has no auth.** | Endpoint publicly accessible without authentication. | Out of V5 scope but should be flagged to security team. |
| 10 | **Object Capture Area Mode requires iOS 18+.** | Scan Mode will be unavailable on iOS 17 devices. | Feature-flag Scan Mode; Single-Shot Mode works on iOS 17+. |
| 11 | **On-demand model download.** YOLO11 + SAM2 + Tissue models (~100-200MB total). | First-launch experience degraded on slow networks. | Show download progress, allow retry, cache aggressively. |
| 12 | **CoreML conversion of SAM2 Mobile.** No verified community conversion exists. | May require significant engineering effort. | Budget 1-2 weeks for conversion + validation. Fallback: server-only SAM 2. |

### Unknown (Need Clarification)

| # | Question |
|---|----------|
| 1 | What is the GCP project ID for the `careplix-woundos` project? Is it the same `333499614175` as the Cloud Run services? |
| 2 | Where is the wound image training dataset stored? Need it for YOLO11 fine-tuning and golden set validation. |
| 3 | Is there a separate backend repo, or is `backend/` in this mono-repo the only backend? |
| 4 | What Firebase project is used for auth? Need project ID to configure the iOS Firebase SDK. |
| 5 | Is the CarePlix WoundAI API (`wound-ai-api-...`) going to be deprecated, or will V5 coexist? |
| 6 | What are the `digitize`, `bcap-api`, and `eczema-ai-api` service URLs? Need to confirm no URL prefix collisions. |
| 7 | Is there an existing Apple Developer account App Store Connect API key for CI/CD? Currently TestFlight uploads require manual Xcode Organizer clicks. |
| 8 | What is the target date for FDA 510(k) submission? This affects the traceability matrix timeline. |

---

**GATE 0 CHECKPOINT.** This audit report is complete. Awaiting your sign-off before proceeding to Phase 1 (Architecture Plan).
