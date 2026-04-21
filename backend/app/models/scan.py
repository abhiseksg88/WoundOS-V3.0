"""
Scan database model — mirrors the iOS WoundScan aggregate.

Stores on-device measurements immediately at upload time.
Backend-computed fields (shadow_*, agreement_*, clinical_*, fwa_*)
are populated asynchronously by the SAM 2 worker.
"""

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class ScanStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class Scan(Base):
    __tablename__ = "scans"

    # --- Identity ---
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    patient_id: Mapped[str] = mapped_column(
        String, ForeignKey("patients.id"), nullable=False, index=True
    )
    nurse_id: Mapped[str] = mapped_column(String, nullable=False, index=True)
    facility_id: Mapped[str] = mapped_column(String, nullable=False, index=True)
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    # --- Processing status ---
    upload_status: Mapped[ScanStatus] = mapped_column(
        Enum(ScanStatus), default=ScanStatus.PENDING, nullable=False
    )

    # --- GCS paths to binary data ---
    rgb_image_path: Mapped[str | None] = mapped_column(Text)
    depth_map_path: Mapped[str | None] = mapped_column(Text)
    mesh_path: Mapped[str | None] = mapped_column(Text)
    metadata_path: Mapped[str | None] = mapped_column(Text)

    # --- Camera & capture metadata ---
    image_width: Mapped[int | None] = mapped_column(Integer)
    image_height: Mapped[int | None] = mapped_column(Integer)
    depth_width: Mapped[int | None] = mapped_column(Integer)
    depth_height: Mapped[int | None] = mapped_column(Integer)
    camera_intrinsics: Mapped[list[float] | None] = mapped_column(ARRAY(Float))
    camera_transform: Mapped[list[float] | None] = mapped_column(ARRAY(Float))
    device_model: Mapped[str | None] = mapped_column(String(50))
    lidar_available: Mapped[bool] = mapped_column(Boolean, default=True)

    # --- Nurse boundary ---
    boundary_type: Mapped[str | None] = mapped_column(String(20))  # polygon / freeform
    boundary_source: Mapped[str | None] = mapped_column(String(20))  # nurse_drawn / auto_vision
    boundary_points_2d: Mapped[dict | None] = mapped_column(JSONB)  # [[x,y], ...]
    tap_point: Mapped[list[float] | None] = mapped_column(ARRAY(Float))

    # --- On-device primary measurements ---
    area_cm2: Mapped[float | None] = mapped_column(Float)
    max_depth_mm: Mapped[float | None] = mapped_column(Float)
    mean_depth_mm: Mapped[float | None] = mapped_column(Float)
    volume_ml: Mapped[float | None] = mapped_column(Float)
    length_mm: Mapped[float | None] = mapped_column(Float)
    width_mm: Mapped[float | None] = mapped_column(Float)
    perimeter_mm: Mapped[float | None] = mapped_column(Float)
    processing_time_ms: Mapped[int | None] = mapped_column(Integer)

    # --- PUSH Score 3.0 ---
    push_total_score: Mapped[int | None] = mapped_column(Integer)
    push_length_width_cm2: Mapped[float | None] = mapped_column(Float)
    exudate_amount: Mapped[str | None] = mapped_column(String(20))
    tissue_type: Mapped[str | None] = mapped_column(String(20))

    # --- Capture quality ---
    tracking_stable_seconds: Mapped[float | None] = mapped_column(Float)
    capture_distance_m: Mapped[float | None] = mapped_column(Float)
    mesh_vertex_count: Mapped[int | None] = mapped_column(Integer)
    mean_depth_confidence: Mapped[float | None] = mapped_column(Float)
    mesh_hit_rate: Mapped[float | None] = mapped_column(Float)
    angular_velocity: Mapped[float | None] = mapped_column(Float)

    # --- Backend-computed: SAM 2 shadow boundary + measurement ---
    shadow_boundary: Mapped[dict | None] = mapped_column(JSONB)
    shadow_measurement: Mapped[dict | None] = mapped_column(JSONB)

    # --- Backend-computed: Agreement metrics ---
    agreement_metrics: Mapped[dict | None] = mapped_column(JSONB)

    # --- Backend-computed: Clinical summary (Claude Haiku) ---
    clinical_summary: Mapped[dict | None] = mapped_column(JSONB)

    # --- Backend-computed: FWA signals ---
    fwa_signals: Mapped[dict | None] = mapped_column(JSONB)

    # --- Review ---
    review_status: Mapped[str | None] = mapped_column(String(20))
    reviewer_id: Mapped[str | None] = mapped_column(String)
    review_notes: Mapped[str | None] = mapped_column(Text)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # --- Timestamps ---
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
