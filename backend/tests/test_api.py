"""
API integration tests — run with: pytest tests/
"""

import json
import io

import pytest
from httpx import AsyncClient, ASGITransport

from app.core.auth import create_access_token
from app.main import app


@pytest.fixture
def auth_headers():
    """Generate a valid bearer token for tests."""
    token, _ = create_access_token(user_id="test-user", nurse_id="test-nurse")
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.anyio
async def test_health():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


@pytest.mark.anyio
async def test_root():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/")
        assert response.status_code == 200
        assert "WoundOS" in response.json()["service"]


@pytest.mark.anyio
async def test_auth_token():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/auth/token",
            json={"firebase_token": "test-firebase-token"},
        )
        assert response.status_code == 200
        data = response.json()
        assert "token" in data
        assert "expires_in" in data
        assert data["expires_in"] > 0


@pytest.mark.anyio
async def test_get_scan_not_found(auth_headers):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(
            "/v1/scans/00000000-0000-0000-0000-000000000000",
            headers=auth_headers,
        )
        assert response.status_code == 404


@pytest.mark.anyio
async def test_get_scan_status_not_found(auth_headers):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(
            "/v1/scans/00000000-0000-0000-0000-000000000000/status",
            headers=auth_headers,
        )
        assert response.status_code == 404


@pytest.mark.anyio
async def test_unauthorized_without_token():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/v1/scans/00000000-0000-0000-0000-000000000000")
        assert response.status_code == 403  # No credentials


@pytest.mark.anyio
async def test_patient_scans_empty(auth_headers):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(
            "/v1/patients/nonexistent-patient/scans",
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 0
        assert data["scans"] == []
