"""
Pydantic request/response schemas — mirrors the iOS WoundCore models.

These are the JSON contracts between the iOS app and the backend.
Uses snake_case to match the iOS `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`.
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


class TokenRequest(BaseModel):
    firebase_token: str


class TokenResponse(BaseModel):
    token: str
    expires_in: int


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------


class MeasurementData(BaseModel):
    area_cm2: float = 0
    max_depth_mm: float = 0
    mean_depth_mm: float = 0
    volume_ml: float = 0
    length_mm: float = 0
    width_mm: float = 0
    perimeter_mm: float = 0
    processing_time_ms: int = 0


class PushScoreData(BaseModel):
    length_times_width_cm2: float = 0
    exudate_amount: str = "none"
    tissue_type: str = "granulation"
    total_score: int = 0


class QualityScoreData(BaseModel):
    tracking_stable_seconds: float = 0
    capture_distance_m: float = 0
    mesh_vertex_count: int = 0
    mean_depth_confidence: float = 0
    mesh_hit_rate: float = 0
    angular_velocity_rad_per_sec: float = 0


class ScanUploadMetadata(BaseModel):
    """Metadata JSON sent as part of the multipart upload.

    Matches `SnapshotSerializer.ScanUploadMetadata` in the iOS codebase.
    """
    scan_id: str
    patient_id: str
    nurse_id: str
    facility_id: str
    captured_at: datetime
    camera_intrinsics: list[float] = Field(default_factory=list)
    camera_transform: list[float] = Field(default_factory=list)
    image_width: int = 0
    image_height: int = 0
    depth_width: int = 0
    depth_height: int = 0
    device_model: str = ""
    lidar_available: bool = True
    boundary_points_2d: list[list[float]] = Field(default_factory=list)
    boundary_type: str = "polygon"
    boundary_source: str = "nurse_drawn"
    tap_point: list[float] | None = None
    primary_measurement: MeasurementData = Field(default_factory=MeasurementData)
    push_score: PushScoreData = Field(default_factory=PushScoreData)
    quality_score: QualityScoreData | None = None


class GCSPaths(BaseModel):
    rgb_image: str = ""
    depth_map: str = ""
    mesh: str = ""
    metadata: str = ""


class UploadResponse(BaseModel):
    scan_id: str
    upload_status: str = "pending"
    gcs_paths: GCSPaths = Field(default_factory=GCSPaths)


# ---------------------------------------------------------------------------
# Scan responses
# ---------------------------------------------------------------------------


class AgreementMetricsResponse(BaseModel):
    iou: float = 0
    dice_coefficient: float = 0
    area_delta_percent: float = 0
    depth_delta_mm: float = 0
    volume_delta_ml: float = 0
    centroid_displacement_mm: float = 0
    sam_confidence: float = 0
    sam_model_version: str = ""
    is_flagged: bool = False


class ClinicalSummaryResponse(BaseModel):
    narrative_summary: str = ""
    trajectory: str = "insufficient_data"
    key_findings: list[str] = Field(default_factory=list)
    recommendations: list[str] = Field(default_factory=list)
    model_version: str = ""


class FWASignalsResponse(BaseModel):
    nurse_baseline_agreement: float = 0
    wound_size_outlier: bool = False
    copy_paste_risk: float = 0
    longitudinal_consistency: float = 0
    overall_risk_score: float = 0
    triggered_flags: list[str] = Field(default_factory=list)


class ScanResponse(BaseModel):
    """Full scan response — includes all on-device + backend-computed fields."""
    id: str
    patient_id: str
    nurse_id: str
    facility_id: str
    captured_at: datetime
    upload_status: str

    # On-device measurements
    area_cm2: float | None = None
    max_depth_mm: float | None = None
    mean_depth_mm: float | None = None
    volume_ml: float | None = None
    length_mm: float | None = None
    width_mm: float | None = None
    perimeter_mm: float | None = None

    # PUSH score
    push_total_score: int | None = None
    exudate_amount: str | None = None
    tissue_type: str | None = None

    # Backend-computed
    agreement_metrics: AgreementMetricsResponse | None = None
    clinical_summary: ClinicalSummaryResponse | None = None
    fwa_signals: FWASignalsResponse | None = None

    # Review
    review_status: str | None = None

    # GCS paths
    rgb_image_path: str | None = None

    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ScanStatusResponse(BaseModel):
    scan_id: str
    processing_status: str
    shadow_measurement: dict | None = None
    agreement_metrics: dict | None = None
    clinical_summary: dict | None = None


class ScanListResponse(BaseModel):
    scans: list[ScanResponse]
    total: int


# ---------------------------------------------------------------------------
# Review
# ---------------------------------------------------------------------------


class ReviewRequest(BaseModel):
    review_status: str  # "approved", "rejected", "needs_correction"
    reviewer_id: str
    notes: str = ""


# ---------------------------------------------------------------------------
# Generic wrapper
# ---------------------------------------------------------------------------


class APIResponse(BaseModel):
    status: str = "ok"
    data: dict | list | None = None
    error: str | None = None
