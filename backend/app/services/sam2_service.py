"""
SAM 2 segmentation service.

Provides wound boundary segmentation using Meta's Segment Anything Model 2.
Falls back to a contour-based heuristic when SAM 2 is not available
(e.g. no GPU, model not downloaded, or running in lightweight mode).
"""

import io
import logging
import os
from typing import Optional

import cv2
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Global model cache
# ---------------------------------------------------------------------------

_sam2_predictor = None
_model_loaded = False


def _get_predictor():
    """Lazy-load SAM 2 predictor (cached globally)."""
    global _sam2_predictor, _model_loaded

    if _model_loaded:
        return _sam2_predictor

    _model_loaded = True

    try:
        import torch
        from sam2.build_sam import build_sam2
        from sam2.sam2_image_predictor import SAM2ImagePredictor

        checkpoint = os.environ.get(
            "SAM2_CHECKPOINT",
            "/app/models/sam2.1_hiera_large.pt",
        )
        model_cfg = os.environ.get(
            "SAM2_MODEL_CFG",
            "configs/sam2.1/sam2.1_hiera_l.yaml",
        )

        if not os.path.exists(checkpoint):
            logger.warning(f"SAM 2 checkpoint not found at {checkpoint} — using fallback segmenter")
            return None

        device = "cuda" if torch.cuda.is_available() else "cpu"
        logger.info(f"Loading SAM 2 model on {device}...")

        model = build_sam2(model_cfg, checkpoint, device=device)
        _sam2_predictor = SAM2ImagePredictor(model)

        logger.info("SAM 2 model loaded successfully")
        return _sam2_predictor

    except ImportError:
        logger.warning("SAM 2 / torch not installed — using fallback segmenter")
        return None
    except Exception as e:
        logger.error(f"Failed to load SAM 2: {e}")
        return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


async def segment_wound(
    image_bytes: bytes,
    tap_point: list[float],
    image_width: int,
    image_height: int,
) -> dict:
    """Segment a wound from an image using a tap point prompt.

    Args:
        image_bytes: JPEG-encoded image data.
        tap_point: [x, y] in pixel coordinates (origin top-left).
        image_width: Original image width.
        image_height: Original image height.

    Returns:
        dict with keys: polygon (list of [x,y] in pixel coords),
        confidence, model_version.
    """
    # Decode image
    pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    np_image = np.array(pil_image)

    predictor = _get_predictor()

    if predictor is not None:
        return _segment_with_sam2(predictor, np_image, tap_point)
    else:
        return _segment_with_fallback(np_image, tap_point)


# ---------------------------------------------------------------------------
# SAM 2 inference
# ---------------------------------------------------------------------------


def _segment_with_sam2(
    predictor,
    np_image: np.ndarray,
    tap_point: list[float],
) -> dict:
    """Run SAM 2 with point prompt."""
    import torch

    predictor.set_image(np_image)

    point_coords = np.array([[tap_point[0], tap_point[1]]])
    point_labels = np.array([1])  # 1 = foreground

    masks, scores, _ = predictor.predict(
        point_coords=point_coords,
        point_labels=point_labels,
        multimask_output=True,
    )

    # Pick the mask with highest score
    best_idx = int(np.argmax(scores))
    mask = masks[best_idx]
    confidence = float(scores[best_idx])

    polygon = _mask_to_polygon(mask)

    return {
        "polygon": polygon,
        "confidence": round(confidence, 4),
        "model_version": "sam2.1-hiera-large",
    }


# ---------------------------------------------------------------------------
# Fallback: OpenCV contour-based segmentation
# ---------------------------------------------------------------------------


def _segment_with_fallback(
    np_image: np.ndarray,
    tap_point: list[float],
) -> dict:
    """Fallback segmenter using GrabCut + contour extraction.

    Uses the tap point to seed a foreground region, then refines with
    GrabCut for wound-like color regions.
    """
    h, w = np_image.shape[:2]
    tx, ty = int(tap_point[0]), int(tap_point[1])

    # Seed rect around tap point (30% of image dimensions)
    rect_w = max(int(w * 0.3), 50)
    rect_h = max(int(h * 0.3), 50)
    x1 = max(0, tx - rect_w // 2)
    y1 = max(0, ty - rect_h // 2)
    x2 = min(w, tx + rect_w // 2)
    y2 = min(h, ty + rect_h // 2)

    mask = np.zeros((h, w), np.uint8)
    bgd_model = np.zeros((1, 65), np.float64)
    fgd_model = np.zeros((1, 65), np.float64)

    rect = (x1, y1, x2 - x1, y2 - y1)

    try:
        cv2.grabCut(np_image, mask, rect, bgd_model, fgd_model, 5, cv2.GC_INIT_WITH_RECT)
    except cv2.error:
        # GrabCut can fail on certain images — return a circle around tap point
        return _circle_fallback(tap_point, w, h)

    # Foreground = GC_FGD (1) or GC_PR_FGD (3)
    fg_mask = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)

    # Morphological cleanup
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_OPEN, kernel, iterations=1)

    polygon = _mask_to_polygon(fg_mask > 0, max_points=60)

    if len(polygon) < 3:
        return _circle_fallback(tap_point, w, h)

    return {
        "polygon": polygon,
        "confidence": 0.65,
        "model_version": "fallback-grabcut-v1",
    }


def _circle_fallback(
    tap_point: list[float],
    width: int,
    height: int,
    radius_frac: float = 0.1,
) -> dict:
    """Last-resort: return a circle around the tap point."""
    import math

    cx, cy = tap_point[0], tap_point[1]
    radius = min(width, height) * radius_frac
    n_points = 32

    polygon = []
    for i in range(n_points):
        angle = 2 * math.pi * i / n_points
        px = cx + radius * math.cos(angle)
        py = cy + radius * math.sin(angle)
        polygon.append([round(px, 1), round(py, 1)])

    return {
        "polygon": polygon,
        "confidence": 0.3,
        "model_version": "fallback-circle-v1",
    }


# ---------------------------------------------------------------------------
# Mask → Polygon extraction
# ---------------------------------------------------------------------------


def _mask_to_polygon(
    mask: np.ndarray,
    max_points: int = 80,
) -> list[list[float]]:
    """Convert a boolean/uint8 mask to a simplified polygon.

    Returns a list of [x, y] points in pixel coordinates.
    """
    mask_uint8 = (mask.astype(np.uint8) * 255) if mask.dtype == bool else mask

    contours, _ = cv2.findContours(mask_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        return []

    # Pick the largest contour
    largest = max(contours, key=cv2.contourArea)

    # Simplify with Douglas-Peucker
    perimeter = cv2.arcLength(largest, True)
    epsilon = perimeter * 0.005  # Start tight
    simplified = cv2.approxPolyDP(largest, epsilon, True)

    # If still too many points, increase epsilon
    while len(simplified) > max_points and epsilon < perimeter * 0.05:
        epsilon *= 1.5
        simplified = cv2.approxPolyDP(largest, epsilon, True)

    polygon = []
    for pt in simplified:
        polygon.append([round(float(pt[0][0]), 1), round(float(pt[0][1]), 1)])

    return polygon
