---
description: How to redeploy the backend (Agent Engine + Cloud Run)
---

# Backend Redeployment

Deploys the `skincare_advisor` agent to Google Cloud Agent Engine and the WebSocket server to Cloud Run.

## Prerequisites

- `gcloud auth application-default login` (authenticated)
- Python with `google-adk` installed (`pip install google-adk`)
- `app/.env` configured with `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`

## Agent Engine Deploy (ADK agent code)

// turbo-all

1. Set UTF-8 encoding (Windows only — prevents crash on emoji output):
```powershell
$env:PYTHONIOENCODING="utf-8"
```

2. Deploy (update existing Agent Engine):
```powershell
adk deploy agent_engine --project=boreal-graph-465506-f2 --region=us-central1 --display_name="AI Skincare Advisor" --agent_engine_id=8778253446047334400 app/skincare_advisor
```

3. Verify the deploy succeeded by checking Cloud Logs:
```powershell
gcloud logging read "resource.labels.reasoning_engine_id=8778253446047334400 severity>=ERROR" --project=boreal-graph-465506-f2 --limit=5 --freshness=10m --format="table(timestamp,severity,textPayload)"
```

If the output is empty — no errors, deploy is healthy.

## Cloud Run Deploy (WebSocket server)

4. Deploy the WebSocket server to Cloud Run:
```powershell
gcloud run deploy skincare-advisor --project=boreal-graph-465506-f2 --region=us-central1 --source=. --allow-unauthenticated --set-env-vars="GOOGLE_CLOUD_PROJECT=boreal-graph-465506-f2,GOOGLE_CLOUD_LOCATION=us-central1,AGENT_ENGINE_ID=8778253446047334400,MODEL_ARMOR_TEMPLATE_ID=skincare-advisor-safety,MODEL_ARMOR_LOCATION=us-central1,ENV=production,ADMIN_UIDS=GNokVNMwVJYClJGaW22ggf4AKH43"
```

## What the CLI Does

1. Copies `app/skincare_advisor/` source to a temp staging folder
2. Reads `requirements.txt` from the agent directory
3. Reads `.agent_engine_config.json` for env vars (e.g., `MODEL_ARMOR_TEMPLATE_ID`)
4. Generates `agent_engine_app.py` wrapper
5. Uploads everything and updates the Agent Engine instance

## Fresh Deploy (new Agent Engine)

If you need to create a brand new instance instead of updating:

```powershell
$env:PYTHONIOENCODING="utf-8"
adk deploy agent_engine --project=boreal-graph-465506-f2 --region=us-central1 --display_name="AI Skincare Advisor" app/skincare_advisor
```

Then update `AGENT_ENGINE_ID` in `app/.env` with the new ID from the output.

## Troubleshooting

- **`charmap` codec error**: Make sure `$env:PYTHONIOENCODING="utf-8"` is set
- **`failed to start and cannot serve traffic`**: Check Cloud Logs for the actual error:
  ```powershell
  gcloud logging read "resource.labels.reasoning_engine_id=8778253446047334400 severity>=ERROR" --project=boreal-graph-465506-f2 --limit=5 --freshness=30m --format=json
  ```
- **Model Armor 403**: Ensure the compute SA has `roles/modelarmor.user`:
  ```powershell
  gcloud projects add-iam-policy-binding boreal-graph-465506-f2 --member="serviceAccount:1089521368524-compute@developer.gserviceaccount.com" --role="roles/modelarmor.user"
  ```
