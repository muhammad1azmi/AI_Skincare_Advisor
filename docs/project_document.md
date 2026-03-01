# AI Skincare Advisor — Project Document

> **Powered by Google ADK & Gemini Live API**
> Real-time multimodal skincare analysis and personalized recommendations using voice, video, and text interaction.
>
> Version 1.0 | February 2026
> Google Cloud · Google ADK · Gemini · Firebase

---

## 1. Executive Summary

The AI Skincare Advisor is an intelligent, real-time skincare consultation platform that leverages Google's Agent Development Kit (ADK) and Gemini Live API to deliver personalized skincare guidance through natural voice, video, and text interactions.

Users can point their camera at their skin, speak about their concerns, and receive immediate, contextual advice from a multi-agent AI system. The platform analyzes visible skin conditions, recommends tailored routines, checks ingredient compatibility, and tracks progress over time — all within a fully Google-native technology stack.

> **Mission:** Democratize access to personalized skincare advice through AI, making expert-level guidance available to anyone with a smartphone — while always encouraging professional dermatological consultation for serious concerns.

### 1.1 Key Objectives

- Provide real-time, multimodal skincare analysis via voice and video using Gemini Live API
- Build a multi-agent system with specialized agents for skin analysis, routine building, ingredient checking, and progress tracking
- Deliver personalized, evidence-based skincare recommendations grounded in dermatological knowledge
- Ensure user privacy and data security with encrypted storage and full user control over their data
- Deploy on a fully Google-native stack: ADK, Gemini, Firebase, Cloud Run, Vertex AI

### 1.2 Target Users

- Individuals seeking personalized skincare advice without expensive dermatologist visits
- Skincare enthusiasts wanting to optimize their routines and check ingredient compatibility
- People with specific skin concerns (acne, hyperpigmentation, sensitivity, aging) wanting targeted guidance
- Users in regions with limited access to dermatological professionals

---

## 2. System Architecture

The system follows a layered architecture built entirely on Google Cloud services and open-source Google frameworks. The architecture is designed for real-time streaming, horizontal scalability, and modular extensibility.

### 2.1 Architecture Overview

| Layer | Purpose | Google Services |
|---|---|---|
| Presentation Layer | User-facing interfaces (mobile, web) | Flutter, Angular, Firebase Hosting |
| Streaming Layer | Real-time bidirectional communication | Gemini Live API, WebSocket, WebRTC |
| Agent Orchestration Layer | Multi-agent coordination and routing | Google ADK (Agent Development Kit) |
| Intelligence Layer | LLM reasoning, RAG, and knowledge | Gemini 2.5 Flash, Vertex AI RAG Engine |
| Data & Storage Layer | User data, media, knowledge base | Firestore, Cloud Storage, Vertex AI Vector Search |
| Observability Layer | LLM tracing, evaluation, monitoring | Cloud Trace, Cloud Logging, OpenTelemetry |

### 2.2 High-Level Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                       │
│  ┌────────────────┐ ┌───────────────┐ ┌───────────────┐     │
│  │  Flutter App   │ │  Angular Web  │ │ Firebase Host │     │
│  │  (iOS/Android) │ │   (Desktop)   │ │   (Static)    │     │
│  └───────┬────────┘ └───────┬───────┘ └───────┬───────┘     │
└──────────┼──────────────────┼─────────────────┼─────────────┘
           │    WebSocket/WebRTC                 │
