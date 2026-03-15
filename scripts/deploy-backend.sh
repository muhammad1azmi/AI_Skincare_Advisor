#!/usr/bin/env bash
# =============================================================================
# deploy-backend.sh — Deploy AI Skincare Advisor to Agent Engine Runtime
# =============================================================================
#
# This script wraps scripts/deploy.py for convenience.
#
# Usage:
#   ./scripts/deploy-backend.sh              # first deployment
#   ./scripts/deploy-backend.sh --update     # update existing
#
# Prerequisites:
#   - gcloud auth application-default login
#   - app/.env configured (AGENT_ENGINE_ID, GCS_STAGING_BUCKET)
#   - GCS staging bucket created
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo "  AI Skincare Advisor — Agent Engine Deploy"
echo "============================================="

# Ensure staging bucket exists
source "$ROOT_DIR/app/.env" 2>/dev/null || true
if [ -z "${GCS_STAGING_BUCKET:-}" ]; then
  echo "ERROR: GCS_STAGING_BUCKET not set in app/.env"
  echo "  Create: gsutil mb gs://your-project-staging"
  echo "  Add:    GCS_STAGING_BUCKET=gs://your-project-staging"
  exit 1
fi

# Run the Python deploy script
python "$SCRIPT_DIR/deploy.py" "$@"
