"""
SAM 2 asynchronous scan processor.

Triggered via Pub/Sub (production) or background task (development).
Runs the full post-upload pipeline:
  1. Download RGB image from GCS
  2. Run SAM 2 inference (shadow boundary)
  3. Compute agreement metrics (nurse vs SAM 2)
  4. Detect FWA signals
  5. Generate clinical summary (Claude Haiku)
  6. Update scan record in database
"""

import logging
import math
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session
from app.models.scan import Scan, ScanStatus
from app.services.clinical_summary import generate_clinical_summary
from app.services.storage import storage_service

logger = logging.getLogger(__name__)


async def process_scan(scan_id: str) -> bool:
    """Run the full post-upload processing pipeline for a scan.

    Returns True on success, False on failure.
    """
    logger.info(f"Processing scan {scan_id}...")

    async with async_session() as session:
        try:
            # 1. Load scan from database
            scan = await session.get(Scan, uuid.UUID(scan_id))
            if scan is None:
                logger.error(f"Scan {scan_id} not found")
                return False

            scan.upload_status = ScanStatus.PROCESSING
            await session.commit()

            # 2. Run SAM 2 inference → shadow boundary
            shadow_boundary = await run_sam2_inference(scan)

            # 3. Compute agreement metrics
            agreement = compute_agreement_metrics(
                nurse_boundary=scan.boundary_points_2d,
                shadow_boundary=shadow_boundary,
                nurse_measurements={
                    "area_cm2": scan.area_cm2,
                    "max_depth_mm": scan.max_depth_mm,
                    "volume_ml": scan.volume_ml,
                },
            )

            # 4. Detect FWA signals
            fwa = await detect_fwa_signals(session, scan, agreement)

            # 5. Generate clinical summary
            clinical = await generate_clinical_summary(
                {
                    "area_cm2": scan.area_cm2 or 0,
                    "max_depth_mm": scan.max_depth_mm or 0,
                    "mean_depth_mm": scan.mean_depth_mm or 0,
                    "volume_ml": scan.volume_ml or 0,
                    "length_mm": scan.length_mm or 0,
                    "width_mm": scan.width_mm or 0,
                    "perimeter_mm": scan.perimeter_mm or 0,
                    "push_total_score": scan.push_total_score or 0,
                    "tissue_type": scan.tissue_type or "unknown",
                    "exudate_amount": scan.exudate_amount or "unknown",
                    "device_model": scan.device_model or "unknown",
                    "mesh_hit_rate": scan.mesh_hit_rate or 0,
                    "mean_depth_confidence": scan.mean_depth_confidence or 0,
                }
            )

            # 6. Update scan with all results
            scan.shadow_boundary = shadow_boundary
            scan.shadow_measurement = _compute_shadow_measurements(shadow_boundary)
            scan.agreement_metrics = agreement
            scan.fwa_signals = fwa
            scan.clinical_summary = clinical
            scan.upload_status = ScanStatus.COMPLETED
            scan.updated_at = datetime.now(timezone.utc)

            # Auto-flag for review if agreement is poor
            if agreement and agreement.get("is_flagged", False):
                scan.review_status = "flagged"

            await session.commit()
            logger.info(f"Scan {scan_id} processing completed")
            return True

        except Exception as e:
            logger.error(f"Scan {scan_id} processing failed: {e}", exc_info=True)
            scan.upload_status = ScanStatus.FAILED
            await session.commit()
            return False


# ---------------------------------------------------------------------------
# SAM 2 Inference
# ---------------------------------------------------------------------------


async def run_sam2_inference(scan: Scan) -> dict | None:
    """Run SAM 2 on the uploaded RGB image to produce a shadow boundary.

    TODO: Replace this stub with actual SAM 2 inference.
    Options:
      - Vertex AI custom prediction endpoint
      - Self-hosted SAM 2 via torch + segment_anything_2
      - Hugging Face Inference Endpoints

    For now, returns a simulated boundary based on the nurse's boundary
    with slight perturbation (for development/testing).
    """
    if not scan.boundary_points_2d:
        return None

    nurse_points = scan.boundary_points_2d
    if not isinstance(nurse_points, list) or len(nurse_points) < 3:
        return None

    # Stub: perturb nurse boundary by small random offsets
    # In production, this is replaced by actual SAM 2 model output
    import random
    random.seed(str(scan.id))

    shadow_points = []
    for point in nurse_points:
        if isinstance(point, list) and len(point) >= 2:
            shadow_points.append([
                max(0, min(1, point[0] + random.uniform(-0.02, 0.02))),
                max(0, min(1, point[1] + random.uniform(-0.02, 0.02))),
            ])

    return {
        "points_2d": shadow_points,
        "source": "sam2",
        "model_version": "sam2-stub-v1",
        "confidence": 0.92,
    }


# ---------------------------------------------------------------------------
# Agreement Metrics (Nurse vs. SAM 2)
# ---------------------------------------------------------------------------