┌──────────┴──────────────────┴─────────────────┴─────────────┐
│              STREAMING LAYER (Cloud Run)                      │
│           FastAPI + ADK Bidi-Streaming Server                 │
│  ┌─────────────────────────────────────┐                     │
│  │  LiveRequestQueue (ADK)             │                     │
│  │  Session Management                 │                     │
│  │  Audio/Video Stream Handler         │                     │
│  └──────────────────┬──────────────────┘                     │
└─────────────────────┼────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│           AGENT ORCHESTRATION LAYER (Google ADK)             │
│  ┌────────────────────────────────────────────────┐          │
│  │           Root Orchestrator Agent               │          │
│  └──┬────────┬────────┬────────┬────────┬─────────┘          │
│     │        │        │        │        │                    │
│  ┌──┴───┐ ┌──┴───┐ ┌──┴────┐ ┌─┴──────┐ ┌┴─────┐           │
│  │ Skin │ │Rout- │ │Ingre- │ │Progress│ │ Q&A  │           │
│  │Analy-│ │ine   │ │dient  │ │Tracker │ │Agent │           │
│  │zer   │ │Build-│ │Checker│ │        │ │      │           │
│  └──────┘ │er    │ └───────┘ └────────┘ └──────┘           │
│           └──────┘                                          │
└──────────────────────────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│                 INTELLIGENCE LAYER                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Gemini 2.5   │  │ Vertex AI    │  │ Google       │        │
│  │ Flash (Live) │  │ RAG Engine   │  │ Search       │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└──────────────────────────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│                 DATA & STORAGE LAYER                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐      │
│  │Firestore │ │  Cloud   │ │ Vertex   │ │ Vertex     │      │
│  │ (Users)  │ │ Storage  │ │ AI Vec.  │ │ AI RAG     │      │
│  └──────────┘ └──────────┘ └──────────┘ └────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

### 2.3 Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Agent Framework | Google ADK (Python) | Multi-agent orchestration, tool management, streaming |
| LLM Engine | Gemini 2.5 Flash (Live API) | Real-time multimodal reasoning (audio + video + text) |
| Search & Grounding | Google Search Tool (ADK built-in) | Real-time product/ingredient information retrieval |
| Backend Runtime | Cloud Run | Serverless container hosting for FastAPI + ADK server |
| Production Deployment | Vertex AI Agent Engine | Enterprise-grade agent hosting, scaling, management |
| User Database | Cloud Firestore | User profiles, skin history, routine data |
| Media Storage | Cloud Storage | Skin photos, progress images, uploaded product labels |
| Knowledge Base | Vertex AI RAG Engine | Dermatological knowledge, ingredient database |
| Vector Search | Vertex AI Vector Search | Semantic search over skincare knowledge embeddings |
| Authentication | Firebase Authentication | User sign-up/login (Google, email, phone) |
| Mobile Frontend | Flutter | Cross-platform iOS/Android app with camera/mic access |
| Web Frontend | Angular | Desktop web application |
| Hosting | Firebase Hosting | Static web assets and CDN |
| Observability | Cloud Trace + Cloud Logging | OpenTelemetry-based LLM tracing and monitoring |
| LLM Evaluation | Vertex AI Evaluation / Phoenix | Agent performance evaluation and prompt optimization |
| CI/CD | Cloud Build | Automated testing, building, and deployment |
| Secrets | Secret Manager | API keys and credential management |

### 2.4 Data Flow

| Step | Action | Services Involved |
|---|---|---|
| 1 | User opens app, authenticates via Firebase Auth | Flutter/Angular, Firebase Auth |
| 2 | Client establishes WebSocket connection to backend | Client, Cloud Run (FastAPI) |
| 3 | ADK creates LiveRequestQueue and session | ADK Runner, Firestore Session Service |
| 4 | User streams audio/video to backend | WebSocket, ADK Bidi-Streaming |
| 5 | ADK routes to Root Orchestrator Agent | ADK Runner, Gemini Live API |
| 6 | Root Agent delegates to specialized sub-agent | ADK LLM-driven transfer |
| 7 | Sub-agent uses tools (search, DB lookup, RAG) | Google Search, Firestore, Vertex AI RAG |
| 8 | Agent generates response (text + audio) | Gemini 2.5 Flash |
| 9 | Response streamed back to client in real-time | WebSocket, ADK event stream |
| 10 | Session state persisted for continuity | Firestore Session Service |
| 11 | All interactions traced for observability | OpenTelemetry, Cloud Trace |

