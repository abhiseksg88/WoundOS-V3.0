"""
Clinical summary generation via Claude Haiku.

Produces a structured clinical wound assessment narrative from
measurement data and PUSH scores.
"""

import json
import logging

from app.core.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)

CLINICAL_PROMPT = """You are a clinical wound care documentation assistant. Generate a structured wound assessment summary from the following measurement data.

**Wound Measurements:**
- Surface Area: {area_cm2:.2f} cm²
- Maximum Depth: {max_depth_mm:.1f} mm
- Mean Depth: {mean_depth_mm:.1f} mm
- Volume: {volume_ml:.2f} mL
- Length × Width: {length_mm:.1f} × {width_mm:.1f} mm
- Perimeter: {perimeter_mm:.1f} mm

**PUSH Score 3.0:** {push_total_score}/17
- Tissue Type: {tissue_type}
- Exudate Amount: {exudate_amount}

**Device:** {device_model}
**Capture Quality:** Mesh hit rate {mesh_hit_rate:.0%}, depth confidence {mean_depth_confidence:.1f}/2.0

Respond with ONLY valid JSON in this exact format:
{{
  "narrative_summary": "2-3 sentence clinical narrative describing the wound",
  "trajectory": "improving|stable|deteriorating|insufficient_data",
  "key_findings": ["finding 1", "finding 2"],
  "recommendations": ["recommendation 1", "recommendation 2"]
}}"""


async def generate_clinical_summary(scan_data: dict) -> dict | None:
    """Generate a clinical summary using Claude Haiku.

    Args:
        scan_data: Dict with measurement fields from the Scan model.

    Returns:
        Dict with narrative_summary, trajectory, key_findings, recommendations.
        None if generation fails.
    """
    if not settings.ANTHROPIC_API_KEY:
        logger.warning("ANTHROPIC_API_KEY not set — skipping clinical summary")
        return _generate_fallback_summary(scan_data)

    try:
        import anthropic

        client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

        prompt = CLINICAL_PROMPT.format(
            area_cm2=scan_data.get("area_cm2", 0),
            max_depth_mm=scan_data.get("max_depth_mm", 0),
            mean_depth_mm=scan_data.get("mean_depth_mm", 0),
            volume_ml=scan_data.get("volume_ml", 0),
            length_mm=scan_data.get("length_mm", 0),
            width_mm=scan_data.get("width_mm", 0),
            perimeter_mm=scan_data.get("perimeter_mm", 0),
            push_total_score=scan_data.get("push_total_score", 0),
            tissue_type=scan_data.get("tissue_type", "unknown"),
            exudate_amount=scan_data.get("exudate_amount", "unknown"),
            device_model=scan_data.get("device_model", "unknown"),
            mesh_hit_rate=scan_data.get("mesh_hit_rate", 0),
            mean_depth_confidence=scan_data.get("mean_depth_confidence", 0),
        )

        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}],
        )

        text = response.content[0].text
        summary = json.loads(text)
        summary["model_version"] = "claude-haiku-4-5-20251001"
        return summary

    except Exception as e:
        logger.error(f"Clinical summary generation failed: {e}")
        return _generate_fallback_summary(scan_data)


def _generate_fallback_summary(scan_data: dict) -> dict:
    """Generate a basic template summary when Claude is unavailable."""
    area = scan_data.get("area_cm2", 0)
    depth = scan_data.get("max_depth_mm", 0)
    push = scan_data.get("push_total_score", 0)

    size_desc = "small" if area < 2 else ("moderate" if area < 10 else "large")
    depth_desc = "shallow" if depth < 5 else ("moderate depth" if depth < 15 else "deep")

    return {
        "narrative_summary": (
            f"A {size_desc}, {depth_desc} wound measuring {area:.1f} cm² "
            f"with a PUSH score of {push}/17. "
            f"Tissue type is {scan_data.get('tissue_type', 'unspecified')} "
            f"with {scan_data.get('exudate_amount', 'unspecified')} exudate."
        ),
        "trajectory": "insufficient_data",
        "key_findings": [
            f"Wound area: {area:.1f} cm²",
            f"Maximum depth: {depth:.1f} mm",
            f"PUSH score: {push}/17",
        ],
        "recommendations": [
            "Continue monitoring wound dimensions at regular intervals",
            "Document any changes in tissue type or exudate characteristics",
        ],
        "model_version": "fallback-template-v1",
    }