def compute_agreement_metrics(
    nurse_boundary: dict | None,
    shadow_boundary: dict | None,
    nurse_measurements: dict | None = None,
) -> dict | None:
    """Compute agreement between nurse-drawn and SAM 2 boundaries.

    Uses IoU on rasterized masks as the primary metric.
    """
    if not nurse_boundary or not shadow_boundary:
        return None

    nurse_pts = nurse_boundary if isinstance(nurse_boundary, list) else nurse_boundary.get("points_2d", [])
    shadow_pts = shadow_boundary.get("points_2d", [])

    if len(nurse_pts) < 3 or len(shadow_pts) < 3:
        return None

    # Compute IoU via rasterized polygon masks
    iou = _compute_polygon_iou(nurse_pts, shadow_pts, grid_size=256)
    dice = 2 * iou / (1 + iou) if iou > 0 else 0

    # Area comparison (from polygon area approximation)
    nurse_area = _polygon_area(nurse_pts)
    shadow_area = _polygon_area(shadow_pts)
    area_delta_pct = (
        abs(nurse_area - shadow_area) / nurse_area * 100 if nurse_area > 0 else 0
    )

    # Centroid displacement
    nurse_cx, nurse_cy = _polygon_centroid(nurse_pts)
    shadow_cx, shadow_cy = _polygon_centroid(shadow_pts)
    centroid_displacement = math.sqrt((nurse_cx - shadow_cx) ** 2 + (nurse_cy - shadow_cy) ** 2)
    # Convert normalized displacement to mm (approximate, using length as reference)
    centroid_mm = centroid_displacement * (nurse_measurements or {}).get("length_mm", 100)

    # Auto-flag thresholds (from iOS AgreementMetrics model)
    is_flagged = (
        iou < 0.7
        or area_delta_pct > 20.0
        or centroid_mm > 20.0
    )

    return {
        "iou": round(iou, 4),
        "dice_coefficient": round(dice, 4),
        "area_delta_percent": round(area_delta_pct, 2),
        "depth_delta_mm": 0,  # Requires 3D mesh analysis
        "volume_delta_ml": 0,
        "centroid_displacement_mm": round(centroid_mm, 2),
        "sam_confidence": shadow_boundary.get("confidence", 0),
        "sam_model_version": shadow_boundary.get("model_version", ""),
        "is_flagged": is_flagged,
    }


def _compute_polygon_iou(poly_a: list, poly_b: list, grid_size: int = 256) -> float:
    """Rasterize two polygons on a grid and compute IoU."""
    mask_a = _rasterize_polygon(poly_a, grid_size)
    mask_b = _rasterize_polygon(poly_b, grid_size)

    intersection = sum(1 for a, b in zip(mask_a, mask_b) if a and b)
    union = sum(1 for a, b in zip(mask_a, mask_b) if a or b)

    return intersection / union if union > 0 else 0


def _rasterize_polygon(polygon: list, grid_size: int) -> list[bool]:
    """Rasterize a polygon (normalized 0-1 coords) onto a boolean grid."""
    mask = [False] * (grid_size * grid_size)
    n = len(polygon)
    if n < 3:
        return mask

    for y in range(grid_size):
        ny = (y + 0.5) / grid_size
        for x in range(grid_size):
            nx = (x + 0.5) / grid_size
            # Ray casting point-in-polygon test
            inside = False
            j = n - 1
            for i in range(n):
                pi = polygon[i]
                pj = polygon[j]
                xi, yi = pi[0], pi[1]
                xj, yj = pj[0], pj[1]
                if ((yi > ny) != (yj > ny)) and (nx < (xj - xi) * (ny - yi) / (yj - yi) + xi):
                    inside = not inside
                j = i
            mask[y * grid_size + x] = inside

    return mask


def _polygon_area(polygon: list) -> float:
    """Shoelace formula for polygon area (normalized coordinates)."""
    n = len(polygon)
    if n < 3:
        return 0
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += polygon[i][0] * polygon[j][1]
        area -= polygon[j][0] * polygon[i][1]
    return abs(area) / 2


def _polygon_centroid(polygon: list) -> tuple[float, float]:
    """Compute centroid of a polygon."""
    n = len(polygon)
    if n == 0:
        return 0, 0
    cx = sum(p[0] for p in polygon) / n
    cy = sum(p[1] for p in polygon) / n
    return cx, cy


# ---------------------------------------------------------------------------
# Shadow Measurements (from SAM 2 boundary)
# ---------------------------------------------------------------------------