---

## 3. Multi-Agent Architecture

The skincare advisor uses a hierarchical multi-agent system built with Google ADK. A Root Orchestrator Agent receives all user interactions and dynamically routes them to the most appropriate specialized sub-agent using LLM-driven transfer. Each sub-agent is an independent, specialized unit with its own instruction set and tools.

### 3.1 Agent Hierarchy

```
                 ┌──────────────────────────┐
                 │  Root Orchestrator Agent  │
                 │   (skincare_advisor)      │
                 │  Model: gemini-2.5-flash  │
                 │  Mode: Bidi-Streaming     │
                 └──┬────┬────┬────┬────┬───┘
                    │    │    │    │    │
              ┌─────┘  ┌─┘  ┌┘   └┐   └──────┐
         ┌────┴───┐ ┌──┴──┐ ┌┴────┐ ┌──┴───┐ ┌─┴────┐
         │  Skin  │ │Rout-│ │Ingr-│ │Prog- │ │ Q&A  │
         │Analyzer│ │ine  │ │edi- │ │ress  │ │Agent │
         │ Agent  │ │Build│ │ent  │ │Track │ │      │
         └────────┘ │er   │ │Check│ │er    │ └──────┘
                    └─────┘ └─────┘ └──────┘
```

### 3.2 Root Orchestrator Agent

The Root Orchestrator is the primary entry point for all user interactions. It uses LLM-driven dynamic routing to determine which sub-agent should handle each request. It maintains conversation context and can handle general greetings or clarification questions directly.

**Responsibilities:**

- Receive and interpret all incoming user messages (text, audio, video)
- Route to the appropriate specialized sub-agent via ADK's LLM transfer mechanism
- Handle general conversation, greetings, and clarification questions
- Maintain overall session context and user profile state
- Enforce safety guardrails and disclaimer messaging

**Code Structure:**

```python
from google.adk.agents import Agent
from sub_agents.skin_analyzer import skin_analyzer_agent
from sub_agents.routine_builder import routine_builder_agent
from sub_agents.ingredient_checker import ingredient_checker_agent
from sub_agents.progress_tracker import progress_tracker_agent
from sub_agents.qa_agent import qa_agent

root_agent = Agent(
    name="skincare_advisor",
    model="gemini-2.5-flash-preview-native-audio",
    description="AI Skincare Advisor - Root Orchestrator",
    instruction="""You are a friendly, knowledgeable skincare
    advisor. Route user requests to the appropriate specialist:
    - Skin concerns/analysis -> skin_analyzer
    - Routine questions -> routine_builder
    - Product/ingredient questions -> ingredient_checker
    - Progress check -> progress_tracker
    - General skincare Q&A -> qa_agent
    IMPORTANT: You are NOT a dermatologist.""",
    sub_agents=[
        skin_analyzer_agent,
        routine_builder_agent,
        ingredient_checker_agent,
        progress_tracker_agent,
        qa_agent,
    ],
)
```

### 3.3 Specialized Sub-Agents

#### 3.3.1 Skin Analyzer Agent

Analyzes skin conditions from video/image input and user descriptions. This is the primary agent for real-time video consultation, leveraging Gemini's multimodal capabilities.

| Property | Details |
|---|---|
| Name | `skin_analyzer` |
| Model | `gemini-2.5-flash-preview-native-audio` |
| Input | Video stream, images, audio descriptions |
| Output | Skin condition observations, concern identification, severity assessment |
| Tools | `save_skin_analysis` (Firestore), `capture_snapshot` (Cloud Storage), `google_search` |

**Key Capabilities:**

- Analyze visible skin conditions from real-time video feed (texture, redness, dryness, acne, hyperpigmentation)
- Cross-reference visual observations with user's verbal description of concerns
- Provide immediate observations with appropriate confidence levels
- Save analysis results and snapshots to user's skin history
- Flag potentially serious conditions that warrant dermatologist consultation

