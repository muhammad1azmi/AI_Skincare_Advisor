#!/usr/bin/env bash
# =============================================================================
# deploy-backend.sh — Automated Cloud Run deployment for AI Skincare Advisor
# =============================================================================
#
# Usage:
#   ./scripts/deploy-backend.sh                    # uses defaults
#   ./scripts/deploy-backend.sh --project MY_PROJ  # override project
#
# Prerequisites:
#   - gcloud CLI authenticated (gcloud auth login)
#   - Billing enabled on the GCP project
#   - Required APIs enabled (run setup-gcp.sh first)
# =============================================================================

set -euo pipefail

# --- Configuration (override via env vars or flags) ---
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-boreal-graph-465506-f2}"
REGION="${GOOGLE_CLOUD_LOCATION:-us-central1}"
SERVICE_NAME="skincare-advisor"
AGENT_ENGINE_ID="${AGENT_ENGINE_ID:-}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-3}"
MEMORY="${MEMORY:-1Gi}"
CPU="${CPU:-1}"
TIMEOUT="${TIMEOUT:-300}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --agent-engine-id) AGENT_ENGINE_ID="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

echo "============================================="
echo "  AI Skincare Advisor — Cloud Run Deployment"
echo "============================================="
echo "  Project:   $PROJECT_ID"
echo "  Region:    $REGION"
echo "  Service:   $SERVICE_NAME"
echo "  Memory:    $MEMORY"
echo "  CPU:       $CPU"
echo "============================================="
echo ""

# --- Step 1: Verify gcloud auth ---
echo "→ Verifying gcloud authentication..."
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [ -z "$ACCOUNT" ]; then
  echo "✗ Not authenticated. Run: gcloud auth login"
  exit 1
fi
echo "  ✓ Authenticated as: $ACCOUNT"

# --- Step 2: Set project ---
echo "→ Setting project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID" --quiet

# --- Step 3: Build environment variables ---
ENV_VARS="GOOGLE_GENAI_USE_VERTEXAI=TRUE"
ENV_VARS+=",GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
ENV_VARS+=",GOOGLE_CLOUD_LOCATION=$REGION"

if [ -n "$AGENT_ENGINE_ID" ]; then
  ENV_VARS+=",AGENT_ENGINE_ID=$AGENT_ENGINE_ID"
fi

# --- Step 4: Deploy to Cloud Run ---
echo ""
echo "→ Deploying to Cloud Run..."
echo "  (This will build the container and deploy — may take 3-5 minutes)"
echo ""

gcloud run deploy "$SERVICE_NAME" \
  --source=. \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --allow-unauthenticated \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --min-instances="$MIN_INSTANCES" \
  --max-instances="$MAX_INSTANCES" \
  --set-env-vars="$ENV_VARS" \
  --quiet

# --- Step 5: Verify deployment ---
echo ""
echo "→ Verifying deployment..."
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --format="value(status.url)" 2>/dev/null)

echo ""
echo "============================================="
echo "  ✓ Deployment successful!"
echo "============================================="
echo "  Service URL:  $SERVICE_URL"
echo "  Health check: $SERVICE_URL/"
echo "  WebSocket:    ${SERVICE_URL/https/wss}/ws/{user_id}/{session_id}"
echo "============================================="

# Hit health check
echo ""
echo "→ Health check response:"
curl -s "$SERVICE_URL/" | python3 -m json.tool 2>/dev/null || curl -s "$SERVICE_URL/"
echo ""
