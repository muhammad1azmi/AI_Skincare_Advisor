# AI Skincare Advisor — Backend

Real-time multimodal skincare consultation platform built with **Google ADK** and **Gemini Live API**.

## Quick Start

```powershell
# 1. Create and activate virtual environment
cd c:\Users\azmis\Documents\AI_Skincare_Advisor
python -m venv .venv
.venv\Scripts\Activate.ps1

# 2. Install dependencies
pip install -r requirements.txt

# 3. Authenticate with Google Cloud
gcloud auth application-default login

# 4. Run with ADK dev server
cd app
adk web
```

Open http://localhost:8000 → select **skincare_advisor** → start chatting.

## Architecture

```
Root Orchestrator (skincare_advisor)
├── skin_analyzer         — Gemini Vision skin analysis
├── routine_builder       — AM/PM routine templates (Vertex AI Search)
├── ingredient_checker    — Ingredient safety (Vertex AI Search)
├── ingredient_interaction_agent — Conflicts & synergies (Vertex AI Search)
├── skin_condition_agent  — Condition info (Vertex AI Search)
├── qa_agent             — Education Q&A (Vertex AI Search)
├── kol_content_agent    — KOL influencer videos (Vertex AI Search)
└── progress_tracker     — Progress tracking (session state)
```

## Streaming Server

```powershell
# Run the FastAPI WebSocket server
cd c:\Users\azmis\Documents\AI_Skincare_Advisor
uvicorn server.main:app --host 0.0.0.0 --port 8080
```

WebSocket endpoint: `ws://localhost:8080/ws/{user_id}/{session_id}`

## Environment Variables

See `.env` for required configuration (GCP project, BigQuery dataset, etc.).