```python
skin_analyzer_agent = Agent(
    name="skin_analyzer",
    model="gemini-2.5-flash-preview-native-audio",
    description="Analyzes skin from video/images and identifies concerns",
    instruction="""You are a skin analysis specialist. When the user
    shows their skin via camera:
    1. Observe visible conditions (texture, tone, spots, redness)
    2. Ask clarifying questions about skin type and history
    3. Provide observations (NOT diagnoses)
    4. Rate concern severity: mild / moderate / consult-dermatologist
    5. Save the analysis for progress tracking
    Always be encouraging and body-positive.""",
    tools=[save_skin_analysis, capture_snapshot, google_search],
)
```

#### 3.3.2 Routine Builder Agent

Creates personalized morning and evening skincare routines based on the user's skin type, concerns, budget, and environment.

| Property | Details |
|---|---|
| Name | `routine_builder` |
| Model | `gemini-2.5-flash` |
| Input | User skin profile, concerns, budget, climate |
| Output | Structured AM/PM routines with product suggestions and application order |
| Tools | `get_user_profile` (Firestore), `search_products` (RAG), `save_routine` (Firestore), `google_search` |

**Key Capabilities:**

- Generate step-by-step morning and evening routines
- Recommend products based on skin type, concerns, and budget range
- Explain the correct order of product application (e.g., thinnest to thickest)
- Adjust routines based on seasonal/climate changes
- Cross-check with ingredient_checker to avoid conflicts

```python
routine_builder_agent = Agent(
    name="routine_builder",
    model="gemini-2.5-flash",
    description="Builds personalized skincare routines",
    instruction="""You are a skincare routine specialist. Build
    routines following these principles:
    1. Always start with cleanser, end with SPF (AM)
    2. Layer products thin-to-thick consistency
    3. Separate actives that conflict (retinol + AHA/BHA)
    4. Consider the user's budget and availability
    5. Explain WHY each step matters""",
    tools=[get_user_profile, search_products, save_routine, google_search],
)
```

#### 3.3.3 Ingredient Checker Agent

Analyzes product ingredients for safety, efficacy, and compatibility. Can process product label images or text-based ingredient lists.

| Property | Details |
|---|---|
| Name | `ingredient_checker` |
| Model | `gemini-2.5-flash` |
| Input | Product label images, ingredient list text, current routine |
| Output | Ingredient analysis, compatibility report, conflict warnings |
| Tools | `lookup_ingredient` (RAG), `check_compatibility` (custom), `get_user_routine` (Firestore), `google_search` |

**Key Capabilities:**

- Parse ingredient lists from product label images using Gemini vision
- Identify key active ingredients and their functions
- Detect ingredient conflicts (e.g., retinol + vitamin C, niacinamide + AHA)
- Flag potential allergens based on user's profile
- Rate product suitability for the user's specific skin type and concerns

#### 3.3.4 Progress Tracker Agent

Tracks skin condition changes over time by comparing periodic photos and analysis results. Provides insights on what's working and what needs adjustment.

| Property | Details |
|---|---|
| Name | `progress_tracker` |
| Model | `gemini-2.5-flash` |
| Input | Current skin photo/video, historical analysis data |
| Output | Progress reports, trend analysis, routine adjustment suggestions |
| Tools | `get_skin_history` (Firestore), `compare_snapshots` (custom), `save_progress_note` (Firestore) |

**Key Capabilities:**

- Compare current skin condition against historical baselines
- Generate visual progress timelines from stored snapshots
- Identify trends: improving, stable, or worsening conditions
- Correlate routine changes with skin condition changes
- Suggest routine adjustments based on observed progress

#### 3.3.5 General Q&A Agent

Handles general skincare education questions, myth-busting, and knowledge sharing. Uses RAG to ground answers in verified dermatological sources.

