"""
Firebase Auth token verification + JWT bearer token issuance.
"""

import time
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings

settings = get_settings()
security = HTTPBearer()


# ---------------------------------------------------------------------------
# JWT token creation (issued by our API after Firebase verification)
# ---------------------------------------------------------------------------


def create_access_token(
    user_id: str,
    nurse_id: str = "",
    facility_id: str = "",
    roles: list[str] | None = None,
) -> tuple[str, int]:
    """Create a signed JWT for the iOS app to use as Bearer token.

    Returns (token_string, expires_in_seconds).
    """
    now = datetime.now(timezone.utc)
    expires = now + timedelta(seconds=settings.JWT_EXPIRATION_SECONDS)
    payload = {
        "sub": user_id,
        "nurse_id": nurse_id,
        "facility_id": facility_id,
        "roles": roles or ["nurse"],
        "iat": now,
        "exp": expires,
    }
    token = jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return token, settings.JWT_EXPIRATION_SECONDS


# ---------------------------------------------------------------------------
# JWT token verification (on every authenticated request)
# ---------------------------------------------------------------------------


def decode_access_token(token: str) -> dict:
    """Decode and verify a JWT bearer token."""
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """FastAPI dependency — extracts and verifies the bearer token."""
    return decode_access_token(credentials.credentials)


# ---------------------------------------------------------------------------
# Firebase ID token verification
# ---------------------------------------------------------------------------


async def verify_firebase_token(id_token: str) -> dict:
    """Verify a Firebase Auth ID token.

    In production, uses firebase-admin SDK.
    In development, accepts any token and returns a stub user.
    """
    if settings.ENVIRONMENT.value == "development" and not settings.FIREBASE_PROJECT_ID:
        # Dev stub — accept any token
        return {
            "uid": "dev-user-001",
            "email": "dev@woundos.com",
            "name": "Dev Nurse",
        }

    # Production: verify with Firebase Admin SDK
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth

        # Initialize Firebase app if not already done
        if not firebase_admin._apps:
            firebase_admin.initialize_app()

        decoded = firebase_auth.verify_id_token(id_token)
        return {
            "uid": decoded["uid"],
            "email": decoded.get("email", ""),
            "name": decoded.get("name", ""),
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Firebase token verification failed: {e}",
        )
