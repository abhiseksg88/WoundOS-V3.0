#!/bin/bash
#
# One-time GCP infrastructure setup for WoundOS Backend.
#
# This script creates all required GCP resources:
#   - Cloud SQL PostgreSQL instance
#   - Cloud Storage bucket
#   - Pub/Sub topic + subscription
#   - Secret Manager secrets
#   - VPC Connector
#   - Cloud Run migration job
#
# Prerequisites:
#   1. gcloud CLI installed and authenticated
#   2. GCP project created
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   ./scripts/setup_gcp.sh
#
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID environment variable}"
REGION="${GCP_REGION:-us-central1}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 24)}"

echo "============================================"
echo "Setting up GCP infrastructure for WoundOS"
echo "  Project: ${PROJECT_ID}"
echo "  Region:  ${REGION}"
echo "============================================"

gcloud config set project "${PROJECT_ID}"

# 1. Enable required APIs
echo ""
echo "[1/8] Enabling APIs..."
gcloud services enable \
    run.googleapis.com \
    sqladmin.googleapis.com \
    pubsub.googleapis.com \
    secretmanager.googleapis.com \
    vpcaccess.googleapis.com \
    cloudbuild.googleapis.com \
    containerregistry.googleapis.com

# 2. Cloud SQL
echo ""
echo "[2/8] Creating Cloud SQL instance..."
gcloud sql instances create woundos-db \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region="${REGION}" \
    --storage-size=10GB \
    --storage-auto-increase \
    --backup-start-time=03:00 \
    --availability-type=zonal \
    --root-password="${DB_PASSWORD}" \
    2>/dev/null || echo "  (Instance already exists)"

gcloud sql databases create woundos --instance=woundos-db \
    2>/dev/null || echo "  (Database already exists)"

gcloud sql users create woundos --instance=woundos-db --password="${DB_PASSWORD}" \
    2>/dev/null || echo "  (User already exists)"

INSTANCE_CONNECTION=$(gcloud sql instances describe woundos-db --format="value(connectionName)")
echo "  Instance: ${INSTANCE_CONNECTION}"

# 3. Cloud Storage
echo ""
echo "[3/8] Creating Cloud Storage buckets..."
for ENV in dev staging production; do
    gsutil mb -l "${REGION}" "gs://woundos-scans-${ENV}" 2>/dev/null || echo "  (Bucket woundos-scans-${ENV} already exists)"
    gsutil uniformbucketlevelaccess set on "gs://woundos-scans-${ENV}" 2>/dev/null || true
done

# 4. Pub/Sub
echo ""
echo "[4/8] Creating Pub/Sub topic..."
gcloud pubsub topics create scan-ready 2>/dev/null || echo "  (Topic already exists)"
gcloud pubsub subscriptions create sam2-worker-sub --topic=scan-ready 2>/dev/null || echo "  (Subscription already exists)"

# 5. Secret Manager
echo ""
echo "[5/8] Creating secrets..."
echo -n "${DB_PASSWORD}" | gcloud secrets create db-password --data-file=- 2>/dev/null || echo "  (Secret db-password already exists)"
echo -n "change-me" | gcloud secrets create jwt-signing-key --data-file=- 2>/dev/null || echo "  (Secret jwt-signing-key already exists)"
echo -n "" | gcloud secrets create anthropic-api-key --data-file=- 2>/dev/null || echo "  (Secret anthropic-api-key already exists)"

echo ""
echo "  IMPORTANT: Set your Anthropic API key:"
echo "  echo -n 'sk-ant-...' | gcloud secrets versions add anthropic-api-key --data-file=-"
echo ""
echo "  IMPORTANT: Set your JWT signing key:"
echo "  echo -n '$(openssl rand -base64 32)' | gcloud secrets versions add jwt-signing-key --data-file=-"

# 6. VPC Connector
echo ""
echo "[6/8] Creating VPC connector..."
gcloud compute networks vpc-access connectors create woundos-connector \
    --region="${REGION}" \
    --range=10.8.0.0/28 \
    2>/dev/null || echo "  (Connector already exists)"

# 7. Grant Cloud Run access to secrets
echo ""
echo "[7/8] Configuring IAM..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

for SECRET in db-password jwt-signing-key anthropic-api-key; do
    gcloud secrets add-iam-policy-binding "${SECRET}" \
        --member="serviceAccount:${SA}" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet 2>/dev/null || true
done

# Grant Cloud SQL access
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA}" \
    --role="roles/cloudsql.client" \
    --quiet 2>/dev/null || true

# 8. Create migration job
echo ""
echo "[8/8] Creating migration Cloud Run job..."
echo "  (Will be configured after first image build)"

echo ""
echo "============================================"
echo "GCP setup complete!"
echo ""
echo "  Cloud SQL: ${INSTANCE_CONNECTION}"
echo "  DB Password: ${DB_PASSWORD}"
echo "  Buckets: woundos-scans-{dev,staging,production}"
echo "  Pub/Sub: scan-ready"
echo ""
echo "Next steps:"
echo "  1. Save DB password: echo -n '${DB_PASSWORD}' > .db-password"
echo "  2. Set Anthropic key in Secret Manager"
echo "  3. Set JWT key in Secret Manager"
echo "  4. Run: ./scripts/deploy.sh staging"
echo "============================================"