| Property | Details |
|---|---|
| Name | `qa_agent` |
| Model | `gemini-2.5-flash` |
| Input | Text or voice questions about skincare topics |
| Output | Evidence-based answers with source references |
| Tools | `skincare_knowledge_search` (Vertex AI RAG), `google_search` |

**Key Capabilities:**

- Answer common skincare questions with evidence-based information
- Debunk skincare myths and misconceptions
- Explain how specific ingredients work on the skin
- Provide general dermatological education (not diagnoses)
- Reference trusted sources (dermatological studies, expert guidelines)

### 3.4 Agent Communication & State Management

Agents communicate through ADK's shared session state stored in Firestore. Each agent can read and write to session state keys relevant to its function:

| State Key | Type | Description | Written By |
|---|---|---|---|
| `user_profile` | Object | Skin type, concerns, allergies, preferences | Root Orchestrator |
| `current_routine` | Object | Active AM/PM skincare routine | Routine Builder |
| `latest_analysis` | Object | Most recent skin analysis results | Skin Analyzer |
| `skin_history` | Array | Historical analysis snapshots with timestamps | Progress Tracker |
| `ingredient_alerts` | Array | Active ingredient conflict warnings | Ingredient Checker |
| `conversation_context` | Object | Summary of current consultation goals | Root Orchestrator |

### 3.5 Agent Routing Logic

The Root Orchestrator uses LLM-driven dynamic routing. Based on the user's input, Gemini decides which sub-agent to transfer to:

| User Input Example | Routed To | Reasoning |
|---|---|---|
| "Look at my skin, what do you see?" | Skin Analyzer | Video/image analysis request |
| "Build me a morning routine for oily skin" | Routine Builder | Routine creation request |
| "Is this moisturizer safe to use with retinol?" | Ingredient Checker | Product compatibility query |
| "How has my skin changed since last month?" | Progress Tracker | Progress comparison request |
| "What does hyaluronic acid do?" | Q&A Agent | General skincare knowledge question |
| "Hi, I need help with my acne" | Root (then Skin Analyzer) | General greeting, then specific concern |

---

## 4. Tools & Integrations

Each agent has access to specific tools that enable it to interact with external services and databases. Tools in ADK are Python functions decorated with metadata that the LLM uses to decide when and how to call them.

### 4.1 Custom Tools

| Tool Name | Used By | Function | Backend Service |
|---|---|---|---|
| `save_skin_analysis` | Skin Analyzer | Persists skin analysis results to user profile | Cloud Firestore |
| `capture_snapshot` | Skin Analyzer | Saves a skin photo with metadata for tracking | Cloud Storage + Firestore |
| `get_user_profile` | Routine Builder, Root | Retrieves user skin type, concerns, allergies | Cloud Firestore |
| `search_products` | Routine Builder | Searches product knowledge base by criteria | Vertex AI RAG Engine |
| `save_routine` | Routine Builder | Saves a generated routine to user profile | Cloud Firestore |
| `lookup_ingredient` | Ingredient Checker | Looks up ingredient details and safety data | Vertex AI RAG Engine |
| `check_compatibility` | Ingredient Checker | Checks if ingredients can be used together | Custom logic + RAG |
| `get_user_routine` | Ingredient Checker | Retrieves current routine for conflict checking | Cloud Firestore |
| `get_skin_history` | Progress Tracker | Retrieves historical skin analyses and photos | Cloud Firestore |
| `compare_snapshots` | Progress Tracker | Compares two skin snapshots for changes | Gemini Vision + custom |
| `save_progress_note` | Progress Tracker | Records a progress observation with date | Cloud Firestore |
| `skincare_knowledge_search` | Q&A Agent | RAG search over dermatological knowledge base | Vertex AI RAG Engine |

### 4.2 Built-in ADK Tools

- **Google Search Tool** — Real-time web search for product information, latest skincare research, and ingredient data
- **Code Execution Tool** — Available for data analysis tasks (e.g., computing ingredient concentration percentages)

### 4.3 Example Tool Implementation

