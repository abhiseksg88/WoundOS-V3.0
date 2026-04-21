"""
Google Cloud Storage service for wound scan binary data.

Handles upload/download of RGB images, depth maps, meshes, and metadata.
Falls back to local filesystem storage in development mode.
"""

import os
import uuid
from pathlib import Path

from app.core.config import get_settings

settings = get_settings()


class StorageService:
    """Abstraction over GCS (production) and local filesystem (development)."""

    def __init__(self):
        self._client = None
        self._bucket = None
        self._local_dir = Path("/tmp/woundos-uploads")

    def _get_bucket(self):
        if self._bucket is None:
            if settings.GCS_PROJECT_ID:
                from google.cloud import storage
                self._client = storage.Client(project=settings.GCS_PROJECT_ID)
                self._bucket = self._client.bucket(settings.GCS_BUCKET)
            else:
                # Local dev — use filesystem
                self._local_dir.mkdir(parents=True, exist_ok=True)
        return self._bucket

    async def upload_file(
        self,
        scan_id: str,
        filename: str,
        data: bytes,
        content_type: str = "application/octet-stream",
    ) -> str:
        """Upload a file and return its storage path.

        Returns:
            GCS path (gs://bucket/...) or local file path.
        """
        gcs_path = f"{scan_id}/{filename}"
        bucket = self._get_bucket()

        if bucket is not None:
            # GCS upload
            blob = bucket.blob(gcs_path)
            blob.upload_from_string(data, content_type=content_type)
            return f"gs://{settings.GCS_BUCKET}/{gcs_path}"
        else:
            # Local dev filesystem
            scan_dir = self._local_dir / scan_id
            scan_dir.mkdir(parents=True, exist_ok=True)
            file_path = scan_dir / filename
            file_path.write_bytes(data)
            return str(file_path)

    async def download_file(self, path: str) -> bytes:
        """Download a file by its storage path."""
        bucket = self._get_bucket()

        if bucket is not None and path.startswith("gs://"):
            # GCS download
            blob_path = path.replace(f"gs://{settings.GCS_BUCKET}/", "")
            blob = bucket.blob(blob_path)
            return blob.download_as_bytes()
        else:
            # Local dev filesystem
            return Path(path).read_bytes()

    async def file_exists(self, path: str) -> bool:
        """Check if a file exists."""
        bucket = self._get_bucket()

        if bucket is not None and path.startswith("gs://"):
            blob_path = path.replace(f"gs://{settings.GCS_BUCKET}/", "")
            blob = bucket.blob(blob_path)
            return blob.exists()
        else:
            return Path(path).exists()


# Singleton
storage_service = StorageService()
