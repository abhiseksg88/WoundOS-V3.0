#!/bin/bash
#
# Deploy WoundOS Backend to Google Cloud Run.
#
# Prerequisites:
#   1. gcloud CLI installed and authenticated
#   2. Docker installed
#   3. GCP project created with required APIs enabled
#
# Usage:
#   ./scripts/deploy.sh              # Deploy to staging
#   ./scripts/deploy.sh production   # Deploy to production
#
set -euo pipefail

ENV="${1:-staging}"
PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID environment variable}"
REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="woundos-api"
MIGRATE_JOB="woundos-migrate"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "============================================"
echo "Deploying WoundOS Backend"
echo "  Environment: ${ENV}"
echo "  Project:     ${PROJECT_ID}"
echo "  Region:      ${REGION}"
echo "============================================"

# Resolve Cloud SQL instance connection name (needed by the app for the
# /cloudsql Unix socket). This was missing before — Cloud Run could not
# reach the database without it.
INSTANCE_CONNECTION=$(gcloud sql instances describe woundos-db \
    --project "${PROJECT_ID}" \
    --format="value(connectionName)")
if [[ -z "${INSTANCE_CONNECTION}" ]]; then
    echo "ERROR: Could not find Cloud SQL instance 'woundos-db'. Run setup_gcp.sh first." >&2
    exit 1
fi
echo "  Cloud SQL:   ${INSTANCE_CONNECTION}"

# Shared DB env vars used by both the migration job and the API service.
DB_ENV_VARS="DB_INSTANCE_CONNECTION_NAME=${INSTANCE_CONNECTION},DB_USER=woundos,DB_NAME=woundos"

# 1. Build and push container image
echo ""
echo "[1/4] Building container image..."
gcloud builds submit --tag "${IMAGE}:latest" --project "${PROJECT_ID}" .

# 2. Create/update and execute the database migration job.
# The job runs `alembic upgrade head` against Cloud SQL via the /cloudsql socket.
echo ""
echo "[2/4] Running database migrations..."
JOB_FLAGS=(
    --image "${IMAGE}:latest"
    --project "${PROJECT_ID}"
    --region "${REGION}"
    --set-cloudsql-instances "${INSTANCE_CONNECTION}"
    --set-env-vars "${DB_ENV_VARS}"
    --set-secrets "DB_PASSWORD=db-password:latest"
    --command alembic
    --args "upgrade,head"
    --task-timeout 600s
    --max-retries 1
)
if gcloud run jobs describe "${MIGRATE_JOB}" --project "${PROJECT_ID}" --region "${REGION}" >/dev/null 2>&1; then
    gcloud run jobs update "${MIGRATE_JOB}" "${JOB_FLAGS[@]}"
else
    gcloud run jobs create "${MIGRATE_JOB}" "${JOB_FLAGS[@]}"
fi
gcloud run jobs execute "${MIGRATE_JOB}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --wait

# 3. Deploy to Cloud Run
# Note: --add-cloudsql-instances mounts the /cloudsql/<instance> unix socket
# inside the container. The app reads DB_INSTANCE_CONNECTION_NAME and builds
# the socket path from it (see app/core/config.py).
echo ""
echo "[3/4] Deploying to Cloud Run..."
gcloud run deploy "${SERVICE_NAME}" \
    --image "${IMAGE}:latest" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --platform managed \
    --memory 512Mi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 10 \
    --timeout 300s \
    --allow-unauthenticated \
    --add-cloudsql-instances "${INSTANCE_CONNECTION}" \
    --set-env-vars "ENVIRONMENT=${ENV}" \
    --set-env-vars "DEBUG=false" \
    --set-env-vars "${DB_ENV_VARS}" \
    --set-env-vars "GCS_BUCKET=woundos-scans-${ENV}" \
    --set-env-vars "GCS_PROJECT_ID=${PROJECT_ID}" \
    --set-env-vars "PUBSUB_PROJECT_ID=${PROJECT_ID}" \
    --set-env-vars "FIREBASE_PROJECT_ID=${PROJECT_ID}" \
    --set-secrets "DB_PASSWORD=db-password:latest" \
    --set-secrets "ANTHROPIC_API_KEY=anthropic-api-key:latest" \
    --set-secrets "JWT_SECRET_KEY=jwt-signing-key:latest" \
    --vpc-connector "woundos-connector" \
    --vpc-egress "private-ranges-only"

# 4. Get the service URL
echo ""
echo "[4/4] Getting service URL..."
URL=$(gcloud run services describe "${SERVICE_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --format "value(status.url)")

echo ""
echo "============================================"
echo "Deployment complete!"
echo "  API URL: ${URL}"
echo "  Health:  ${URL}/health"
echo "  Docs:    ${URL}/docs"
echo "============================================"
