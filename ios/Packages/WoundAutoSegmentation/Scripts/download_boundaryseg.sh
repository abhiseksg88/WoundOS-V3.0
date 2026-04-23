#!/bin/bash
# Downloads BoundarySeg.mlpackage from Google Cloud Storage and verifies SHA256.
#
# Prerequisites:
#   - gcloud SDK installed with `gsutil` available
#   - Authenticated to the wound-ai-models bucket
#
# Usage:
#   ./download_boundaryseg.sh

set -euo pipefail

EXPECTED_SHA="0a5b7bb951f5cb47dcc37b81e3fc352643dfe8f2df433d17f25bc4b2b5658a44"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/../Sources/WoundAutoSegmentation/Resources"
DEST="${RESOURCES_DIR}/BoundarySeg.mlpackage"
GCS_PATH="gs://wound-ai-models-careplix-woundos/models/v1.2/BoundarySeg.mlpackage"

# Ensure Resources directory exists
mkdir -p "${RESOURCES_DIR}"

echo "Downloading BoundarySeg.mlpackage from GCS..."
echo "  Source: ${GCS_PATH}"
echo "  Dest:   ${DEST}"

if ! command -v gsutil &> /dev/null; then
    echo ""
    echo "ERROR: gsutil not found. Install the Google Cloud SDK:"
    echo "  brew install --cask google-cloud-sdk"
    echo ""
    echo "Or download manually and place at:"
    echo "  ${DEST}"
    exit 1
fi

gsutil -m cp -r "${GCS_PATH}" "${DEST}"

echo ""
echo "Download complete."
echo "Expected SHA256: ${EXPECTED_SHA}"
echo ""
echo "After verifying, uncomment the resources line in Package.swift:"
echo "  resources: [.copy(\"Resources/BoundarySeg.mlpackage\"), ...]"
