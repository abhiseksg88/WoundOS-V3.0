"""
API routes — all 6 endpoints the iOS app calls.

POST   /v1/auth/token              → Exchange Firebase token for API bearer
POST   /v1/scans/upload            → Multipart upload (RGB, depth, mesh, metadata)
GET    /v1/scans/{scanId}          → Fetch scan with all fields
GET    /v1/scans/{scanId}/status   → Poll processing status
GET    /v1/patients/{patientId}/scans → List patient scans
PATCH  /v1/scans/{scanId}/review   → Submit clinician review
"""

import json
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.schemas import (
    APIResponse,
    GCSPaths,
    ReviewRequest,
    ScanListResponse,
    ScanResponse,
    ScanStatusResponse,
    ScanUploadMetadata,
    SegmentationResponse,
    TokenRequest,
    TokenResponse,
    UploadResponse,
)
from app.core.auth import create_access_token, get_current_user, verify_firebase_token
from app.core.database import get_db
from app.models.patient import Patient
from app.models.scan import Scan, ScanStatus
from app.services.pubsub import pubsub_service
from app.services.sam2_service import segment_wound
from app.services.storage import storage_service
from app.workers.sam2_processor import process_scan

logger = logging.getLogger(__name__)

router = APIRouter()


# ---------------------------------------------------------------------------
# 0. POST /v1/segment — Real-time wound segmentation
# ---------------------------------------------------------------------------


@router.post("/segment", response_model=SegmentationResponse)
async def segment_image(
    image: UploadFile = File(...),
    tap_point: str = Form(...),
    image_width: int = Form(...),
    image_height: int = Form(...),
    user: dict = Depends(get_current_user),
):
    """Segment a wound from an image using a tap-point prompt.

    Returns a polygon boundary suitable for display on the iOS canvas.
    Uses SAM 2 when available, falls back to GrabCut-based segmentation.
    """
    image_bytes = await image.read()

    import json
    tap = json.loads(tap_point)
    if not isinstance(tap, list) or len(tap) < 2:
        raise HTTPException(status_code=400, detail="tap_point must be [x, y]")

    try:
        result = await segment_wound(
            image_bytes=image_bytes,
            tap_point=tap,
            image_width=image_width,
            image_height=image_height,
        )
    except Exception as e:
        logger.error(f"Segmentation failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Segmentation failed: {str(e)}")

    if not result.get("polygon") or len(result["polygon"]) < 3:
        raise HTTPException(status_code=422, detail="No wound boundary detected")

    return SegmentationResponse(
        polygon=result["polygon"],
        confidence=result["confidence"],
        model_version=result["model_version"],
    )


# ---------------------------------------------------------------------------
# 1. POST /v1/auth/token
# ---------------------------------------------------------------------------


@router.post("/auth/token", response_model=TokenResponse)
async def exchange_token(request: TokenRequest):
    """Exchange a Firebase Auth ID token for an API bearer token."""
    firebase_user = await verify_firebase_token(request.firebase_token)

    token, expires_in = create_access_token(
        user_id=firebase_user["uid"],
        nurse_id=firebase_user.get("uid", ""),
        facility_id="",  # Populated from user profile in production
    )

    return TokenResponse(token=token, expires_in=expires_in)


# ---------------------------------------------------------------------------
# 2. POST /v1/scans/upload
# ---------------------------------------------------------------------------


