# WoundOS iOS Client — Backend Integration Brief

Paste this entire document into Claude inside Xcode. It contains everything needed to wire the iOS app to the deployed staging backend: base URL, auth flow, all six endpoints with exact JSON contracts, the multipart upload format, status polling, and Swift integration patterns.

---

## 1. Goal

Implement (or replace the stub of) the iOS networking layer that talks to the WoundOS FastAPI backend running on Cloud Run. Deliverables:

1. A `WoundOSClient` class (async/await, Swift 5.9+, iOS 17+) that exposes one method per backend endpoint.
2. Codable request/response models that match the JSON wire format exactly (snake_case).
3. Bearer-token storage + refresh on 401.
4. Multipart upload for scans (four parts: `rgb_image`, `depth_map`, `mesh`, `metadata`).
5. A polling helper that watches `/v1/scans/{id}/status` until `processing_status == "completed"` or `"failed"`.
6. Unit tests that hit a mock URLProtocol — no real network.

---

## 2. Environment

| Key | Value |
| --- | --- |
| Base URL (staging) | `https://woundos-api-333499614175.us-central1.run.app` |
| API version prefix | `/v1` |
| Health check | `GET /health` → `{"status":"ok","service":"woundos-api"}` |
| Auth scheme | `Authorization: Bearer <jwt>` on every `/v1/*` route |
| Token lifetime | 3600 seconds (HS256-signed JWT issued by the backend) |
| JSON encoding | snake_case on the wire (both directions) |
| Date format | RFC 3339 / ISO 8601, UTC with `Z` suffix (e.g. `2026-04-20T15:04:05Z`) |

Set these in an `APIConfig` struct with a `baseURL: URL` and `version: String = "v1"`.

Recommended `JSONDecoder`:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601
```

Recommended `JSONEncoder`:

```swift
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
encoder.dateEncodingStrategy = .iso8601
```

---

## 3. Auth flow

The iOS app signs in with Firebase (already wired in the existing code), gets a Firebase ID token, then exchanges it for a short-lived API bearer token:

```
iOS (Firebase Auth) ──ID token──▶ POST /v1/auth/token ──JWT──▶ iOS
         │                                                       │
         └──── Bearer <JWT> on every subsequent request ─────────┘