```python
from google.cloud import firestore

db = firestore.AsyncClient()

async def save_skin_analysis(
    user_id: str,
    concerns: list[str],
    severity: str,
    observations: str,
    recommendations: list[str]
) -> dict:
    """Saves a skin analysis result to the user's profile.

    Args:
        user_id: The authenticated user's ID.
        concerns: List of identified skin concerns.
        severity: Overall severity (mild/moderate/severe).
        observations: Detailed text observations.
        recommendations: List of recommended actions.

    Returns:
        dict: Confirmation with analysis ID.
    """
    from datetime import datetime

    analysis = {
        "concerns": concerns,
        "severity": severity,
        "observations": observations,
        "recommendations": recommendations,
        "timestamp": datetime.utcnow(),
    }

    ref = db.collection("users").document(user_id)
    ref_analysis = ref.collection("skin_analyses")
    doc_ref = await ref_analysis.add(analysis)

    return {"status": "saved", "analysis_id": doc_ref.id}
```

---

## 5. Knowledge Base & RAG Architecture

The skincare advisor's accuracy depends on a well-curated knowledge base accessed through Retrieval-Augmented Generation (RAG). This ensures all recommendations are grounded in verified dermatological information rather than relying solely on the LLM's training data.

### 5.1 Knowledge Base Structure

| Collection | Content | Source | Update Frequency |
|---|---|---|---|
| Ingredients | 3,000+ skincare ingredients with safety/efficacy data | CIR, EWG, PubChem databases | Monthly |
| Ingredient Interactions | Known conflicts and synergies between active ingredients | Dermatological literature | Monthly |
| Skin Conditions | Common conditions: symptoms, triggers, care guidelines | AAD, BAD clinical guides | Quarterly |
| Product Database | Popular products with full ingredient lists and reviews | Web scraping + manual curation | Weekly |
| Routine Templates | Evidence-based routine templates by skin type and concern | Dermatologist consultations | Quarterly |
| Skincare Education | Myths, FAQs, educational content for consumer understanding | Peer-reviewed articles | Monthly |

### 5.2 RAG Pipeline

The RAG pipeline uses Vertex AI RAG Engine for document ingestion and retrieval, with Vertex AI Vector Search for semantic similarity:

```
Knowledge Documents (PDFs, structured data)
        │
        ▼
Vertex AI RAG Engine (Ingestion)
  - Chunking (512 tokens, 100 overlap)
  - Embedding (text-embedding-005)
        │
        ▼
Vertex AI Vector Search (Index)
  - Approximate Nearest Neighbor (ANN)
  - Cosine similarity
        │
        ▼
Agent Tool Call (query)
  - Top-k retrieval (k=5)
  - Context injection into agent prompt
  - Gemini generates grounded response
```

---

## 6. LLM Observability & Evaluation

Observability is critical for an AI skincare advisor where recommendation quality directly impacts user trust and safety. The system uses OpenTelemetry-based tracing integrated with Google Cloud Observability.

### 6.1 Observability Stack

| Component | Google Service | Purpose |
|---|---|---|
| Trace Collection | Cloud Trace (via OTel) | Capture every agent run, tool call, and LLM interaction |
| Logging | Cloud Logging | Structured logs for agent decisions, errors, and warnings |
| Metrics | Cloud Monitoring | Token usage, latency, error rates, throughput dashboards |
| LLM Evaluation | Vertex AI Evaluation | Automated quality assessment of agent responses |
| Advanced Analysis | Phoenix (self-hosted on Cloud Run) | Prompt optimization, trace replay, evaluation experiments |

### 6.2 What Gets Traced

ADK's built-in OpenTelemetry integration automatically captures the following spans for every interaction:

- **Agent Execution Spans** — start/end of each agent's processing, including which agent handled the request
- **LLM Call Spans** — every call to Gemini, including prompt, completion, token counts, and latency
- **Tool Invocation Spans** — each tool call with input parameters, output, duration, and success/failure
- **Agent Transfer Spans** — when the Root Orchestrator routes to a sub-agent, capturing the routing decision
- **Session Events** — session creation, state updates, and session resumption after WebSocket reconnects

