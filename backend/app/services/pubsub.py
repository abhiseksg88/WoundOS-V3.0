"""
Google Cloud Pub/Sub service — publishes scan-ready events for async processing.

In development mode (no PUBSUB_PROJECT_ID), processes scans synchronously
in a background task instead.
"""

import json
import logging

from app.core.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


class PubSubService:
    def __init__(self):
        self._publisher = None

    def _get_publisher(self):
        if self._publisher is None and settings.PUBSUB_PROJECT_ID:
            from google.cloud import pubsub_v1
            self._publisher = pubsub_v1.PublisherClient()
        return self._publisher

    @property
    def _topic_path(self) -> str:
        return f"projects/{settings.PUBSUB_PROJECT_ID}/topics/{settings.PUBSUB_TOPIC_SCAN_READY}"

    async def publish_scan_ready(self, scan_id: str, gcs_paths: dict) -> bool:
        """Publish a scan-ready event to trigger SAM 2 processing.

        Args:
            scan_id: UUID string of the uploaded scan.
            gcs_paths: Dict with rgb_image, depth_map, mesh, metadata paths.

        Returns:
            True if published (or processed locally), False on error.
        """
        message = {
            "scan_id": scan_id,
            "rgb_path": gcs_paths.get("rgb_image", ""),
            "depth_path": gcs_paths.get("depth_map", ""),
            "mesh_path": gcs_paths.get("mesh", ""),
            "metadata_path": gcs_paths.get("metadata", ""),
        }

        publisher = self._get_publisher()
        if publisher is not None:
            # Production: publish to Pub/Sub
            try:
                data = json.dumps(message).encode("utf-8")
                future = publisher.publish(self._topic_path, data=data)
                message_id = future.result(timeout=10)
                logger.info(f"Published scan-ready for {scan_id}, message_id={message_id}")
                return True
            except Exception as e:
                logger.error(f"Failed to publish scan-ready for {scan_id}: {e}")
                return False
        else:
            # Development: process inline via background task
            logger.info(f"Dev mode: scan-ready event for {scan_id} (will process in background)")
            return True


# Singleton
pubsub_service = PubSubService()