```

**Dev mode shortcut:** the staging environment currently runs with `FIREBASE_PROJECT_ID` set but no production users — verifying a real Firebase token requires that a matching user exists in the Firebase project. Until the user registration flow is wired, pass any non-empty string as `firebase_token`; the backend is in staging mode and will still issue a JWT (the handler short-circuits when `ENVIRONMENT=development` — check before relying on this in staging).

### `POST /v1/auth/token`

Request body:
```json
{ "firebase_token": "eyJhbGciOiJS..." }
```

Response `200 OK`:
```json
{
  "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
  "expires_in": 3600
}
```

Errors: `401 Unauthorized` if Firebase verification fails.

Store the JWT in Keychain. Refresh when you get a 401 from any other endpoint (treat 401 as "re-auth and retry once").

---

## 4. Endpoint catalog

All six routes require `Authorization: Bearer <jwt>` except `POST /v1/auth/token`.

### 4.1 `POST /v1/scans/upload` — multipart scan upload

Content-Type: `multipart/form-data`

Four parts, all required:

| Part name | Content-Type | Body |
| --- | --- | --- |
| `rgb_image` | `image/jpeg` | JPEG bytes of the captured RGB frame |
| `depth_map` | `application/octet-stream` | Float16 depth buffer (width × height × 2 bytes) |
| `mesh` | `application/octet-stream` | Binary mesh (vertex buffer + index buffer, your existing on-device format) |
| `metadata` | `application/json` | The `ScanUploadMetadata` JSON below |

`metadata` JSON shape (keys are **required** unless marked optional):

```json
{
  "scan_id": "b6e2c8a0-8f7e-4d9e-b1b2-9b8e3a1a2c4d",
  "patient_id": "pt_12345",
  "nurse_id": "nurse_001",
  "facility_id": "fac_001",
  "captured_at": "2026-04-20T15:04:05Z",

  "camera_intrinsics": [fx, fy, cx, cy],
  "camera_transform":  [16 floats, row-major 4x4],
  "image_width": 1920,
  "image_height": 1080,
  "depth_width": 320,
  "depth_height": 240,
  "device_model": "iPhone15,3",
  "lidar_available": true,

  "boundary_points_2d": [[x0, y0], [x1, y1], ...],
  "boundary_type": "polygon",
  "boundary_source": "nurse_drawn",
  "tap_point": [x, y],

  "primary_measurement": {
    "area_cm2": 4.82,
    "max_depth_mm": 6.3,
    "mean_depth_mm": 2.8,
    "volume_ml": 1.4,
    "length_mm": 32.1,
    "width_mm": 18.7,
    "perimeter_mm": 88.4,
    "processing_time_ms": 214
  },
  "push_score": {
    "length_times_width_cm2": 6.0,
    "exudate_amount": "light",
    "tissue_type": "granulation",
    "total_score": 9
  },
  "quality_score": {
    "tracking_stable_seconds": 2.4,
    "capture_distance_m": 0.32,
    "mesh_vertex_count": 18420,
    "mean_depth_confidence": 0.86,
    "mesh_hit_rate": 0.94,
    "angular_velocity_rad_per_sec": 0.12
  }
}
```

Notes:
- `scan_id` **must** be a valid UUID string generated on-device. The backend uses it as the primary key; do not let the server assign it.
- `tap_point` and `quality_score` are optional (nullable).
- `boundary_points_2d` coordinates are in image-space pixels.
- `captured_at` is UTC ISO-8601.

Response `200 OK`:
```json
{
  "scan_id": "b6e2c8a0-8f7e-4d9e-b1b2-9b8e3a1a2c4d",
  "upload_status": "pending",
  "gcs_paths": {
    "rgb_image": "gs://woundos-scans-staging/scans/<id>/rgb.jpg",
    "depth_map": "gs://woundos-scans-staging/scans/<id>/depth.bin",
    "mesh":      "gs://woundos-scans-staging/scans/<id>/mesh.bin",
    "metadata":  "gs://woundos-scans-staging/scans/<id>/metadata.json"
  }
}
```

Errors:
- `400` — metadata JSON failed validation (body contains `{"detail":"Invalid metadata: ..."}`)
- `401` — missing/invalid bearer
- `500` — GCS or DB failure

### 4.2 `GET /v1/scans/{scan_id}` — full scan

Response `200 OK` — shape of `ScanResponse`:

```json
{
  "id": "b6e2c8a0-...",
  "patient_id": "pt_12345",
  "nurse_id": "nurse_001",
  "facility_id": "fac_001",
  "captured_at": "2026-04-20T15:04:05Z",
  "upload_status": "completed",

  "area_cm2": 4.82,
  "max_depth_mm": 6.3,
  "mean_depth_mm": 2.8,
  "volume_ml": 1.4,
  "length_mm": 32.1,
  "width_mm": 18.7,
  "perimeter_mm": 88.4,

  "push_total_score": 9,
  "exudate_amount": "light",
  "tissue_type": "granulation",

  "agreement_metrics": {
    "iou": 0.88,
    "dice_coefficient": 0.93,
    "area_delta_percent": 4.1,
    "depth_delta_mm": 0.3,
    "volume_delta_ml": 0.08,
    "centroid_displacement_mm": 1.1,
    "sam_confidence": 0.96,
    "sam_model_version": "sam2-1.0",
    "is_flagged": false
  },
  "clinical_summary": {
    "narrative_summary": "Stage 3 sacral pressure injury, ~5 cm², granulating.",
    "trajectory": "improving",
    "key_findings": ["granulation tissue", "low exudate"],
    "recommendations": ["continue current dressing regimen"],
    "model_version": "claude-haiku-4-5-20251001"
  },
  "fwa_signals": {
    "nurse_baseline_agreement": 0.91,
    "wound_size_outlier": false,
    "copy_paste_risk": 0.02,
    "longitudinal_consistency": 0.88,
    "overall_risk_score": 0.07,
    "triggered_flags": []
  },

  "review_status": null,
  "rgb_image_path": "gs://woundos-scans-staging/scans/<id>/rgb.jpg",
  "created_at": "2026-04-20T15:04:06Z",
  "updated_at": "2026-04-20T15:04:38Z"
}
```

Any of `agreement_metrics`, `clinical_summary`, `fwa_signals`, or `review_status` may be `null` before processing completes — make the Swift models `Optional`.

### 4.3 `GET /v1/scans/{scan_id}/status` — lightweight polling

Response `200 OK`:
```json
{
  "scan_id": "b6e2c8a0-...",
  "processing_status": "processing",
  "shadow_measurement": null,
  "agreement_metrics": null,
  "clinical_summary": null
}
```

`processing_status` values: `"pending"`, `"processing"`, `"completed"`, `"failed"`.

Poll every **5 seconds** after upload; stop when status is `completed` or `failed`; time out at **90 seconds** and surface a user-visible error. On `completed`, call `GET /v1/scans/{id}` for the full payload.

### 4.4 `GET /v1/patients/{patient_id}/scans` — list scans for a patient

Response `200 OK`:
```json
{
  "scans": [ /* array of ScanResponse, newest first */ ],
  "total": 12
}
```

### 4.5 `PATCH /v1/scans/{scan_id}/review` — submit clinician review

Request body:
```json
{
  "review_status": "approved",   // or "rejected" | "needs_correction"
  "reviewer_id": "clinician_42",
  "notes": "Agree with SAM boundary."
}
```

Response `200 OK`:
```json
{
  "status": "ok",
  "data": { "scan_id": "...", "review_status": "approved" },
  "error": null
}
```

### 4.6 `POST /v1/auth/token` — already documented in §3.

---

## 5. Swift client skeleton

Produce code along these lines (flesh out error handling, retries, and tests):

```swift
public struct APIConfig {
    public let baseURL: URL
    public let version: String = "v1"
    public static let staging = APIConfig(
        baseURL: URL(string: "https://woundos-api-333499614175.us-central1.run.app")!
    )
}

