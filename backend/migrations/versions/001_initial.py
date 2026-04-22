"""Initial schema — patients + scans tables.

Revision ID: 001
Revises: None
Create Date: 2026-04-20
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Patients table
    op.create_table(
        "patients",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("facility_id", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_patients_facility_id", "patients", ["facility_id"])

    # Scans table
    op.create_table(
        "scans",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("patient_id", sa.String(), nullable=False),
        sa.Column("nurse_id", sa.String(), nullable=False),
        sa.Column("facility_id", sa.String(), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "upload_status",
            sa.Enum("PENDING", "PROCESSING", "COMPLETED", "FAILED", name="scanstatus"),
            nullable=False,
        ),
        # GCS paths
        sa.Column("rgb_image_path", sa.Text(), nullable=True),
        sa.Column("depth_map_path", sa.Text(), nullable=True),
        sa.Column("mesh_path", sa.Text(), nullable=True),
        sa.Column("metadata_path", sa.Text(), nullable=True),
        # Camera metadata
        sa.Column("image_width", sa.Integer(), nullable=True),
        sa.Column("image_height", sa.Integer(), nullable=True),
        sa.Column("depth_width", sa.Integer(), nullable=True),
        sa.Column("depth_height", sa.Integer(), nullable=True),
        sa.Column("camera_intrinsics", postgresql.ARRAY(sa.Float()), nullable=True),
        sa.Column("camera_transform", postgresql.ARRAY(sa.Float()), nullable=True),
        sa.Column("device_model", sa.String(50), nullable=True),
        sa.Column("lidar_available", sa.Boolean(), nullable=True, default=True),
        # Boundary
        sa.Column("boundary_type", sa.String(20), nullable=True),
        sa.Column("boundary_source", sa.String(20), nullable=True),
        sa.Column("boundary_points_2d", postgresql.JSONB(), nullable=True),
        sa.Column("tap_point", postgresql.ARRAY(sa.Float()), nullable=True),
        # On-device measurements
        sa.Column("area_cm2", sa.Float(), nullable=True),
        sa.Column("max_depth_mm", sa.Float(), nullable=True),
        sa.Column("mean_depth_mm", sa.Float(), nullable=True),
        sa.Column("volume_ml", sa.Float(), nullable=True),
        sa.Column("length_mm", sa.Float(), nullable=True),
        sa.Column("width_mm", sa.Float(), nullable=True),
        sa.Column("perimeter_mm", sa.Float(), nullable=True),
        sa.Column("processing_time_ms", sa.Integer(), nullable=True),
        # PUSH score
        sa.Column("push_total_score", sa.Integer(), nullable=True),
        sa.Column("push_length_width_cm2", sa.Float(), nullable=True),
        sa.Column("exudate_amount", sa.String(20), nullable=True),
        sa.Column("tissue_type", sa.String(20), nullable=True),
        # Quality
        sa.Column("tracking_stable_seconds", sa.Float(), nullable=True),
        sa.Column("capture_distance_m", sa.Float(), nullable=True),
        sa.Column("mesh_vertex_count", sa.Integer(), nullable=True),
        sa.Column("mean_depth_confidence", sa.Float(), nullable=True),
        sa.Column("mesh_hit_rate", sa.Float(), nullable=True),
        sa.Column("angular_velocity", sa.Float(), nullable=True),
        # Backend-computed
        sa.Column("shadow_boundary", postgresql.JSONB(), nullable=True),
        sa.Column("shadow_measurement", postgresql.JSONB(), nullable=True),
        sa.Column("agreement_metrics", postgresql.JSONB(), nullable=True),
        sa.Column("clinical_summary", postgresql.JSONB(), nullable=True),
        sa.Column("fwa_signals", postgresql.JSONB(), nullable=True),
        # Review
        sa.Column("review_status", sa.String(20), nullable=True),
        sa.Column("reviewer_id", sa.String(), nullable=True),
        sa.Column("review_notes", sa.Text(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        # Timestamps
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        # Constraints
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"]),
    )
    op.create_index("ix_scans_patient_id", "scans", ["patient_id"])
    op.create_index("ix_scans_nurse_id", "scans", ["nurse_id"])
    op.create_index("ix_scans_facility_id", "scans", ["facility_id"])


def downgrade() -> None:
    op.drop_table("scans")
    op.drop_table("patients")
    op.execute("DROP TYPE IF EXISTS scanstatus")
