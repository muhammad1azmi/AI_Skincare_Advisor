# Glow — AI Skincare Advisor — Project Document

> **Powered by Google ADK & Gemini Live API**
> Real-time multimodal skincare analysis and personalized recommendations using voice, video, and text interaction.
>
> Version 2.0 | March 2026
> Google Cloud · Google ADK · Gemini · Firebase · Model Armor

---

## 1. Executive Summary

**Glow** is an intelligent, real-time skincare consultation platform that leverages Google's Agent Development Kit (ADK) and Gemini Live API to deliver personalized skincare guidance through natural voice, video, and text interactions.

Users can point their camera at their skin, speak about their concerns, and receive immediate, contextual advice from a multi-agent AI system featuring 8 specialist agents and 3 workflow agents. The platform analyzes visible skin conditions, recommends tailored routines, checks ingredient safety and interactions, finds relevant KOL content, and tracks progress over time — all within a fully Google-native technology stack.

> **Mission:** Democratize access to personalized skincare advice through AI, making expert-level guidance available to anyone with a smartphone — while always encouraging professional dermatological consultation for serious concerns.

### 1.1 Key Objectives

- Provide real-time, multimodal skincare analysis via voice and video using Gemini Live API with native audio
- Build a multi-agent system with 8 specialist agents and 3 workflow agents (parallel, sequential, loop patterns) via ADK
- Deliver personalized, evidence-based skincare recommendations grounded in Vertex AI Search datastores
- Ensure user safety with defense-in-depth: Google Cloud Model Armor, ADK callbacks, and Gemini safety filters
- Enable cross-session memory with Vertex AI Memory Bank for personalized continuity
- Track all agent interactions via BigQuery Agent Analytics Plugin for observability
- Deploy on a fully Google-native stack: ADK, Gemini, Firebase, Cloud Run, Vertex AI Agent Engine

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
| Presentation Layer | User-facing mobile interface | Flutter (iOS/Android) |
| Streaming Layer | Real-time bidirectional communication | Gemini Live API, WebSocket |
| Agent Orchestration Layer | Multi-agent coordination, routing, and workflows | Google ADK (`AgentTool`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`) |
| Intelligence Layer | LLM reasoning, knowledge retrieval, thinking | Gemini Live 2.5 Flash (native audio), Gemini 2.5 Flash, Vertex AI Search |
| Security Layer | Input/output sanitization, safety guardrails | Google Cloud Model Armor, ADK callbacks, Gemini safety filters |
| Data & Storage Layer | User data, media, knowledge datastores | Firestore, Cloud Storage, Vertex AI Search datastores |
| Observability Layer | Agent analytics, tracing, structured logging | BigQuery Agent Analytics Plugin, OpenTelemetry |
| Engagement Layer | Push notifications, routine reminders, product deals | Firebase Cloud Messaging (FCM) |

### 2.2 High-Level Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                       │
│  ┌────────────────────────────────────────────────────┐      │
│  │  Flutter App "Glow"  (iOS/Android)                 │      │
│  │  Camera · Microphone · Push Notifications          │      │
│  └───────────────────────┬────────────────────────────┘      │
└──────────────────────────┼───────────────────────────────────┘
                           │    WebSocket (audio/video/text)
┌──────────────────────────┴───────────────────────────────────┐
│              STREAMING LAYER (Cloud Run)                      │
│           FastAPI + ADK Bidi-Streaming Server                 │
│  ┌─────────────────────────────────────┐                     │
│  │  LiveRequestQueue (ADK)             │                     │
│  │  Firebase Auth (JWT verification)   │                     │
│  │  Rate Limiting + Session Mgmt       │                     │
│  │  Binary audio / JSON text framing   │                     │
│  └──────────────────┬──────────────────┘                     │
└─────────────────────┼────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│           AGENT ORCHESTRATION LAYER (Google ADK)             │
│  ┌────────────────────────────────────────────────┐          │
│  │     Root Orchestrator Agent (skincare_advisor)  │          │
│  │     Model: gemini-live-2.5-flash-native-audio   │          │
│  │     BuiltInPlanner (thinking_budget=1024)       │          │
│  │     PreloadMemoryTool + AgentTool wrappers      │          │
│  └──┬────┬────┬────┬────┬────┬────┬────┬─────────┘          │
│     │    │    │    │    │    │    │    │                      │
│  ┌──┴──┐┌┴──┐┌┴──┐┌┴──┐┌┴──┐┌┴──┐┌┴──┐┌┴─────┐             │
│  │Skin ││Rou││Ing││Ing││Ski││Q&A││KOL││Prog- │             │
│  │Anal-││tin││red││red││n  ││   ││Con││ress  │             │
│  │yzer ││e  ││ie-││ie-││Con││   ││ten││Track │             │
│  │     ││Bui││nt ││nt ││dit││   ││t  ││er    │             │
│  │     ││ld ││Chk││Int││ion││   ││   ││      │             │
│  └─────┘│er │└───┘│er │└───┘└───┘└───┘└──────┘             │
│          └───┘     └───┘                                     │
│  ┌──── Workflow Agents (composite patterns) ─────────────┐  │
│  │  ParallelAgent: Parallel Ingredient Check             │  │
│  │  SequentialAgent: Full Consultation Pipeline           │  │
│  │  SequentialAgent+LoopAgent: Routine Review Loop        │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│                 SECURITY LAYER                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Model Armor  │  │ ADK Callback │  │ Gemini Built │        │
│  │ (PI, PII,    │  │ before/after │  │ -in Safety   │        │
│  │  RAI, URIs)  │  │ + medical    │  │ Filters      │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└──────────────────────────────────────────────────────────────┘
                      │
┌─────────────────────┴────────────────────────────────────────┐
│                 DATA & OBSERVABILITY LAYER                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐      │
│  │Firestore │ │ Cloud    │ │ Vertex   │ │ BigQuery   │      │
│  │(Sessions)│ │ Storage  │ │ AI Search│ │ Analytics  │      │
│  └──────────┘ └──────────┘ │(5 stores)│ │  Plugin    │      │
│                             └──────────┘ └────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

### 2.3 Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Agent Framework | Google ADK v1.23.0 (Python) | Multi-agent orchestration, AgentTool, workflow agents, streaming |
| Root LLM | Gemini Live 2.5 Flash (native audio) | Real-time multimodal reasoning with native audio input/output |
| Sub-Agent LLM | Gemini 2.5 Flash | Text-based specialist reasoning for sub-agents |
| Knowledge Retrieval | Vertex AI Search Tool (5 datastores) | Grounded retrieval: ingredients, interactions, conditions, routines, KOL content |
| Agent Planning | BuiltInPlanner (ThinkingConfig) | Native Gemini thinking for tool selection and reasoning |
| Cross-Session Memory | Vertex AI Memory Bank + PreloadMemoryTool | Persistent user preferences, skin type, concerns across sessions |
| Security | Google Cloud Model Armor | ML-powered prompt/response sanitization (PI, PII, RAI, malicious URIs) |
| Backend Runtime | Cloud Run | Serverless container hosting for FastAPI + ADK server |
| Production Deployment | Vertex AI Agent Engine | Enterprise-grade agent hosting, scaling, session/memory management |
| Observability | BigQuery Agent Analytics Plugin | Agent event logging, tool calls, LLM interactions, multimodal content |
| Distributed Tracing | OpenTelemetry SDK | Trace IDs correlation across agent/tool spans |
| User Database | Cloud Firestore | User sessions, skin history, routine data |
| Authentication | Firebase Authentication | User sign-up/login (Google Sign-In, email/password) |
| Push Notifications | Firebase Cloud Messaging (FCM) | Routine reminders, follow-up nudges, product deal notifications |
| Mobile Frontend | Flutter | Cross-platform iOS/Android app with camera, mic, push notification support |
| Container | Python 3.13-slim, Docker | Production container with non-root user |
| CI/CD | Cloud Build + deploy scripts | Automated build and deployment |
| Secrets | Secret Manager | API keys and credential management |

### 2.4 Data Flow

| Step | Action | Services Involved |
|---|---|---|
| 1 | User opens Glow app, authenticates via Firebase Auth | Flutter, Firebase Auth |
| 2 | Client establishes WebSocket connection to backend (`/ws/{user_id}/{session_id}`) | Flutter, Cloud Run (FastAPI) |
| 3 | Server verifies Firebase JWT, creates InMemory live session | FastAPI, Firebase Auth, ADK |
| 4 | LiveRequestQueue created, RunConfig set (AUDIO modality, BIDI streaming, Aoede voice) | ADK Runner |
| 5 | User streams audio/video/text to backend via WebSocket | WebSocket, LiveRequestQueue |
| 6 | Root Orchestrator Agent receives input, BuiltInPlanner reasons about routing | ADK, Gemini Live API |
| 7 | Root Agent calls specialist AgentTool (executed via `run_async` in isolated context) | AgentTool, Gemini 2.5 Flash |
| 8 | Sub-agent uses Vertex AI Search Tool to retrieve grounded knowledge | Vertex AI Search datastores |
| 9 | Tool results streamed back to client (toolEvent call/result JSON frames) | WebSocket |
| 10 | Audio response streamed as binary WebSocket frames, transcription as JSON | WebSocket |
| 11 | After-agent callback sends events to Memory Bank for extraction | Vertex AI Memory Bank |
| 12 | All interactions logged via BigQuery Agent Analytics Plugin | BigQuery |

---

## 3. Multi-Agent Architecture

The skincare advisor uses a hierarchical multi-agent system built with Google ADK. A Root Orchestrator Agent receives all user interactions and uses `AgentTool` wrappers to delegate to specialized sub-agents. Sub-agents execute via `run_async()` in isolated contexts — this avoids the Vertex AI mixed-tool-type limitation with the live audio model.

### 3.1 Agent Hierarchy

```
                     ┌──────────────────────────────┐
                     │   Root Orchestrator Agent     │
                     │   (skincare_advisor)          │
                     │   Model: gemini-live-2.5-     │
                     │     flash-native-audio        │
                     │   BuiltInPlanner + Callbacks  │
                     └──┬──┬──┬──┬──┬──┬──┬──┬──────┘
                        │  │  │  │  │  │  │  │
       ┌────────────────┘  │  │  │  │  │  │  └────────┐
  ┌────┴────┐ ┌────┴───┐ ┌┴──┐ ┌┴──┐ ┌┴──┐ ┌┴──┐ ┌───┴──┐ ┌──┴───┐
  │  Skin   │ │Routine │ │Ing│ │Ing│ │Ski│ │Q&A│ │ KOL  │ │Prog- │
  │Analyzer │ │Builder │ │red│ │red│ │n  │ │   │ │Conte-│ │ress  │
  │         │ │        │ │Chk│ │Int│ │Con│ │   │ │nt    │ │Track │
  └─────────┘ └────────┘ └───┘ └───┘ └───┘ └───┘ └──────┘ └──────┘

  ┌─── Workflow (Composite) Agents ────────────────────────────────┐
  │                                                                │
  │  🔀 Parallel Ingredient Agent                                 │
  │     ParallelAgent[IngChecker ‖ IngInteraction]                │
  │     → SequentialAgent → IngredientSynthesis                   │
  │                                                                │
  │  📋 Consultation Pipeline Agent                               │
  │     SequentialAgent[SkinAnalyzer → SkinCondition →            │
  │       RoutineBuilder → ConsultationSynthesis → KOLContent]    │
  │                                                                │
  │  🔄 Routine Review Agent                                      │
  │     SequentialAgent[RoutineBuilder →                           │
  │       LoopAgent(max=3)[RoutineCritic → RoutineRefiner]]       │
  └────────────────────────────────────────────────────────────────┘
```

### 3.2 Root Orchestrator Agent

The Root Orchestrator is the primary entry point for all user interactions. It uses the `gemini-live-2.5-flash-native-audio` model for real-time voice conversations and delegates to specialist agents via `AgentTool` wrappers.

**Key Design Decision — AgentTool vs sub_agents:**

Sub-agents are wrapped as `AgentTool` instances (NOT `sub_agents` / `transfer_to_agent`). This is necessary because:
- `AgentTool.run_async()` creates a NEW Runner + InMemorySessionService
- It calls `runner.run_async()` (standard async mode), NOT `run_live()`
- Sub-agents execute in a completely independent context
- `VertexAiSearchTool` works fine because it's not in a live session
- The text result is returned to the live model like any function response

**Responsibilities:**

- Receive and interpret all incoming user messages (text, audio, video)
- Use BuiltInPlanner (ThinkingConfig, budget=1024) to reason about tool selection
- Route to the appropriate specialist agent via AgentTool
- PreloadMemoryTool retrieves user memories at the start of every turn
- Handle general conversation, greetings, and clarification questions directly
- Enforce safety via before_model_callback (Model Armor + medical checks) and after_model_callback
- Persist memories via after_agent_callback (Memory Bank integration)

**Code Structure:**

```python
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from google.adk.planners import BuiltInPlanner
from google.genai import types

root_agent = Agent(
    name="skincare_advisor",
    model="gemini-live-2.5-flash-native-audio",
    description="AI Skincare Advisor — Root Orchestrator",
    instruction=_ROOT_INSTRUCTION,  # Loaded from prompts/root_orchestrator.txt
    planner=BuiltInPlanner(
        thinking_config=types.ThinkingConfig(thinking_budget=1024)
    ),
    generate_content_config=types.GenerateContentConfig(
        safety_settings=[...],  # BLOCK_MEDIUM_AND_ABOVE for all categories
    ),
    tools=[
        PreloadMemoryTool(),
        AgentTool(agent=skin_analyzer_agent),
        AgentTool(agent=routine_builder_agent),
        AgentTool(agent=ingredient_checker_agent),
        AgentTool(agent=ingredient_interaction_agent),
        AgentTool(agent=skin_condition_agent),
        AgentTool(agent=qa_agent),
        AgentTool(agent=kol_content_agent),
        AgentTool(agent=progress_tracker_agent),
        # Composite workflow agents
        AgentTool(agent=parallel_ingredient_agent),
        AgentTool(agent=consultation_pipeline_agent),
        AgentTool(agent=routine_review_agent),
    ],
    before_model_callback=_safety_guardrail,
    after_model_callback=_output_safety_check,
    after_agent_callback=generate_memories_callback,
)
```

### 3.3 Specialist Sub-Agents

#### 3.3.1 Skin Analyzer Agent

Analyzes skin conditions from video/image input and user descriptions. Uses Gemini Vision capabilities.

| Property | Details |
|---|---|
| Name | `skin_analyzer` |
| Model | `gemini-2.5-flash` |
| Input | Video frames, images, text descriptions |
| Output | Skin condition observations, concern identification, severity assessment |
| Tools | `save_analysis_to_state` (persists to session state) |
| Output Key | `skin_analysis_result` |

#### 3.3.2 Routine Builder Agent

Creates personalized morning and evening skincare routines grounded in routine template data.

| Property | Details |
|---|---|
| Name | `routine_builder` |
| Model | `gemini-2.5-flash` |
| Input | User skin concerns, preferences, environment |
| Output | Structured AM/PM routines with product suggestions and application order |
| Tools | `VertexAiSearchTool` (routine-templates datastore) |
| Output Key | `current_routine` |

#### 3.3.3 Ingredient Checker Agent

Analyzes product ingredients for safety, efficacy, and suitability using grounded ingredient data.

| Property | Details |
|---|---|
| Name | `ingredient_checker` |
| Model | `gemini-2.5-flash` |
| Input | Product names, ingredient lists |
| Output | Ingredient safety analysis, suitability assessment |
| Tools | `VertexAiSearchTool` (skincare-ingredients datastore) |

#### 3.3.4 Ingredient Interaction Agent

Checks ingredient compatibility and identifies potential conflicts between active ingredients.

| Property | Details |
|---|---|
| Name | `ingredient_interaction` |
| Model | `gemini-2.5-flash` |
| Input | Multiple ingredients or products to check |
| Output | Compatibility report, conflict warnings, safe combinations |
| Tools | `VertexAiSearchTool` (ingredient-interactions BigQuery datastore) |

#### 3.3.5 Skin Condition Agent

Provides information about skin conditions, symptoms, triggers, and recommended care approaches.

| Property | Details |
|---|---|
| Name | `skin_condition` |
| Model | `gemini-2.5-flash` |
| Input | Condition names, symptoms described by user |
| Output | Condition information, triggers, care guidelines |
| Tools | `VertexAiSearchTool` (skin-conditions datastore) |

#### 3.3.6 General Q&A Agent

Handles general skincare education questions, grounded in dermatological knowledge.

| Property | Details |
|---|---|
| Name | `qa_agent` |
| Model | `gemini-2.5-flash` |
| Input | Text or voice questions about skincare topics |
| Output | Evidence-based answers with grounded references |
| Tools | `VertexAiSearchTool` (skincare-ingredients datastore) |

#### 3.3.7 KOL Content Agent

Finds relevant Key Opinion Leader (KOL) and influencer skincare video content matching user concerns.

| Property | Details |
|---|---|
| Name | `kol_content_agent` |
| Model | `gemini-2.5-flash` |
| Input | User's skin concerns and topics of interest |
| Output | Relevant KOL video URLs and content recommendations |
| Tools | `VertexAiSearchTool` (kol-content Google Sheets datastore) |

#### 3.3.8 Progress Tracker Agent

Tracks skin condition changes over time by recording and comparing observations.

| Property | Details |
|---|---|
| Name | `progress_tracker` |
| Model | `gemini-2.5-flash` |
| Input | Current skin observations, historical data |
| Output | Progress reports, trend analysis |
| Tools | `save_progress_note`, `get_progress_notes` (session state) |

### 3.4 Workflow (Composite) Agents

ADK enables powerful composite agent patterns. The system uses three workflow agents that combine specialist agents into coordinated pipelines:

#### 3.4.1 Parallel Ingredient Check Agent

Runs ingredient safety and interaction checks **concurrently**, then synthesizes results.

```
SequentialAgent [
    ParallelAgent [
        ingredient_checker ‖ ingredient_interaction
    ],
    IngredientSynthesisAgent (merges results from state)
]
```

**Use when:** The user asks about an ingredient's safety AND its compatibility simultaneously.

#### 3.4.2 Full Consultation Pipeline Agent

Chains specialist agents in a fixed order where each step builds on the previous one's output via session state.

```
SequentialAgent [
    skin_analyzer       → state: skin_analysis_result
    skin_condition      → state: skin_condition_result
    routine_builder     → state: current_routine
    consultation_synth  → state: consultation_summary
    kol_content_agent   → finds relevant videos
]
```

**Use when:** The user requests a comprehensive consultation or says "analyze everything."

#### 3.4.3 Routine Review Loop Agent

Iteratively reviews and refines skincare routines before they reach the user using a critic/refiner loop.

```
SequentialAgent [
    routine_builder (→ state: current_routine),
    LoopAgent (max 3 iterations) [
        RoutineCriticAgent  (→ state: routine_criticism)
        RoutineRefinerAgent (updates routine or calls exit_loop)
    ]
]
```

**Use when:** Safety is important (sensitive skin, acne-prone skin, complex multi-step routines).

### 3.5 Agent Factory Pattern

To satisfy ADK's single-parent rule (each agent instance can only belong to one workflow parent), the system uses **factory functions** in `agent_factories.py` to create fresh instances with the same configuration but unique names:

```python
def create_ingredient_checker(name="ingredient_checker", **overrides) -> Agent:
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        instruction=_load_prompt("ingredient_checker.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["ingredients"], ...)],
        **overrides,
    )
```

### 3.6 Agent Routing Logic

The Root Orchestrator uses the BuiltInPlanner's thinking capability to decide which AgentTool to invoke:

| User Input Example | Routed To | Reasoning |
|---|---|---|
| "Look at my skin, what do you see?" | Skin Analyzer | Video/image analysis request |
| "Build me a morning routine for oily skin" | Routine Builder | Routine creation request |
| "Is this moisturizer safe?" | Ingredient Checker | Single product safety query |
| "Can I use retinol with vitamin C?" | Ingredient Interaction | Ingredient compatibility query |
| "What is rosacea? What causes it?" | Skin Condition | Condition information request |
| "What does hyaluronic acid do?" | Q&A Agent | General skincare knowledge |
| "Show me skincare videos about acne" | KOL Content Agent | Content recommendation request |
| "How has my skin changed?" | Progress Tracker | Progress comparison request |
| "Check this product's safety AND interactions" | Parallel Ingredient Agent | Combined safety + interaction check |
| "Give me a full consultation" | Consultation Pipeline | End-to-end consultation pipeline |
| "Build me a safe routine for sensitive skin" | Routine Review Agent | Routine with safety validation loop |

---

## 4. Tools & Integrations

### 4.1 Vertex AI Search Datastores

The system uses 5 Vertex AI Search datastores for grounded knowledge retrieval:

| Datastore | Content | Data Source | Agents Using It |
|---|---|---|---|
| `skincare-ingredients` | 3,000+ skincare ingredients with safety/efficacy data | Structured data | Ingredient Checker, Q&A Agent |
| `test-first-bigquery-table` | Ingredient interaction and compatibility data | BigQuery table | Ingredient Interaction Agent |
| `skin-conditions` | Common conditions: symptoms, triggers, care guidelines | Structured data | Skin Condition Agent |
| `routine-templates` | Evidence-based routine templates by skin type/concern | Structured data | Routine Builder Agent |
| `kol-content` | KOL/influencer skincare video content catalog | Google Sheets | KOL Content Agent |

### 4.2 Custom Tools (FunctionTools)

| Tool Name | Used By | Function | Storage |
|---|---|---|---|
| `save_analysis_to_state` | Skin Analyzer | Persists skin analysis results to session state | Session State |
| `save_progress_note` | Progress Tracker | Records a progress observation with date | Session State |
| `get_progress_notes` | Progress Tracker | Retrieves historical progress notes | Session State |
| `exit_loop` | Routine Refiner | Signals the LoopAgent to stop iterating | ToolContext (escalate) |

### 4.3 Built-in ADK Tools

- **PreloadMemoryTool** — Retrieves user memories from Vertex AI Memory Bank at the start of every turn, enabling cross-session personalization
- **VertexAiSearchTool** — Grounded knowledge retrieval from Vertex AI Search datastores (used by 5 specialist agents)
- **AgentTool** — Wraps sub-agents as callable tools that execute via `run_async()` in isolated contexts

### 4.4 ADK Callbacks

| Callback | Type | Function |
|---|---|---|
| `_safety_guardrail` | `before_model_callback` | Model Armor prompt sanitization + medical request blocking |
| `_output_safety_check` | `after_model_callback` | Model Armor response screening + medical language flagging |
| `generate_memories_callback` | `after_agent_callback` | Sends recent events to Memory Bank for memory extraction |

---

## 5. Knowledge Base & RAG Architecture

The skincare advisor's accuracy depends on grounded knowledge retrieval through Vertex AI Search datastores. This ensures all recommendations are evidence-based rather than relying solely on the LLM's training data.

### 5.1 Knowledge Base Structure

| Datastore | Content | Update Mechanism |
|---|---|---|
| Ingredients | 3,000+ skincare ingredients with safety/efficacy data | Vertex AI Search ingestion |
| Ingredient Interactions | Known conflicts and synergies between active ingredients | BigQuery table → Vertex AI Search |
| Skin Conditions | Common conditions: symptoms, triggers, care guidelines | Vertex AI Search ingestion |
| Routine Templates | Evidence-based routine templates by skin type and concern | Vertex AI Search ingestion |
| KOL Content | Curated KOL/influencer skincare video content | Google Sheets → Vertex AI Search connector |

### 5.2 Retrieval Pipeline

```
User Query (via AgentTool → sub-agent)
        │
        ▼
VertexAiSearchTool(data_store_id=..., bypass_multi_tools_limit=True)
  - Automatic query formation from agent context
  - Semantic search over datastore
        │
        ▼
Gemini 2.5 Flash (sub-agent)
  - Receives retrieved documents as context
  - Generates grounded response
  - Returns text result to root agent via AgentTool
        │
        ▼
Root Agent (gemini-live-2.5-flash-native-audio)
  - Speaks the response to the user in real-time
```

---

## 6. Security & Safety — Defense in Depth

> **CRITICAL:** Skin photos and health-related data are sensitive personal information. The system implements 5 layers of security.

### 6.1 Layer 1: Google Cloud Model Armor

ML-powered prompt and response sanitization using the Model Armor Python SDK:

| Filter | Detection |
|---|---|
| Responsible AI (RAI) | Hate speech, harassment, sexually explicit, dangerous content |
| Prompt Injection & Jailbreak | Attempts to override system instructions or extract prompts |
| Sensitive Data Protection (PII/SDP) | Credit cards, SSN, API keys, passwords, phone numbers |
| Malicious URI Detection | URLs linked to phishing, malware, or other threats |
| CSAM | Always-on child safety protection |

**Fail-open design:** If Model Armor is unavailable, requests pass through with a warning log — never silently blocking all users.

```python
from google.cloud import modelarmor_v1

# Prompt sanitization
result = model_armor.sanitize_prompt(user_text)
if result.is_blocked:
    return tailored_response(result.blocked_reason)

# Response sanitization
result = model_armor.sanitize_response(response_text)
if result.is_blocked:
    return safe_rephrased_response()
```

### 6.2 Layer 2: ADK before_model_callback

Domain-specific medical request blocking that Model Armor doesn't cover:

- Blocks explicit prescription/diagnosis requests (12 patterns)
- Returns friendly redirect to dermatologist consultation
- Custom to skincare domain boundaries

### 6.3 Layer 3: ADK after_model_callback

Output screening for medical language in model responses:
- Model Armor response screening
- Flags medical-sounding language (logging only for monitoring)
- "I diagnose," "prescription for," etc.

### 6.4 Layer 4: Gemini Built-in Safety Filters

Configured in `generate_content_config` with `BLOCK_MEDIUM_AND_ABOVE` threshold for:
- Dangerous content
- Harassment
- Hate speech
- Sexually explicit content

### 6.5 Layer 5: System Prompt Guardrails

Root orchestrator prompt includes:
- Explicit persona boundary: "You are NOT a dermatologist"
- Body-positive language requirements
- Severity-based dermatologist referral thresholds
- No storage of raw video streams

### 6.6 Authentication & Data Protection

- Firebase Authentication for user identity (Google Sign-In, email/password)
- JWT token validation on every WebSocket connection
- CORS restricted to allowed origins only
- Rate limiting: 30 text messages per 60-second window per session
- Non-root container user in production Docker image
- API keys stored in Secret Manager

---

## 7. Observability — BigQuery Agent Analytics

### 7.1 BigQuery Agent Analytics Plugin

The system uses ADK's BigQuery Agent Analytics Plugin for comprehensive observability:

```python
from google.adk.plugins.bigquery_agent_analytics_plugin import (
    BigQueryAgentAnalyticsPlugin,
    BigQueryLoggerConfig,
)

bq_plugin = BigQueryAgentAnalyticsPlugin(
    project_id=_PROJECT_ID,
    dataset_id="adk_agent_logs",
    table_id="agent_events_ai_skincare_advisor",
    config=BigQueryLoggerConfig(
        enabled=True,
        gcs_bucket_name=os.environ.get("GCS_BUCKET_NAME"),
        log_multi_modal_content=True,
        max_content_length=500 * 1024,  # 500 KB
        batch_size=1,                   # Low latency
    ),
)
```

### 7.2 What Gets Logged

All agent events are automatically captured in BigQuery:

- **Agent Execution Events** — which agent handled each request
- **LLM Call Events** — prompts, completions, token counts, latency
- **Tool Invocation Events** — input parameters, output, duration, success/failure
- **Multimodal Content** — audio/image data stored in GCS, referenced from BigQuery
- **Session Events** — session creation, state updates

### 7.3 BigQuery Analytics Views

Custom SQL views provide operational dashboards (defined in `docs/bigquery_analytics_views.sql`):

- Agent usage distribution
- Tool call success rates
- Response latency percentiles
- Session completion patterns
- Error rate monitoring

### 7.4 Structured Logging

JSON-structured logging with rotating file handler:
- Console handler: INFO level
- File handler: 5MB max, 3 backup files (`logs/server.log`)
- Noisy ADK module suppression (audio cache, protocol, connection)

---

## 8. Cross-Session Memory — Vertex AI Memory Bank

### 8.1 Architecture

The system uses Vertex AI Memory Bank for persistent, cross-session user memories:

- **PreloadMemoryTool** — Retrieves relevant memories at the start of every turn
- **after_agent_callback** — Sends recent events to Memory Bank after each turn

### 8.2 Memory Extraction

```python
async def generate_memories_callback(callback_context: CallbackContext):
    """Sends recent events to Memory Bank for memory extraction."""
    recent_events = callback_context.session.events[-5:-1]
    if recent_events:
        await callback_context.add_events_to_memory(events=recent_events)
```

The Memory Bank LLM automatically:
- Extracts meaningful info (skin type, preferences, concerns, routines)
- Consolidates with existing memories (update, not duplicate)
- Ignores non-informative turns

### 8.3 Dual-Mode Services

| Mode | Session Service | Memory Service | Trigger |
|---|---|---|---|
| Local Dev | `InMemorySessionService` | `InMemoryMemoryService` | `AGENT_ENGINE_ID` not set |
| Production | `VertexAiSessionService` | `VertexAiMemoryBankService` | `AGENT_ENGINE_ID` set |

**Note:** Live streaming sessions always use `InMemorySessionService` because `VertexAiSessionService`'s events API is incompatible with `run_live()`.

---

## 9. Push Notifications — Firebase Cloud Messaging

### 9.1 Notification Types

| Type | Trigger | Content |
|---|---|---|
| Routine Reminder | Scheduled (morning/evening) | "Time to start your morning skincare routine!" |
| Follow-up Nudge | Time since last consultation | "How's your skin doing? Want to check in?" |
| Progress Milestone | 3, 5, 10, 25 check-ins | "🏆 10 Check-ins! Incredible dedication!" |
| Product Discount | Personalized to skin concerns | Matched from product catalog with buy_url |

### 9.2 Product Catalog

The `server/product_catalog.py` module provides a curated product catalog matched to user skin concerns, enabling personalized deal notifications with direct e-commerce purchase links.

### 9.3 API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/register-token` | POST | Register FCM device token |
| `/api/send-notification` | POST | Send push notification to user |
| `/api/trigger-reminders` | POST | Trigger routine reminders + product deals for all users |

---

## 10. Flutter Mobile App — "Glow"

### 10.1 App Architecture

The Flutter app provides a native iOS/Android experience for real-time skincare consultation:

| Screen | File | Purpose |
|---|---|---|
| Login | `login_screen.dart` | Firebase Auth (Google Sign-In, email/password) |
| Home | `home_screen.dart` | Dashboard with consultation history |
| Main | `main_screen.dart` | Navigation and app shell |
| Consultation Lobby | `consultation_lobby_screen.dart` | Pre-consultation setup |
| Consultation | `consultation_screen.dart` | Real-time voice/video consultation |
| Chat | `chat_screen.dart` | Text-based chat interface |

### 10.2 Services

| Service | File | Purpose |
|---|---|---|
| Audio | `audio_service.dart` | PCM audio capture and playback |
| Camera | `camera_service.dart` | Camera capture for skin analysis |
| WebSocket | `websocket_service.dart` | Bidi-streaming connection to backend |
| Auth | `auth_service.dart` | Firebase Auth state management |
| Chat History | `chat_history_service.dart` | Session history retrieval |
| Notifications | `notification_service.dart` | FCM push notification handling |

### 10.3 Key Features

- Real-time voice conversation with native audio streaming
- Camera integration for live skin analysis
- Tool event display (shows "Analyzing ingredients..." during agent processing)
- Transcription display (input and output transcription)
- Push notification support for routine reminders and product deals
- Custom theme with dark mode support

---

## 11. Project Structure

```
AI_Skincare_Advisor/
├── app/
│   ├── .env                                # API keys & config
│   └── skincare_advisor/
│       ├── __init__.py                     # Package init (imports root_agent)
│       ├── agent.py                        # Root Orchestrator Agent
│       ├── model_armor.py                  # Model Armor SDK integration
│       ├── callbacks/
│       │   ├── __init__.py
│       │   └── memory_callbacks.py         # Memory Bank after_agent_callback
│       ├── sub_agents/
│       │   ├── __init__.py
│       │   ├── agent_factories.py          # DRY agent creation (single-parent rule)
│       │   ├── skin_analyzer.py            # Skin Analyzer Agent
│       │   ├── routine_builder.py          # Routine Builder Agent
│       │   ├── ingredient_checker.py       # Ingredient Checker Agent
│       │   ├── ingredient_interaction.py   # Ingredient Interaction Agent
│       │   ├── skin_condition.py           # Skin Condition Agent
│       │   ├── qa_agent.py                 # General Q&A Agent
│       │   ├── kol_content.py              # KOL Content Agent
│       │   ├── progress_tracker.py         # Progress Tracker Agent
│       │   ├── parallel_ingredient_check.py # ParallelAgent workflow
│       │   ├── consultation_pipeline.py    # SequentialAgent pipeline
│       │   └── routine_review_loop.py      # LoopAgent review workflow
│       ├── tools/
│       │   ├── __init__.py
│       │   ├── skin_tools.py              # save_analysis_to_state
│       │   └── progress_tools.py          # save_progress_note, get_progress_notes
│       ├── prompts/                        # 13 system prompts (one per agent)
│       │   ├── root_orchestrator.txt
│       │   ├── skin_analyzer.txt
│       │   ├── routine_builder.txt
│       │   ├── ingredient_checker.txt
│       │   ├── ingredient_interaction.txt
│       │   ├── skin_condition.txt
│       │   ├── qa_agent.txt
│       │   ├── kol_content.txt
│       │   ├── progress_tracker.txt
│       │   ├── ingredient_synthesis.txt
│       │   ├── consultation_synthesis.txt
│       │   ├── routine_critic.txt
│       │   └── routine_refiner.txt
│       └── tests/
│           └── integration/
├── server/
│   ├── main.py                             # FastAPI + WebSocket + ADK Runner
│   ├── auth.py                             # Firebase Auth JWT verification
│   ├── model_armor.py                      # Model Armor (server copy)
│   ├── notifications.py                    # FCM push notification service
│   └── product_catalog.py                  # Product catalog for deal notifications
├── frontend/
│   └── flutter_app/                        # Flutter "Glow" mobile app
│       └── lib/
│           ├── main.dart                   # App entry point
│           ├── router.dart                 # GoRouter navigation
│           ├── theme.dart                  # Material 3 dark theme
│           ├── config.dart                 # Backend URL config
│           ├── firebase_options.dart
│           ├── screens/                    # 6 screens (login, home, main, lobby, consultation, chat)
│           └── services/                   # 6 services (audio, camera, websocket, auth, chat, notifications)
├── scripts/
│   ├── create_agent_engine.py              # Create Vertex AI Agent Engine instance
│   ├── create_model_armor_template.py      # Create Model Armor template
│   ├── deploy-backend.sh                   # Backend deployment script
│   ├── deploy.py                           # Python deployment orchestrator
│   ├── setup-gcp.sh                        # GCP project setup
│   └── test_websocket.py                   # WebSocket connection test
├── docs/
│   ├── project_document.md                 # This document
│   ├── blog_post.md                        # Hackathon blog post
│   ├── submission_text.md                  # Hackathon submission
│   ├── frontend_screens.md                 # Frontend documentation
│   ├── model_armor.md                      # Model Armor documentation
│   ├── bigquery_analytics_views.sql        # BigQuery dashboard queries
│   ├── eval_results.txt                    # Agent evaluation results
│   └── *.png                               # Architecture diagrams
├── logs/                                    # Rotating server logs
├── Dockerfile                               # Cloud Run container (Python 3.13-slim)
├── Dockerfile.flutter                       # Flutter web build container
├── requirements.txt                         # Python dependencies
├── .env                                     # Root environment variables
└── README.md                                # Project README
```

---

## 12. Deployment Architecture

### 12.1 Environments

| Environment | Platform | Session/Memory Services | Observability |
|---|---|---|---|
| Local Dev | `python -m server.main` | `InMemorySession/MemoryService` | Console + file logging, BigQuery plugin |
| Production | Cloud Run + Agent Engine | `VertexAiSession/MemoryBankService` | BigQuery analytics + Cloud Logging |

### 12.2 Cloud Run Deployment

```dockerfile
# Dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN adduser --disabled-password --gecos "" appuser && \
    chown -R appuser:appuser /app
COPY . .
USER appuser
CMD ["sh", "-c", "uvicorn server.main:web_app --host 0.0.0.0 --port ${PORT:-8080}"]
```

### 12.3 WebSocket Configuration

Production WebSocket settings optimized for long-running tool calls:
- `ws_ping_interval=30` — Ping every 30s (prevents idle disconnects)
- `ws_ping_timeout=120` — Wait up to 120s for pong (handles slow tool calls)

### 12.4 Deployment Scripts

| Script | Purpose |
|---|---|
| `scripts/deploy-backend.sh` | Build and deploy to Cloud Run |
| `scripts/deploy.py` | Python deployment orchestrator |
| `scripts/create_agent_engine.py` | Create Vertex AI Agent Engine instance |
| `scripts/create_model_armor_template.py` | Create Model Armor template via gcloud |
| `scripts/setup-gcp.sh` | Initial GCP project setup (APIs, IAM, services) |

### 12.5 Key Environment Variables

| Variable | Purpose | Required |
|---|---|---|
| `GOOGLE_CLOUD_PROJECT` | GCP project ID | Yes |
| `GOOGLE_CLOUD_LOCATION` | Region (default: us-central1) | Yes |
| `AGENT_ENGINE_ID` | Vertex AI Agent Engine ID (production mode) | Prod only |
| `MODEL_ARMOR_TEMPLATE_ID` | Model Armor template ID | Optional |
| `GCS_BUCKET_NAME` | GCS bucket for BigQuery multimodal content | Optional |
| `BQ_DATASET_ID` | BigQuery dataset (default: adk_agent_logs) | Optional |
| `ALLOWED_ORIGINS` | CORS allowed origins | Optional |
| `SKIP_AUTH` | Skip Firebase Auth in local dev | Dev only |

---

## 13. Dependencies

```
google-adk[eval]==1.23.0
google-genai==1.60.0
google-cloud-aiplatform[agent_engine]
fastapi
uvicorn[standard]
python-dotenv
firebase-admin
opentelemetry-sdk
google-cloud-modelarmor
```

---

*Glow — AI Skincare Advisor — Powered by Google ADK & Gemini*