public enum APIError: Error, Equatable {
    case unauthorized
    case notFound
    case badRequest(String)
    case server(Int, String)
    case decoding(String)
    case transport(URLError)
}

public actor WoundOSClient {
    private let config: APIConfig
    private let session: URLSession
    private let tokenStore: TokenStore          // your Keychain wrapper
    private let firebase: FirebaseAuthProviding // existing

    public init(config: APIConfig = .staging,
                session: URLSession = .shared,
                tokenStore: TokenStore,
                firebase: FirebaseAuthProviding) {
        self.config = config
        self.session = session
        self.tokenStore = tokenStore
        self.firebase = firebase
    }

    // MARK: Auth
    public func ensureValidToken() async throws -> String { /* ... */ }
    public func exchangeFirebaseToken(_ idToken: String) async throws -> TokenResponse { /* ... */ }

    // MARK: Endpoints
    public func uploadScan(
        rgbImage: Data,
        depthMap: Data,
        mesh: Data,
        metadata: ScanUploadMetadata
    ) async throws -> UploadResponse { /* multipart POST */ }

    public func getScan(id: UUID) async throws -> ScanResponse
    public func getScanStatus(id: UUID) async throws -> ScanStatusResponse
    public func listScans(forPatient patientID: String) async throws -> ScanListResponse
    public func submitReview(scanID: UUID, _ review: ReviewRequest) async throws

    // MARK: Polling helper
    public func pollUntilComplete(
        scanID: UUID,
        every interval: Duration = .seconds(5),
        timeout: Duration = .seconds(90)
    ) async throws -> ScanResponse { /* ... */ }
}
```

### Multipart body construction

Use a fresh `UUID().uuidString` as the boundary:

```
--<boundary>\r\n
Content-Disposition: form-data; name="rgb_image"; filename="rgb.jpg"\r\n
Content-Type: image/jpeg\r\n\r\n
<JPEG bytes>\r\n
--<boundary>\r\n
Content-Disposition: form-data; name="depth_map"; filename="depth.bin"\r\n
Content-Type: application/octet-stream\r\n\r\n
<depth bytes>\r\n
--<boundary>\r\n
Content-Disposition: form-data; name="mesh"; filename="mesh.bin"\r\n
Content-Type: application/octet-stream\r\n\r\n
<mesh bytes>\r\n
--<boundary>\r\n
Content-Disposition: form-data; name="metadata"; filename="metadata.json"\r\n
Content-Type: application/json\r\n\r\n
<metadata JSON bytes>\r\n
--<boundary>--\r\n
```

Set `Content-Type: multipart/form-data; boundary=<boundary>` on the `URLRequest`. Use `URLSession.upload(for:from:)` with the assembled `Data` to avoid chunked streaming surprises; for very large uploads (>50MB) switch to a temp file + `upload(for:fromFile:)`.

### Retry policy

- 401 → call `exchangeFirebaseToken` with a fresh Firebase ID token, retry once.
- 5xx and `URLError.timedOut` / `.networkConnectionLost` → exponential backoff (1s, 2s, 4s), max 3 attempts. Skip retry for `POST /upload` (uploads are idempotent by `scan_id`, but the user should see the error and tap retry manually).
- 4xx other than 401 → surface to UI, no retry.

---

## 6. Codable models to generate

Mirror these exactly. All JSON keys on the wire are snake_case; with `.convertFromSnakeCase` on the decoder the Swift properties can stay camelCase.

```swift
struct TokenRequest: Codable { let firebaseToken: String }
struct TokenResponse: Codable { let token: String; let expiresIn: Int }

