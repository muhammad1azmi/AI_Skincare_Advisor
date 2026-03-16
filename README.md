# 🧴 Glow — AI Skincare Advisor

> **A real-time multimodal AI skincare consultation agent** — talk to it, show it your skin, and get personalized advice powered by Gemini Live API and Google ADK.

**Category**: Live Agents 🗣️ | **Hackathon**: #GeminiLiveAgentChallenge

[![Built with Google ADK](https://img.shields.io/badge/Built%20with-Google%20ADK-4285F4?logo=google)](https://google.github.io/adk-docs/)
[![Powered by Gemini](https://img.shields.io/badge/Powered%20by-Gemini%202.5%20Flash-886FBF?logo=google)](https://ai.google.dev/)
[![Deployed on Cloud Run](https://img.shields.io/badge/Deployed%20on-Cloud%20Run-4285F4?logo=googlecloud)](https://cloud.google.com/run)
Blogpost: https://sites.google.com/borobudur.ai/ai-skincare-advisor/home

---

## 🎯 What It Does

Glow is a mobile app that provides **real-time voice + video skincare consultations**. Users can:

- **Talk naturally** to the AI advisor — real-time audio streaming with interruption handling
- **Show their skin** via camera — the AI analyzes conditions live (1 FPS video streaming)
- **Get interrupted** mid-response — graceful interruption handling built-in
- **Receive personalized routines** based on skin type, concerns, and goals
- **Check ingredient safety** — verify product ingredients and interactions
- **Track progress** — compare skin conditions over time with analysis snapshots
- **Browse KOL recommendations** — curated content from skincare influencers

The app seamlessly transitions from **live voice/video consultation** to **text chat**, preserving the full conversation transcript. Cross-session memory means the AI remembers you.

---

## 🏗️ Architecture

![Architecture Diagram](docs/architecture.png)

<details>
<summary>Text version (click to expand)</summary>

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App                         │
│  ┌──────────┐  ┌──────────────┐  ┌───────────┐  ┌───────────┐ │
│  │  Camera   │  │ Microphone   │  │ Text Chat │  │  FCM Push │ │
│  │ (JPEG 1fps│  │(PCM 16kHz)   │  │  Messages │  │  Notifs   │ │
│  └─────┬─────┘  └──────┬───────┘  └─────┬─────┘  └─────┬─────┘ │
│        │               │               │               │       │
│        └───────────────┴───────────────┴───────┬───────┘       │
│                                                │               │
│                    WebSocket (wss://)           │               │
│                    + Firebase JWT Auth          │               │
└────────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Google Cloud Run                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              FastAPI WebSocket Server                     │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │ Firebase JWT │  │ Bidi-Stream  │  │ FCM Push       │  │  │
│  │  │ Auth Verify  │  │ Lifecycle    │  │ Notifications  │  │  │
│  │  └─────────────┘  └──────┬───────┘  └────────────────┘  │  │
│  └──────────────────────────┼───────────────────────────────┘  │
│                             │                                   │
│  ┌──────────────────────────▼───────────────────────────────┐  │
│  │              Google ADK Runner                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │         Root Orchestrator (Gemini 2.5 Flash)        │  │  │
│  │  │    + Model Armor + Safety Guardrail Callbacks       │  │  │
│  │  └────────────────────┬───────────────────────────────┘  │  │
│  │                       │ AgentTool (x11)                   │  │
│  │  ┌────────┬───────────┼───────────┬───────────┐          │  │
│  │  ▼        ▼           ▼           ▼           ▼          │  │
│  │ Skin    Routine   Ingredient  Ingredient   Skin         │  │
│  │Analyzer Builder    Checker   Interaction  Condition     │  │
│  │  │        │          │           │           │           │  │
│  │  ▼        ▼          ▼           ▼           ▼           │  │
│  │ Q&A    KOL Content  Progress   Parallel    Pipeline     │  │
│  │ Agent    Agent       Tracker   Ingredient  Consultation │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             │                                   │
│  ┌──────────────────────────▼───────────────────────────────┐  │
│  │         Vertex AI Session Service                         │  │
│  │         (Persistent Managed Sessions)                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌──────────────┐ ┌───────────┐ ┌──────────────┐
     │  Vertex AI    │ │ BigQuery  │ │   Firebase   │
     │  Search       │ │ (KOL Data │ │  Auth + FCM  │
     │  (Datastores) │ │  + Agent  │ │              │
     │               │ │ Analytics)│ │              │
     └──────────────┘ └───────────┘ └──────────────┘
```

</details>

---

## 🎨 Design Pillars

### 🛡️ Security-First

5 layers of defense-in-depth for a health-adjacent AI:

1. **Google Cloud Model Armor** — ML-powered prompt/response sanitization (prompt injection, jailbreak, PII, harmful content, malicious URLs)
2. **before_model_callback** — domain-specific medical request blocking
3. **after_model_callback** — Model Armor response screening + medical language flagging
4. **Gemini safety filters** — configured SafetySettings (`BLOCK_MEDIUM_AND_ABOVE`)
5. **Root prompt guardrails** — explicit persona boundary instructions

### 📊 Observability-First

You can't improve what you can't measure:

- **BigQuery Agent Analytics** — all agent interactions logged to `adk_agent_logs` dataset
- **OpenTelemetry tracing** — every agent run, LLM call, tool invocation captured as spans
- **Custom dashboards** — p95 latency, token usage, routing accuracy, safety triggers

### 🧪 Eval-Driven Development

Every change goes through automated evaluation:

- **Routing accuracy tests** — does the orchestrator pick the right specialist?
- **Safety guardrail tests** — are medical requests properly deflected?
- **Response quality evaluations** — are recommendations relevant and safe?

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **AI Model** | Gemini 2.5 Flash (native audio) via ADK |
| **Agent Framework** | Google ADK (Agent Development Kit) |
| **Streaming** | Gemini Live API — bidi-streaming via `LiveRequestQueue` |
| **Backend** | FastAPI + Uvicorn on **Google Cloud Run** |
| **Agent Hosting** | Vertex AI Agent Engine (EXPERIMENTAL bidi-streaming) |
| **Sessions** | `VertexAiSessionService` (persistent, managed) |
| **Memory** | `PreloadMemoryTool` + `generate_memories_callback` |
| **Security** | Google Cloud Model Armor + multi-layer callbacks |
| **Authentication** | Firebase Auth (Google Sign-In + JWT) |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **Search & Grounding** | Vertex AI Search (skincare knowledge datastores) |
| **Analytics** | BigQuery (KOL content + agent analytics) |
| **Frontend** | Flutter (Android) — camera, mic, real-time UI |
| **CI/CD** | GitHub Actions → APK build → Firebase App Distribution |
| **IaC** | Automated GCP setup + Agent Engine deployment scripts |

### ☁️ Google Cloud Services Used

| Service | Purpose |
|---|---|
| **Cloud Run** | WebSocket server hosting (FastAPI + ADK) |
| **Vertex AI Agent Engine** | Production agent hosting with bidi-streaming |
| **Vertex AI (Gemini)** | LLM reasoning — audio, video, text |
| **Vertex AI Search** | RAG — skincare knowledge datastores |
| **BigQuery** | KOL content database + agent analytics |
| **Cloud Model Armor** | ML-powered input/output sanitization |
| **Firebase Auth** | User authentication (Google Sign-In) |
| **Firebase Cloud Messaging** | Push notifications |
| **Firebase App Distribution** | CI/CD APK delivery |
| **Cloud Build** | Container build for Cloud Run |
| **Artifact Registry** | Docker image storage |

---

## 🤖 Multi-Agent System

The root orchestrator coordinates **8 specialist agents + 3 workflow agents**:

| Agent | Purpose | Key Tools |
|---|---|---|
| 🔬 **Skin Analyzer** | Analyzes skin from camera images | `save_analysis_to_state` |
| 📋 **Routine Builder** | Creates personalized skincare routines | Vertex AI Search |
| 🧪 **Ingredient Checker** | Verifies ingredient safety & efficacy | Vertex AI Search |
| ⚠️ **Ingredient Interaction** | Checks for harmful ingredient combinations | Vertex AI Search |
| 🩺 **Skin Condition** | Identifies and explains skin conditions | Vertex AI Search |
| ❓ **Q&A Agent** | Answers general skincare questions | Vertex AI Search |
| 🌟 **KOL Content** | Recommends influencer-curated content | BigQuery + Vertex AI Search |
| 📊 **Progress Tracker** | Tracks skin improvements over time | `get_progress_summary` |
| ⚡ **Parallel Ingredient** | Runs ingredient + interaction checks simultaneously | Composite workflow |
| 🔄 **Consultation Pipeline** | End-to-end consultation workflow | Sequential pipeline |
| 🔁 **Routine Review Loop** | Iterative routine refinement | Loop pattern |

All sub-agents are wrapped as `AgentTool` instances — they execute in independent `Runner` contexts, avoiding live session conflicts with `VertexAiSearchTool`.

---

## 🚀 Quick Start

### Prerequisites

- Python 3.11+
- Flutter SDK 3.29+
- Google Cloud project with billing enabled
- Firebase project linked to GCP

### 1. Clone & Install Backend

```bash
git clone https://github.com/muhammad1azmi/AI_Skincare_Advisor.git
cd AI_Skincare_Advisor

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure Environment

Create `.env` in the project root:

```env
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_GENAI_USE_VERTEXAI=TRUE
AGENT_ENGINE_ID=your-agent-engine-id
```

### 3. Run Backend Locally

```bash
# Skip auth for local dev
export SKIP_AUTH=true

# Start the server
uvicorn server.main:app --host 0.0.0.0 --port 8080 --reload
```

The WebSocket endpoint will be available at `ws://localhost:8080/ws/{user_id}/{session_id}`.

### 4. Run Flutter App

```bash
cd frontend/flutter_app

# Install dependencies
flutter pub get

# Run on Android device/emulator
flutter run

# Or build APK
flutter build apk --release
```

For local development, update `lib/config.dart` to point to `ws://YOUR_LOCAL_IP:8080`.

---

## ☁️ Deploy to Google Cloud

### Automated Deployment (IaC)

The project includes infrastructure-as-code scripts for fully automated deployment:

#### Step 1: GCP Infrastructure Setup

```bash
# One-time setup: enables all APIs, creates BigQuery datasets, configures IAM
./scripts/setup-gcp.sh
```

This script enables: Vertex AI, Cloud Run, Cloud Build, Artifact Registry, Vertex AI Search, BigQuery, Firebase APIs.

#### Step 2: Deploy Agent to Vertex AI Agent Engine

```bash
# First deployment (creates new Agent Engine instance)
python scripts/deploy.py

# Update existing deployment
python scripts/deploy.py --update
```

Deploys the ADK agent with **EXPERIMENTAL server mode** for bidi-streaming (Gemini Live API).

#### Step 3: Deploy Backend to Cloud Run

```bash
# Deploy WebSocket server to Cloud Run
./scripts/deploy-backend.sh
```

Or manually:

```bash
gcloud run deploy skincare-advisor \
  --source=. \
  --region=us-central1 \
  --project=your-project-id \
  --allow-unauthenticated \
  --set-env-vars="GOOGLE_GENAI_USE_VERTEXAI=TRUE,GOOGLE_CLOUD_PROJECT=your-project-id,GOOGLE_CLOUD_LOCATION=us-central1,AGENT_ENGINE_ID=your-engine-id"
```

#### Step 4: Build & Distribute Flutter APK

Push to `main` branch triggers automatic APK build and Firebase App Distribution:

```bash
git push origin main
# → GitHub Actions builds APK → Firebase App Distribution → Testers get notified
```

Required GitHub Secrets:
- `FIREBASE_APP_ID` — Your Firebase Android app ID
- `FIREBASE_SERVICE_ACCOUNT` — Firebase service account JSON key

---

## 📁 Project Structure

```
AI_Skincare_Advisor/
├── app/skincare_advisor/          # ADK Agent system
│   ├── agent.py                   # Root orchestrator (Gemini 2.5 Flash)
│   ├── sub_agents/                # 8 specialist + 3 workflow agents
│   ├── tools/                     # Custom tools (skin analysis, progress)
│   ├── callbacks/                 # Memory generation callback
│   ├── prompts/                   # Agent instruction prompts
│   ├── model_armor.py             # Model Armor integration
│   └── tests/                     # ADK evaluation tests
├── server/                        # FastAPI backend
│   ├── main.py                    # WebSocket bidi-streaming server
│   ├── auth.py                    # Firebase JWT verification
│   ├── notifications.py           # FCM push notifications
│   ├── model_armor.py             # Server-side Model Armor
│   └── product_catalog.py         # Product data service
├── frontend/flutter_app/          # Flutter mobile app
│   ├── lib/
│   │   ├── screens/               # Chat, Consultation, Home, Login
│   │   ├── services/              # WebSocket, Auth, Audio, Camera, Notifications
│   │   ├── config.dart            # Backend URL configuration
│   │   └── main.dart              # App entry point
│   └── android/                   # Android platform config
├── scripts/                       # Deployment & setup scripts (IaC)
│   ├── setup-gcp.sh               # One-time GCP infrastructure setup
│   ├── deploy.py                  # Agent Engine deployment (create/update)
│   ├── deploy-backend.sh          # Cloud Run deployment
│   ├── create_agent_engine.py     # Agent Engine instance creation
│   └── create_model_armor_template.py  # Model Armor template setup
├── docs/                          # Documentation & diagrams
├── .github/workflows/             # CI/CD
│   ├── build-apk.yml              # APK build + Firebase distribution
│   └── run-eval.yml               # ADK evaluation pipeline
├── Dockerfile                     # Cloud Run container
├── requirements.txt               # Python dependencies
└── README.md                      # This file
```

---

## 🔒 Security

- **Google Cloud Model Armor** — ML-powered I/O sanitization (prompt injection, jailbreak, PII, harmful content)
- **Firebase Auth** — Google Sign-In with JWT verification on every WebSocket connection
- **No hardcoded secrets** — All credentials via environment variables
- **Non-root container** — Cloud Run runs as `appuser`
- **Safety guardrails** — before/after model callbacks reject medical and unsafe content
- **CORS restricted** — Only allowed origins

---

## 📊 Evaluation

The project includes ADK evaluation tests covering:

- **Routing accuracy** — Does the orchestrator pick the right specialist?
- **Safety guardrails** — Are medical requests properly deflected?
- **Response quality** — Are skincare recommendations relevant and helpful?

Run evaluations:
```bash
cd app
python -m pytest skincare_advisor/tests/ -v
```

---

## 🏆 Hackathon Highlights

| Criteria | How We Excel |
|---|---|
| **Multimodal I/O** | Camera (vision) + Microphone (audio) + Text → Voice + Text responses |
| **Live API** | Gemini Live API with bidi-streaming, real-time transcription |
| **Interruptible** | `LiveRequestQueue` handles user interruptions mid-response |
| **Multi-Agent** | 11 agents (8 specialist + 3 workflow) via AgentTool orchestration |
| **Security-First** | 5-layer defense: Model Armor + callbacks + Gemini filters + prompt guardrails |
| **Observability-First** | BigQuery analytics + OpenTelemetry tracing + custom dashboards |
| **Eval-Driven** | Automated routing, safety, and quality evaluation pipeline |
| **Google Cloud** | Cloud Run + Agent Engine + Vertex AI + BigQuery + Firebase + Model Armor |
| **Production-Ready** | CI/CD pipeline, auth, push notifications, persistent sessions, IaC |

---

## 📄 License

MIT

---

*Built with ❤️ using Google ADK, Gemini 2.5 Flash, and Google Cloud for the #GeminiLiveAgentChallenge*