### 6.3 Key Metrics & Dashboards

| Metric | Description | Alert Threshold |
|---|---|---|
| Agent Response Latency (p95) | Time from user input to first agent response token | > 3 seconds |
| Tool Call Success Rate | Percentage of tool calls that return without error | < 95% |
| Token Usage per Session | Average tokens consumed per consultation session | > 50,000 tokens |
| Agent Routing Accuracy | Percentage of correct sub-agent selections (via eval) | < 90% |
| Recommendation Safety Score | LLM-as-judge evaluation of safety compliance | < 0.95 |
| Hallucination Rate | Percentage of responses containing ungrounded claims | > 5% |
| Session Completion Rate | Percentage of sessions where user received a complete recommendation | < 80% |

### 6.4 Enabling Observability

ADK natively supports exporting telemetry to Google Cloud with a single CLI flag:

```bash
# Development: local traces
adk web

# Production: export to Google Cloud Observability
adk web --otel_to_cloud

# Required environment variables
export GOOGLE_CLOUD_PROJECT="skincare-advisor-prod"
export GOOGLE_CLOUD_LOCATION="us-central1"
```

---

## 7. Project Structure

```
skincare-advisor/
├── app/
│   ├── .env                          # API keys & config
│   └── skincare_advisor/
│       ├── __init__.py               # Package init (imports root_agent)
│       ├── agent.py                  # Root Orchestrator Agent
│       ├── sub_agents/
│       │   ├── __init__.py
│       │   ├── skin_analyzer.py      # Skin Analyzer Agent
│       │   ├── routine_builder.py    # Routine Builder Agent
│       │   ├── ingredient_checker.py # Ingredient Checker Agent
│       │   ├── progress_tracker.py   # Progress Tracker Agent
│       │   └── qa_agent.py           # General Q&A Agent
│       ├── tools/
│       │   ├── __init__.py
│       │   ├── skin_tools.py         # save_skin_analysis, capture_snapshot
│       │   ├── routine_tools.py      # search_products, save_routine
│       │   ├── ingredient_tools.py   # lookup_ingredient, check_compatibility
│       │   ├── progress_tools.py     # get_skin_history, compare_snapshots
│       │   ├── user_tools.py         # get_user_profile, update_profile
│       │   └── knowledge_tools.py    # skincare_knowledge_search (RAG)
│       └── prompts/
│           ├── root_orchestrator.txt  # System prompt for Root Agent
│           ├── skin_analyzer.txt      # System prompt for Skin Analyzer
│           ├── routine_builder.txt    # System prompt for Routine Builder
│           ├── ingredient_checker.txt # System prompt for Ingredient Checker
│           ├── progress_tracker.txt   # System prompt for Progress Tracker
│           └── qa_agent.txt           # System prompt for Q&A Agent
├── server/
│   ├── main.py                       # FastAPI + WebSocket server
│   ├── streaming_service.py          # ADK Bidi-streaming integration
│   └── auth.py                       # Firebase Auth middleware
├── knowledge/
│   ├── ingredients/                  # Ingredient data (CSV/JSON)
│   ├── conditions/                   # Skin condition guides
│   ├── routines/                     # Routine templates
│   └── ingest.py                     # Script to ingest into Vertex AI RAG
├── frontend/
│   ├── flutter_app/                  # Flutter mobile app source
│   └── angular_web/                  # Angular web app source
├── infra/
│   ├── Dockerfile                    # Container for Cloud Run
│   ├── cloudbuild.yaml               # Cloud Build CI/CD pipeline
│   ├── terraform/                    # Infrastructure as Code
│   └── firebase.json                 # Firebase configuration
├── evals/
│   ├── test_routing.py               # Agent routing accuracy tests
│   ├── test_safety.py                # Safety guardrail tests
│   └── test_quality.py               # Response quality evaluation
├── requirements.txt
├── opentelemetry.env                 # OTel config for Cloud Trace
└── README.md
```

