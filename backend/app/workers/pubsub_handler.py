"""
Pub/Sub push handler — receives scan-ready messages from Cloud Run.

In production, this is deployed as a separate Cloud Run service
that receives Pub/Sub push messages via HTTP POST.

Usage:
    Deploy as a second Cloud Run service with Pub/Sub push subscription.
    The push subscription sends POST requests to /pubsub/push with the
    scan-ready message payload.
"""

import base64
import json
import logging

from fastapi import APIRouter, HTTPException, Request

from app.workers.sam2_processor import process_scan

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/pubsub/push")
async def handle_pubsub_push(request: Request):
    """Handle a Pub/Sub push message.

    Pub/Sub sends a JSON envelope with the message data base64-encoded.
    """
    try:
        envelope = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    if not isinstance(envelope, dict) or "message" not in envelope:
        raise HTTPException(status_code=400, detail="Missing message field")

    message = envelope["message"]
    if "data" not in message:
        raise HTTPException(status_code=400, detail="Missing data field")

    # Decode the base64 message data
    try:
        data = json.loads(base64.b64decode(message["data"]).decode("utf-8"))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid message data: {e}")

    scan_id = data.get("scan_id")
    if not scan_id:
        raise HTTPException(status_code=400, detail="Missing scan_id")

    logger.info(f"Received Pub/Sub message for scan {scan_id}")

    # Process the scan
    success = await process_scan(scan_id)

    if not success:
        # Return 500 so Pub/Sub retries
        raise HTTPException(status_code=500, detail=f"Processing failed for {scan_id}")

    # Return 200 to acknowledge the message
    return {"status": "ok", "scan_id": scan_id}