def _compute_shadow_measurements(shadow_boundary: dict | None) -> dict | None:
    """Compute basic measurements from the SAM 2 shadow boundary.

    Note: Full 3D measurements require the mesh — this computes 2D
    approximations. In production, reuse the iOS measurement engine
    server-side or project onto the uploaded mesh.
    """
    if not shadow_boundary:
        return None

    pts = shadow_boundary.get("points_2d", [])
    if len(pts) < 3:
        return None

    area = _polygon_area(pts)

    # Compute bounding box dimensions
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    width = max(xs) - min(xs)
    height = max(ys) - min(ys)

    # Perimeter
    perimeter = 0
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        dx = pts[j][0] - pts[i][0]
        dy = pts[j][1] - pts[i][1]
        perimeter += math.sqrt(dx * dx + dy * dy)

    return {
        "area_normalized": round(area, 6),
        "length_normalized": round(max(width, height), 4),
        "width_normalized": round(min(width, height), 4),
        "perimeter_normalized": round(perimeter, 4),
        "source": "sam2",
    }


# ---------------------------------------------------------------------------
# FWA Detection
# ---------------------------------------------------------------------------


async def detect_fwa_signals(
    session: AsyncSession,
    scan: Scan,
    agreement: dict | None,
) -> dict | None:
    """Detect Fraud/Waste/Abuse signals by analyzing the scan against
    historical data for the same nurse.

    Checks:
      - Agreement with SAM 2 baseline
      - Statistical outliers in wound size
      - Scan frequency anomalies
      - Copy-paste risk (similarity to recent scans)
    """
    # Query nurse's historical scans
    result = await session.execute(
        select(Scan)
        .where(Scan.nurse_id == scan.nurse_id)
        .where(Scan.id != scan.id)
        .where(Scan.upload_status == ScanStatus.COMPLETED)
        .order_by(Scan.captured_at.desc())
        .limit(50)
    )
    history = result.scalars().all()

    triggered_flags = []

    # 1. Low AI agreement
    nurse_iou = agreement.get("iou", 1.0) if agreement else 1.0
    if agreement:
        historical_ious = [
            s.agreement_metrics.get("iou", 0)
            for s in history
            if s.agreement_metrics
        ]
        baseline = sum(historical_ious) / len(historical_ious) if historical_ious else 0.85
    else:
        baseline = 0.85

    if nurse_iou < 0.5:
        triggered_flags.append("low_ai_agreement")

    # 2. Wound size outlier
    if scan.area_cm2 and history:
        historical_areas = [s.area_cm2 for s in history if s.area_cm2]
        if historical_areas:
            mean_area = sum(historical_areas) / len(historical_areas)
            std_area = (
                sum((a - mean_area) ** 2 for a in historical_areas) / len(historical_areas)
            ) ** 0.5
            if std_area > 0 and abs((scan.area_cm2 - mean_area) / std_area) > 3:
                triggered_flags.append("wound_size_outlier")

    # 3. Scan frequency check
    if len(history) >= 2:
        recent = [s for s in history if s.patient_id == scan.patient_id]
        if len(recent) >= 3:
            # More than 3 scans for same patient in recent history — check frequency
            intervals = []
            for i in range(len(recent) - 1):
                delta = abs((recent[i].captured_at - recent[i + 1].captured_at).total_seconds())
                intervals.append(delta)
            # Less than 1 hour between scans on average is suspicious
            if intervals and sum(intervals) / len(intervals) < 3600:
                triggered_flags.append("abnormal_scan_frequency")

    # 4. Copy-paste risk (simplified: check if boundary is identical to a recent scan)
    copy_paste_risk = 0.0
    if scan.boundary_points_2d:
        for prev in history[:10]:
            if prev.boundary_points_2d and prev.patient_id == scan.patient_id:
                similarity = _boundary_similarity(scan.boundary_points_2d, prev.boundary_points_2d)
                copy_paste_risk = max(copy_paste_risk, similarity)
                if similarity > 0.98:
                    triggered_flags.append("suspected_copy_paste")
                    break

    # Overall risk score
    risk_score = min(1.0, len(triggered_flags) * 0.25 + (1 - nurse_iou) * 0.3)

    return {
        "nurse_baseline_agreement": round(baseline, 4),
        "wound_size_outlier": "wound_size_outlier" in triggered_flags,
        "copy_paste_risk": round(copy_paste_risk, 4),
        "longitudinal_consistency": 1.0,  # TODO: implement trajectory analysis
        "overall_risk_score": round(risk_score, 4),
        "triggered_flags": triggered_flags,
    }


def _boundary_similarity(a: list, b: list) -> float:
    """Quick boundary similarity check (Hausdorff-like)."""
    if not a or not b:
        return 0
    if isinstance(a, dict):
        a = a.get("points_2d", a) if isinstance(a, dict) else a
    if isinstance(b, dict):
        b = b.get("points_2d", b) if isinstance(b, dict) else b
    if len(a) != len(b):
        return 0

    total_dist = 0
    for pa, pb in zip(a, b):
        if isinstance(pa, list) and isinstance(pb, list) and len(pa) >= 2 and len(pb) >= 2:
            total_dist += math.sqrt((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2)
        else:
            return 0

    avg_dist = total_dist / len(a)
    return max(0, 1 - avg_dist * 50)  # Normalize: dist 0 → similarity 1
