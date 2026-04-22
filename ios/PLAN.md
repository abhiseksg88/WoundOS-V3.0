# WoundOS V4 — Clinical Wound Measurement Upgrade

## Goal
Transform WoundOS from a prototype into a clinical-grade wound documentation tool
with server-side AI segmentation, guided capture, and a proper nurse workflow.

---

## Phase 1: Server-Side SAM 2 Segmentation

### Backend (Python/FastAPI on GCP Cloud Run)

**1a. New `POST /v1/segment` endpoint** (`app/api/routes.py`)
- Accepts: multipart `image` (JPEG) + JSON `tap_point` ([x,y] in pixel coords) + `image_width` + `image_height`
- Returns: `{ polygon: [[x,y],...], confidence: 0.95, model_version: "sam2-hiera-large-v1" }`
- Auth: Bearer token required (reuse existing `get_current_user`)
- Timeout: 30s max

**1b. SAM 2 inference service** (`app/services/sam2_service.py`)
- Install `segment-anything-2` + `torch` in the Docker image
- Load SAM 2 `sam2_hiera_large` checkpoint on startup (cached in memory)
- Pipeline: decode JPEG → resize → SAM 2 with point prompt → binary mask → contour extraction → polygon simplification
- GPU: Use Cloud Run with GPU (L4) or fall back to CPU with `sam2_hiera_tiny` for cost control
- Polygon output: normalized [0,1] coordinates, simplified to ~40-80 vertices

**1c. Update `app/api/schemas.py`**
- Add `SegmentationRequest` and `SegmentationResponse` Pydantic models

**1d. Update Docker/requirements**
- Add `torch`, `segment-anything-2`, `opencv-python-headless` to requirements
- Download SAM 2 checkpoint in Docker build

### iOS Client

**1e. New `ServerSegmenter` class** (`Packages/WoundAutoSegmentation/.../ServerSegmenter.swift`)
- Conforms to existing `WoundSegmenter` protocol
- `segment(image:, tapPoint:)`:
  1. JPEG-encode the CGImage (quality 0.8)
  2. POST multipart to `Endpoints.segment` with image + tap_point JSON
  3. Decode `SegmentationResponse` → map polygon to `[CGPoint]` in image pixel coords
  4. Return `SegmentationResult(polygonImageSpace:, imageSize:, confidence:, modelIdentifier: "sam2.server.v1")`
- Timeout: 15s, no retry (user can tap again)

**1f. Add `Endpoints.segment`** (`Packages/WoundNetworking/.../Endpoints.swift`)
- `static var segment: URL` → `{versionedURL}/segment`

**1g. Add `segmentImage()` to `WoundOSClient`** (`Packages/WoundNetworking/.../APIClient.swift`)
- New method: `func segmentImage(jpegData: Data, tapPoint: CGPoint, imageWidth: Int, imageHeight: Int) async throws -> SegmentationResponse`
- Multipart POST with image + metadata

**1h. Add response model** (`Packages/WoundNetworking/.../APIModels.swift`)
- `SegmentationResponse: Codable, Sendable` with `polygon`, `confidence`, `model_version`

**1i. Update DI fallback chain** (`WoundOS/App/DependencyContainer.swift`)
- New chain: `ServerSegmenter` (needs network) → `VisionForegroundSegmenter` (offline fallback) → `nil` (manual only)
- `ServerSegmenter` takes the `WoundOSClient` instance from the container

---

## Phase 2: Guided Capture UX

### 2a. Wound Framing Guide Overlay (`CaptureViewController.swift`)
- Add a **translucent wound target reticle** in the center of the AR view:
  - Rounded rectangle outline (dashed, white 40% opacity)
  - Center crosshair dot
  - Label: "Center wound in frame"
- This gives nurses a visual target — like scanning a QR code
- Reticle fades out when capture button is pressed

### 2b. Enhanced Distance Indicator
- Replace static "Hold 15-30 cm from wound" hint with a **live distance bar**:
  - Visual bar that fills green when distance is in 15-30cm range
  - "Too close" / "Too far" / "Perfect" labels
  - Uses existing `CaptureQualityMonitor.lastDistance`
- Distance text shows live cm reading (already partially implemented in guidanceText)

### 2c. Step-by-Step Capture Instructions
- First-time overlay (shows once, then stored in UserDefaults):
  1. "Point camera at wound" (with arrow animation)
  2. "Hold steady at 15-30 cm" (with distance visual)
  3. "Tap capture when ready" (with button highlight)
- Dismissable, never shown again after first successful capture

### 2d. Post-Capture Freeze + Confirm
- After capture, show frozen frame with "Use This Photo" / "Retake" buttons
- Prevents accidental captures; gives nurse confidence in image quality
- Only proceed to boundary drawing on "Use This Photo"

