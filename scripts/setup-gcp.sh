#!/usr/bin/env bash
# =============================================================================
# setup-gcp.sh — One-time GCP infrastructure setup for AI Skincare Advisor
# =============================================================================
#
# Run this ONCE to enable all required APIs, create service accounts,
# and configure the GCP project for the AI Skincare Advisor.
#
# Usage:
#   ./scripts/setup-gcp.sh
#   ./scripts/setup-gcp.sh --project MY_PROJECT_ID
# =============================================================================

set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:?Error: GOOGLE_CLOUD_PROJECT env var is not set}"
REGION="${GOOGLE_CLOUD_LOCATION:-us-central1}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

echo "============================================="
echo "  AI Skincare Advisor — GCP Setup"
echo "============================================="
echo "  Project: $PROJECT_ID"
echo "  Region:  $REGION"
echo "============================================="
echo ""

gcloud config set project "$PROJECT_ID" --quiet

# --- Enable Required APIs ---
echo "→ Enabling required GCP APIs..."

APIS=(
  "aiplatform.googleapis.com"           # Vertex AI (Gemini, Agent Engine)
  "run.googleapis.com"                  # Cloud Run
  "cloudbuild.googleapis.com"           # Cloud Build (for Cloud Run source deploy)
  "artifactregistry.googleapis.com"     # Artifact Registry (container images)
  "discoveryengine.googleapis.com"      # Vertex AI Search
  "bigquery.googleapis.com"             # BigQuery (Agent Analytics)
  "firebaseappcheck.googleapis.com"     # Firebase App Check
  "fcm.googleapis.com"                  # Firebase Cloud Messaging
  "firebaseappdistribution.googleapis.com"  # Firebase App Distribution
)

for api in "${APIS[@]}"; do
  echo "  Enabling $api..."
  gcloud services enable "$api" --quiet 2>/dev/null || true
done
echo "  ✓ All APIs enabled"

# --- Create BigQuery Dataset for Agent Analytics ---
echo ""
echo "→ Creating BigQuery dataset for agent analytics..."
bq mk --dataset \
  --location="$REGION" \
  --description="ADK Agent Analytics logs for AI Skincare Advisor" \
  "${PROJECT_ID}:adk_agent_logs" 2>/dev/null || echo "  (dataset already exists)"
echo "  ✓ BigQuery dataset ready"

# --- Verify Vertex AI Agent Engine ---
echo ""
echo "→ Checking Vertex AI Agent Engine..."
AGENT_ENGINE_ID="${AGENT_ENGINE_ID:-}"
if [ -z "$AGENT_ENGINE_ID" ]; then
  echo "  ⚠ AGENT_ENGINE_ID not set. Run create_agent_engine.py to create one:"
  echo "    python scripts/create_agent_engine.py"
else
  echo "  ✓ Agent Engine ID: $AGENT_ENGINE_ID"
fi

echo ""
echo "============================================="
echo "  ✓ GCP setup complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Create Agent Engine:  python scripts/create_agent_engine.py"
echo "  2. Deploy backend:       ./scripts/deploy-backend.sh"
echo "  3. Build Flutter APK:    cd frontend/flutter_app && flutter build apk --release"
echo ""
