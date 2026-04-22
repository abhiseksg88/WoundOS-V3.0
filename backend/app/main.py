"""
WoundOS Backend — FastAPI application entry point.

Run locally:
    uvicorn app.main:app --reload --port 8080

Run with Docker:
    docker-compose up
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router as api_router
from app.core.config import get_settings
from app.workers.pubsub_handler import router as pubsub_router

settings = get_settings()

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

app = FastAPI(
    title=settings.PROJECT_NAME,
    version="1.0.0",
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
)

# CORS — allow the iOS app (and local dev tools) to call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount API routes under /v1
app.include_router(api_router, prefix=settings.API_V1_PREFIX)

# Mount Pub/Sub push handler (for Cloud Run worker receiving scan-ready events)
app.include_router(pubsub_router)


# ---------------------------------------------------------------------------
# Health check (for Cloud Run + load balancer)
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok", "service": "woundos-api"}


@app.get("/")
async def root():
    return {"service": "WoundOS Backend", "version": "1.0.0", "docs": "/docs"}


# ---------------------------------------------------------------------------
# Startup / Shutdown
# ---------------------------------------------------------------------------


@app.on_event("startup")
async def startup():
    logging.info(f"WoundOS Backend starting (env={settings.ENVIRONMENT.value})")


@app.on_event("shutdown")
async def shutdown():
    logging.info("WoundOS Backend shutting down")