---

## Phase 3: Improved Boundary Drawing UX

### 3a. Auto-Seg Loading State
- When "Auto" mode taps and server segmentation is running:
  - Pulsing ring animation around tap point
  - "Detecting wound boundary..." label
  - 15s timeout with graceful fallback message

### 3b. Boundary Refinement Tools
- After auto-seg returns polygon:
  - **Drag vertices** to refine (already works in polygon mode)
  - **"Accept"** button (green, prominent) to proceed immediately
  - **"Refine"** toggle to switch to manual editing mode
  - Clear visual: green polygon on wound, vertex handles visible

### 3c. Remove Mode Toggle Confusion
- Currently: segmented control with "Auto / Polygon / Freeform" — confusing for nurses
- New flow:
  - Default: "Auto Detect" (tap wound center → server segments)
  - If auto fails or nurse prefers manual: "Draw Manually" button appears
  - Manual mode: just freeform tracing (simpler than polygon+freeform choice)

---

## Phase 4: Clinical Wound Assessment Form

### 4a. Wound Assessment Screen (new screen, between boundary and measurement results)
- Appears after boundary is confirmed, before measurements compute
- Form fields (matches PUSH Score 3.0 + standard wound documentation):

  **Required:**
  - Wound Location (body diagram picker or dropdown: sacrum, heel, leg, etc.)
  - Wound Type (pressure injury, diabetic ulcer, venous ulcer, surgical, other)
  - Exudate Amount (none, light, moderate, heavy) — currently hardcoded to `.none`
  - Tissue Type (epithelial, granulation, slough, necrotic) — currently hardcoded to `.granulation`

  **Optional:**
  - Pain Level (0-10 NRS scale)
  - Odor (none, mild, moderate, strong)
  - Periwound Condition (intact, macerated, erythematous, indurated)
  - Clinical Notes (free text, max 500 chars)

- "Compute Measurements" button at bottom

### 4b. Patient Selection (replace hardcoded IDs)
- Simple patient picker at the top of the assessment form
- For V4: text field for patient ID + name
- Future: integrate with facility patient list from backend

### 4c. Wire Assessment Data Through Pipeline
- Pass exudate/tissue selections to `computeMeasurements()` (currently hardcoded defaults)
- Store wound location, type, pain, odor, periwound in `WoundScan` model
- Include in upload metadata to backend

---

## Phase 5: Enhanced Results & Documentation

### 5a. Measurement Confidence Indicator
- Show mesh hit rate + depth confidence as a quality badge:
  - "High Confidence" (green) — mesh hit rate >80%, depth confidence >1.5
  - "Moderate" (yellow) — mesh hit rate 40-80%
  - "Low" (red) — mesh hit rate <40% (recommend retake)

### 5b. Export / Share Report
- "Share Report" button on measurement results
- Generates a clinical PDF or shareable summary:
  - Patient ID, date, wound location/type
  - Wound photo with boundary overlay
  - All measurements (area, L×W, depth, volume, perimeter)
  - PUSH Score breakdown
  - Assessment notes

---

## Implementation Order

| Step | What | Files Changed | Priority |
|------|------|---------------|----------|
| 1a-1d | Backend SAM 2 endpoint | backend/app/ (4 files) | P0 |
| 1e-1i | iOS ServerSegmenter + networking | 5 iOS files | P0 |
| 3c | Simplify mode toggle (Auto Detect / Draw Manually) | BoundaryDrawingVC | P0 |
| 3a | Auto-seg loading animation | BoundaryDrawingVC | P0 |
| 2a | Wound framing guide overlay | CaptureVC | P1 |
| 2b | Live distance indicator bar | CaptureVC | P1 |
| 4a | Wound assessment form | New screen + coordinator | P1 |
| 4b | Patient ID input | Assessment form | P1 |
| 4c | Wire assessment data | ViewModel + WoundScan model | P1 |
| 2d | Post-capture confirm screen | CaptureVC/Coordinator | P2 |
| 2c | First-time tutorial overlay | CaptureVC | P2 |
| 3b | Boundary refinement (accept/refine) | BoundaryDrawingVC | P2 |
| 5a | Measurement confidence badge | MeasurementResultVC | P2 |
| 5b | Export/share report | MeasurementResultVC | P3 |

---

## What We're NOT Changing
- AR capture pipeline (ARSessionManager, CaptureQualityMonitor) — works well
- Measurement engine (MeshMeasurementEngine) — LiDAR-based, our moat
- BoundaryProjector (2D→3D projection) — proven accurate
- Upload pipeline (UploadManager, WoundOSClient) — already fixed in V4
- Local storage (LocalScanStorage) — keeps working offline
- MVVM-C architecture — maintaining existing patterns