@router.post("/scans/upload", response_model=UploadResponse)
async def upload_scan(
    background_tasks: BackgroundTasks,
    rgb_image: UploadFile = File(...),
    depth_map: UploadFile = File(...),
    mesh: UploadFile = File(...),
    metadata: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """Receive a multipart scan upload from the iOS app.

    Parts:
      - rgb_image: JPEG image
      - depth_map: Float16 binary depth data
      - mesh: Binary mesh (vertices + faces)
      - metadata: JSON metadata blob
    """
    # Parse metadata
    metadata_bytes = await metadata.read()
    try:
        meta = ScanUploadMetadata(**json.loads(metadata_bytes))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid metadata: {e}")

    scan_id = meta.scan_id

    # Read binary data
    rgb_data = await rgb_image.read()
    depth_data = await depth_map.read()
    mesh_data = await mesh.read()

    # Upload to GCS (or local filesystem in dev)
    gcs_paths = GCSPaths(
        rgb_image=await storage_service.upload_file(scan_id, "rgb.jpg", rgb_data, "image/jpeg"),
        depth_map=await storage_service.upload_file(scan_id, "depth.bin", depth_data),
        mesh=await storage_service.upload_file(scan_id, "mesh.bin", mesh_data),
        metadata=await storage_service.upload_file(scan_id, "metadata.json", metadata_bytes, "application/json"),
    )

    # Ensure patient exists
    patient = await db.get(Patient, meta.patient_id)
    if patient is None:
        patient = Patient(id=meta.patient_id, facility_id=meta.facility_id)
        db.add(patient)

    # Create scan record
    scan = Scan(
        id=uuid.UUID(scan_id),
        patient_id=meta.patient_id,
        nurse_id=meta.nurse_id,
        facility_id=meta.facility_id,
        captured_at=meta.captured_at,
        upload_status=ScanStatus.PENDING,
        # GCS paths
        rgb_image_path=gcs_paths.rgb_image,
        depth_map_path=gcs_paths.depth_map,
        mesh_path=gcs_paths.mesh,
        metadata_path=gcs_paths.metadata,
        # Camera metadata
        image_width=meta.image_width,
        image_height=meta.image_height,
        depth_width=meta.depth_width,
        depth_height=meta.depth_height,
        camera_intrinsics=meta.camera_intrinsics,
        camera_transform=meta.camera_transform,
        device_model=meta.device_model,
        lidar_available=meta.lidar_available,
        # Boundary
        boundary_type=meta.boundary_type,
        boundary_source=meta.boundary_source,
        boundary_points_2d=meta.boundary_points_2d,
        tap_point=meta.tap_point,
        # On-device measurements
        area_cm2=meta.primary_measurement.area_cm2,
        max_depth_mm=meta.primary_measurement.max_depth_mm,
        mean_depth_mm=meta.primary_measurement.mean_depth_mm,
        volume_ml=meta.primary_measurement.volume_ml,
        length_mm=meta.primary_measurement.length_mm,
        width_mm=meta.primary_measurement.width_mm,
        perimeter_mm=meta.primary_measurement.perimeter_mm,
        processing_time_ms=meta.primary_measurement.processing_time_ms,
        # PUSH score
        push_total_score=meta.push_score.total_score,
        push_length_width_cm2=meta.push_score.length_times_width_cm2,
        exudate_amount=meta.push_score.exudate_amount,
        tissue_type=meta.push_score.tissue_type,
        # Quality score
        tracking_stable_seconds=meta.quality_score.tracking_stable_seconds if meta.quality_score else None,
        capture_distance_m=meta.quality_score.capture_distance_m if meta.quality_score else None,
        mesh_vertex_count=meta.quality_score.mesh_vertex_count if meta.quality_score else None,
        mean_depth_confidence=meta.quality_score.mean_depth_confidence if meta.quality_score else None,
        mesh_hit_rate=meta.quality_score.mesh_hit_rate if meta.quality_score else None,
        angular_velocity=meta.quality_score.angular_velocity_rad_per_sec if meta.quality_score else None,
    )
    db.add(scan)
    await db.flush()

    # Trigger async processing
    published = await pubsub_service.publish_scan_ready(
        scan_id=scan_id,
        gcs_paths=gcs_paths.model_dump(),
    )

    if not published:
        # Dev fallback: process in background task
        background_tasks.add_task(process_scan, scan_id)

    # Always also add a background task in dev (Pub/Sub won't trigger worker locally)
    from app.core.config import get_settings
    if get_settings().ENVIRONMENT.value == "development":
        background_tasks.add_task(process_scan, scan_id)

    logger.info(f"Scan {scan_id} uploaded successfully")

    return UploadResponse(
        scan_id=scan_id,
        upload_status="pending",
        gcs_paths=gcs_paths,
    )


# ---------------------------------------------------------------------------
# 3. GET /v1/scans/{scanId}
# ---------------------------------------------------------------------------


@router.get("/scans/{scan_id}", response_model=ScanResponse)
async def get_scan(
    scan_id: str,
    db: AsyncSession = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """Fetch a single scan with all fields (including backend-computed data)."""
    scan = await db.get(Scan, uuid.UUID(scan_id))
    if scan is None:
        raise HTTPException(status_code=404, detail="Scan not found")

    return _scan_to_response(scan)


# ---------------------------------------------------------------------------
# 4. GET /v1/scans/{scanId}/status
# ---------------------------------------------------------------------------


@router.get("/scans/{scan_id}/status", response_model=ScanStatusResponse)
async def get_scan_status(
    scan_id: str,
    db: AsyncSession = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """Poll the processing status of a scan.

    The iOS app polls this every 5 seconds after upload to check
    if SAM 2 processing is complete.
    """
    scan = await db.get(Scan, uuid.UUID(scan_id))
    if scan is None:
        raise HTTPException(status_code=404, detail="Scan not found")

    return ScanStatusResponse(
        scan_id=str(scan.id),
        processing_status=scan.upload_status.value,
        shadow_measurement=scan.shadow_measurement,
        agreement_metrics=scan.agreement_metrics,
        clinical_summary=scan.clinical_summary,
    )


# ---------------------------------------------------------------------------
# 5. GET /v1/patients/{patientId}/scans
# ---------------------------------------------------------------------------


@router.get("/patients/{patient_id}/scans", response_model=ScanListResponse)
async def get_patient_scans(
    patient_id: str,
    db: AsyncSession = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """List all scans for a patient, newest first."""
    result = await db.execute(
        select(Scan)
        .where(Scan.patient_id == patient_id)
        .order_by(Scan.captured_at.desc())
    )
    scans = result.scalars().all()

    return ScanListResponse(
        scans=[_scan_to_response(s) for s in scans],
        total=len(scans),
    )


# ---------------------------------------------------------------------------
# 6. PATCH /v1/scans/{scanId}/review
# ---------------------------------------------------------------------------


@router.patch("/scans/{scan_id}/review")
async def review_scan(
    scan_id: str,
    review: ReviewRequest,
    db: AsyncSession = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """Submit a clinician review for a flagged scan."""
    scan = await db.get(Scan, uuid.UUID(scan_id))
    if scan is None:
        raise HTTPException(status_code=404, detail="Scan not found")

    scan.review_status = review.review_status
    scan.reviewer_id = review.reviewer_id
    scan.review_notes = review.notes
    scan.reviewed_at = datetime.now(timezone.utc)
    scan.updated_at = datetime.now(timezone.utc)

    await db.flush()

    return APIResponse(
        status="ok",
        data={"scan_id": str(scan.id), "review_status": scan.review_status},
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _scan_to_response(scan: Scan) -> ScanResponse:
    """Convert a Scan ORM model to the API response schema."""
    return ScanResponse(
        id=str(scan.id),
        patient_id=scan.patient_id,
        nurse_id=scan.nurse_id,
        facility_id=scan.facility_id,
        captured_at=scan.captured_at,
        upload_status=scan.upload_status.value,
        area_cm2=scan.area_cm2,
        max_depth_mm=scan.max_depth_mm,
        mean_depth_mm=scan.mean_depth_mm,
        volume_ml=scan.volume_ml,
        length_mm=scan.length_mm,
        width_mm=scan.width_mm,
        perimeter_mm=scan.perimeter_mm,
        push_total_score=scan.push_total_score,
        exudate_amount=scan.exudate_amount,
        tissue_type=scan.tissue_type,
        agreement_metrics=scan.agreement_metrics,
        clinical_summary=scan.clinical_summary,
        fwa_signals=scan.fwa_signals,
        review_status=scan.review_status,
        rgb_image_path=scan.rgb_image_path,
        created_at=scan.created_at,
        updated_at=scan.updated_at,
    )