struct MeasurementData: Codable {
    var areaCm2: Double = 0
    var maxDepthMm: Double = 0
    var meanDepthMm: Double = 0
    var volumeMl: Double = 0
    var lengthMm: Double = 0
    var widthMm: Double = 0
    var perimeterMm: Double = 0
    var processingTimeMs: Int = 0
}

struct PushScoreData: Codable {
    var lengthTimesWidthCm2: Double = 0
    var exudateAmount: String = "none"
    var tissueType: String = "granulation"
    var totalScore: Int = 0
}

struct QualityScoreData: Codable {
    var trackingStableSeconds: Double = 0
    var captureDistanceM: Double = 0
    var meshVertexCount: Int = 0
    var meanDepthConfidence: Double = 0
    var meshHitRate: Double = 0
    var angularVelocityRadPerSec: Double = 0
}

struct ScanUploadMetadata: Codable {
    let scanId: String
    let patientId: String
    let nurseId: String
    let facilityId: String
    let capturedAt: Date
    var cameraIntrinsics: [Double]
    var cameraTransform: [Double]
    var imageWidth: Int
    var imageHeight: Int
    var depthWidth: Int
    var depthHeight: Int
    var deviceModel: String
    var lidarAvailable: Bool
    var boundaryPoints2d: [[Double]]
    var boundaryType: String
    var boundarySource: String
    var tapPoint: [Double]?
    var primaryMeasurement: MeasurementData
    var pushScore: PushScoreData
    var qualityScore: QualityScoreData?
}

struct GCSPaths: Codable {
    let rgbImage: String
    let depthMap: String
    let mesh: String
    let metadata: String
}

struct UploadResponse: Codable {
    let scanId: String
    let uploadStatus: String
    let gcsPaths: GCSPaths
}

struct AgreementMetricsResponse: Codable {
    let iou: Double
    let diceCoefficient: Double
    let areaDeltaPercent: Double
    let depthDeltaMm: Double
    let volumeDeltaMl: Double
    let centroidDisplacementMm: Double
    let samConfidence: Double
    let samModelVersion: String
    let isFlagged: Bool
}

struct ClinicalSummaryResponse: Codable {
    let narrativeSummary: String
    let trajectory: String         // "improving" | "stable" | "worsening" | "insufficient_data"
    let keyFindings: [String]
    let recommendations: [String]
    let modelVersion: String
}

struct FWASignalsResponse: Codable {
    let nurseBaselineAgreement: Double
    let woundSizeOutlier: Bool
    let copyPasteRisk: Double
    let longitudinalConsistency: Double
    let overallRiskScore: Double
    let triggeredFlags: [String]
}

