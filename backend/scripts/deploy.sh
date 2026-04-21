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
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "============================================"
echo "Deploying WoundOS Backend"
echo "  Environment: ${ENV}"
echo "  Project:     ${PROJECT_ID}"
echo "  Region:      ${REGION}"
echo "============================================"

# 1. Build and push container image
echo ""
echo "[1/4] Building container image..."
gcloud builds submit --tag "${IMAGE}:latest" --project "${PROJECT_ID}" .

# 2. Run database migrations
echo ""
echo "[2/4] Running database migrations..."
gcloud run jobs execute woundos-migrate \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --wait 2>/dev/null || echo "  (Migration job not found — run setup.sh first)"

# 3. Deploy to Cloud Run
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
    --set-env-vars "ENVIRONMENT=${ENV}" \
    --set-env-vars "DEBUG=false" \
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