---

## 8. Deployment Architecture

### 8.1 Environments

| Environment | Platform | ADK Config | Observability |
|---|---|---|---|
| Local Dev | adk web (localhost:8000) | `GOOGLE_GENAI_USE_VERTEXAI=FALSE` | Console logging |
| Staging | Cloud Run (staging) | `GOOGLE_GENAI_USE_VERTEXAI=TRUE` | Cloud Trace (staging project) |
| Production | Vertex AI Agent Engine / Cloud Run | `GOOGLE_GENAI_USE_VERTEXAI=TRUE` | Cloud Trace + alerts |

### 8.2 Cloud Run Deployment

```dockerfile
# Dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["uvicorn", "server.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

```bash
# Deploy to Cloud Run
gcloud run deploy skincare-advisor \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_GENAI_USE_VERTEXAI=TRUE \
  --min-instances 1 \
  --max-instances 10 \
  --memory 2Gi
```

### 8.3 CI/CD Pipeline

Cloud Build automates testing, building, and deployment:

- Push to main branch triggers Cloud Build pipeline
- Run unit tests and agent evaluation tests (`evals/`)
- Build Docker container and push to Artifact Registry
- Deploy to Cloud Run staging, run integration tests
- Manual approval gate for production deployment
- Deploy to production Cloud Run / Vertex AI Agent Engine

---

## 9. Security & Privacy

> **CRITICAL:** Skin photos and health-related data are sensitive personal information. The system must meet the highest standards of data privacy and security.

### 9.1 Data Protection

- All skin photos encrypted at rest (AES-256) in Cloud Storage
- Data in transit encrypted with TLS 1.3 across all connections
- User data isolated with Firestore security rules — users can only access their own data
- Full data deletion: users can delete all their data at any time, including photos and analysis history
- No third-party data sharing — user data never leaves Google Cloud infrastructure

### 9.2 Authentication & Authorization

- Firebase Authentication for user identity (Google Sign-In, email/password, phone)
- JWT token validation on every API request
- Service-to-service authentication via Google Cloud IAM
- API keys stored in Secret Manager, never in code or environment files

### 9.3 AI Safety Guardrails

- System prompts include explicit disclaimers: "Not a medical professional, not a diagnosis"
- Severity thresholds: conditions flagged as severe automatically recommend dermatologist consultation
- Content filtering: Gemini's built-in safety filters active for all interactions
- Body-positive language enforced via system prompts — no negative commentary on appearance
- No storage of raw video streams — only user-approved snapshots are saved
- Regular evaluation runs to detect and fix hallucination or unsafe recommendations

---

## 10. Development Roadmap

| Phase | Timeline | Deliverables | Status |
|---|---|---|---|
| Phase 1: Foundation | Weeks 1–4 | ADK setup, Root Agent, Skin Analyzer with Gemini Live API, basic Flutter app | Planned |
| Phase 2: Multi-Agent | Weeks 5–8 | Routine Builder, Ingredient Checker, Q&A Agent, Firestore integration | Planned |
| Phase 3: Knowledge | Weeks 9–11 | RAG pipeline, ingredient database, Vertex AI Vector Search, knowledge ingestion | Planned |
| Phase 4: Progress | Weeks 12–14 | Progress Tracker, photo comparison, historical analysis, dashboards | Planned |
| Phase 5: Observability | Weeks 15–16 | Cloud Trace integration, evaluation pipeline, safety testing, monitoring alerts | Planned |
| Phase 6: Production | Weeks 17–20 | Cloud Run deployment, CI/CD, security hardening, beta testing | Planned |
| Phase 7: Launch | Weeks 21–24 | Public launch, app store submission, user onboarding, feedback loop | Planned |

---

*AI Skincare Advisor — Powered by Google ADK & Gemini*