struct ScanResponse: Codable {
    let id: String
    let patientId: String
    let nurseId: String
    let facilityId: String
    let capturedAt: Date
    let uploadStatus: String
    let areaCm2: Double?
    let maxDepthMm: Double?
    let meanDepthMm: Double?
    let volumeMl: Double?
    let lengthMm: Double?
    let widthMm: Double?
    let perimeterMm: Double?
    let pushTotalScore: Int?
    let exudateAmount: String?
    let tissueType: String?
    let agreementMetrics: AgreementMetricsResponse?
    let clinicalSummary: ClinicalSummaryResponse?
    let fwaSignals: FWASignalsResponse?
    let reviewStatus: String?
    let rgbImagePath: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ScanStatusResponse: Codable {
    let scanId: String
    let processingStatus: String   // "pending" | "processing" | "completed" | "failed"
    let shadowMeasurement: [String: AnyCodable]?
    let agreementMetrics: [String: AnyCodable]?
    let clinicalSummary: [String: AnyCodable]?
}

struct ScanListResponse: Codable {
    let scans: [ScanResponse]
    let total: Int
}

struct ReviewRequest: Codable {
    let reviewStatus: String       // "approved" | "rejected" | "needs_correction"
    let reviewerId: String
    var notes: String = ""
}
```

(`AnyCodable` is a standard helper; one implementation: https://github.com/Flight-School/AnyCodable)

---

## 7. Tests to write

Use `URLProtocol` stubbing (no live network). At minimum:

1. `uploadScan` builds a multipart body with exactly four parts in order `rgb_image`, `depth_map`, `mesh`, `metadata`, each with the correct `Content-Type`, and a trailing `--<boundary>--` terminator.
2. On `401 Unauthorized` from any endpoint, the client calls `exchangeFirebaseToken` once and retries the original request.
3. `pollUntilComplete` stops on `"completed"`, throws on `"failed"`, and throws a timeout error after 90 s (use a virtual clock or inject the `Duration` parameters as 0.01 s in the test).
4. `ScanResponse` decodes the sample payload in §4.2 with all optional fields populated, and also decodes a variant where `agreement_metrics`, `clinical_summary`, `fwa_signals`, and `review_status` are `null`.
5. Date round-trip: an ISO-8601 `capturedAt` encodes and decodes back to the same `Date` (within 1 ms).

---

## 8. Known backend quirks to defend against

- Health probe is `GET /health` (not `/v1/health`). Don't prefix with the version.
- `/docs` is disabled in staging (`DEBUG=false`). Don't depend on live OpenAPI.
- `clinical_summary` can be `null` for up to ~30 s after upload while the Claude call runs. Defensive decode.
- Anthropic API key is currently a placeholder in staging, so `clinical_summary` will be `null` (or contain an error stub) until the real key is added. Treat as expected, don't surface as a hard error.
- The Pub/Sub worker is currently unauthenticated and may get 5xx or silent failures. A scan stuck in `"pending"` for >90s should be surfaced to the user as "processing unavailable — try again" rather than looping forever.
- `POST /upload` is idempotent by `scan_id` — retrying with the same `scan_id` after a network blip will overwrite GCS blobs but won't duplicate DB rows (the primary-key insert will fail on the second try and the request will return 500; treat as "already uploaded").

---

## 9. What I want back

1. A new Swift package or Xcode group `WoundOSClient/` containing `WoundOSClient.swift`, `APIModels.swift`, `Multipart.swift`, `TokenStore.swift`, and a small `URLSession+Extensions.swift`.
2. Matching `WoundOSClientTests/` with `URLProtocolMock` and the five tests listed in §7.
3. One-line wiring in the existing `ScanUploadCoordinator` (or equivalent) to replace whatever stub is there with real calls: upload → poll → fetch → update SwiftData store.
4. Leave the existing on-device measurement / capture code untouched — this PR is the network layer only.

Start by reading the existing iOS project structure, then propose a short plan (files to add, files to modify) before writing code. Do not invent endpoints or field names — stick to exactly what is documented above.
