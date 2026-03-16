# Glow — AI Skincare Advisor

## Inspiration

Skincare is deeply personal, yet access to expert advice is unequal. A single dermatologist visit can cost $150–$300, and in many parts of the world, dermatologists are scarce entirely. Meanwhile, the internet is flooded with conflicting advice, and most skincare "AI tools" are glorified chatbots that can't even see your skin.

We asked: **what if you could video-call an AI skincare expert that actually sees you, listens to you, and speaks back — like having a dermatologist in your pocket?**

## What It Does

**Glow** is a real-time, multimodal AI skincare advisor built as a mobile app. Users can:

- **Talk naturally** — the AI listens via real-time audio streaming and responds with a natural, warm voice. You can interrupt it mid-sentence, and it handles it gracefully.
- **Show your skin** — point your phone camera at your skin, and the AI analyzes texture, redness, dryness, acne, and more in real-time (1 FPS video streaming).
- **Get personalized routines** — based on your skin type, concerns, climate, budget, and ingredient preferences.
- **Check ingredients** — scan a product label or ask about ingredient interactions (e.g., "Can I use retinol with niacinamide?").
- **Track progress** — compare your skin condition over time with periodic analysis snapshots.
- **Discover content** — get curated recommendations from skincare KOLs via BigQuery-powered content search.

The app seamlessly transitions from **live voice+video consultation** to **text chat**, preserving the full conversation transcript. Cross-session memory means the AI remembers your skin type, past concerns, and routines — it picks up right where you left off.

## How We Built It

### Architecture: Three Design Pillars

We built Glow with three architectural pillars that guided every design decision:

**1. Security-First 🛡️**

Since Glow handles health-adjacent conversations and camera data, we implemented **defense-in-depth with 5 layers of security**:

- **Google Cloud Model Armor** — ML-powered prompt and response sanitization that catches prompt injection, jailbreak attempts, PII/sensitive data leakage, harmful content, and malicious URLs. This is a Google-managed service that provides production-grade protection far beyond regex patterns.
- **before_model_callback** — domain-specific guardrail that blocks medical diagnosis/prescription requests (e.g., "prescribe me tretinoin") and redirects users to healthcare professionals.
- **after_model_callback** — screens the AI's output through Model Armor and flags medical language in responses.
- **Gemini built-in safety filters** — configured SafetySettings (BLOCK_MEDIUM_AND_ABOVE) for dangerous content, harassment, hate speech, and sexually explicit content.
- **Root prompt safety guardrails** — explicit persona boundary instructions that reinforce the AI's role as an advisor, not a doctor.

**2. Observability-First 📊**

You can't improve what you can't measure. We instrumented everything from day one:

- **BigQuery Agent Analytics** — all agent interactions flow into a BigQuery dataset (`adk_agent_logs`) for analysis. We track routing decisions, response quality, tool call success rates, and session patterns.
- **OpenTelemetry tracing** — every agent run, LLM call, tool invocation, and agent transfer is captured as spans via ADK's built-in OpenTelemetry integration, exported to Cloud Trace.
- **Custom dashboards** — we monitor p95 latency, token usage per session, tool call success rates, and safety guardrail triggers.

This observability infrastructure lets us identify and fix issues quickly — for example, we discovered that the Skin Analyzer agent was being routed too aggressively for general questions, and we tuned the routing prompt based on BigQuery trace data.

**3. Eval-Driven Agentic AI Development 🧪**

We used ADK's evaluation framework to iterate on agent quality scientifically, not by vibes:

- **Routing accuracy tests** — does the root orchestrator pick the correct specialist agent for each query type?
- **Safety guardrail tests** — are medical/prescription requests properly deflected?
- **Response quality evaluations** — are skincare recommendations relevant, accurate, and appropriately cautious?

Every prompt change goes through the eval pipeline before deployment. This eval-driven approach caught several issues early, including cases where the ingredient checker would confidently recommend combinations that dermatologists advise against.

### Tech Stack

| Layer | Technology |
|---|---|
| **AI Model** | Gemini 2.5 Flash (native audio) via ADK |
| **Agent Framework** | Google ADK (Agent Development Kit) |
| **Streaming** | Gemini Live API — bidi-streaming via `LiveRequestQueue` |
| **Backend** | FastAPI + Uvicorn on **Google Cloud Run** |
| **Agent Hosting** | Vertex AI Agent Engine (EXPERIMENTAL bidi-streaming mode) |
| **Sessions** | `VertexAiSessionService` (persistent, managed) |
| **Memory** | `PreloadMemoryTool` + `generate_memories_callback` (cross-session) |
| **Security** | Google Cloud Model Armor + multi-layer callbacks |
| **Authentication** | Firebase Auth (Google Sign-In + JWT verification) |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **Search & Grounding** | Vertex AI Search (skincare knowledge datastores) |
| **Analytics** | BigQuery (KOL content, agent analytics) |
| **Frontend** | Flutter (Android) — camera, mic, real-time streaming UI |
| **CI/CD** | GitHub Actions (APK build + Firebase App Distribution) |
| **IaC** | Automated GCP setup + Agent Engine deployment scripts |

### Multi-Agent System

The root orchestrator coordinates **8 specialist agents + 3 workflow agents**, each wrapped as `AgentTool` instances. This is a deliberate architectural choice — `AgentTool.run_async()` creates an independent execution context for each sub-agent, which is critical for compatibility with Gemini's native-audio live model (sub-agents use standard async, not live streaming).

| Agent | Purpose |
|---|---|
| 🔬 Skin Analyzer | Analyzes skin from live camera feed |
| 📋 Routine Builder | Creates personalized AM/PM routines |
| 🧪 Ingredient Checker | Verifies ingredient safety & efficacy |
| ⚠️ Ingredient Interaction | Checks for harmful ingredient combinations |
| 🩺 Skin Condition | Identifies and explains skin conditions |
| ❓ Q&A Agent | Answers general skincare questions |
| 🌟 KOL Content | Recommends influencer-curated content |
| 📊 Progress Tracker | Tracks skin improvements over time |
| ⚡ Parallel Ingredient Check | Runs ingredient + interaction checks simultaneously |
| 🔄 Consultation Pipeline | End-to-end consultation workflow |
| 🔁 Routine Review Loop | Iterative routine refinement |

The root orchestrator uses `BuiltInPlanner` with a thinking budget of 1024 tokens — the model reasons internally about which tool to call and what visual context to include before acting.

## Challenges We Ran Into

1. **Live API + Sub-Agent Compatibility** — The native-audio live model doesn't support mixing tool types within the same session. We solved this with the `AgentTool` pattern: sub-agents run in completely independent `Runner` + `InMemorySessionService` contexts, so `VertexAiSearchTool` works fine because it's not in a live session.

2. **Bidi-Streaming on Agent Engine** — Deploying bidi-streaming agents requires EXPERIMENTAL server mode, which is a newer feature. We had to work through several deployment iterations to get the `LiveRequestQueue` pipeline working correctly end-to-end on Agent Engine.

3. **Model Armor Integration** — Integrating Model Armor with ADK callbacks required careful handling of the sanitization API responses and graceful fallback when the module isn't available (e.g., during local eval runs).

4. **Audio Interruption Handling** — Ensuring smooth interruption when the user speaks over the AI mid-response required careful management of the `LiveRequestQueue` send/receive lifecycle.

## Accomplishments That We're Proud Of

- **True "See, Hear, and Speak"** — Not a text box with a voice wrapper. The AI genuinely processes live video and audio simultaneously and responds in natural speech.
- **5 layers of security** — From Google Cloud Model Armor (ML-powered) to domain-specific medical guardrails, we took security seriously for a health-adjacent AI.
- **11 agents working together** — The multi-agent orchestration with parallel, pipeline, and loop workflow patterns is production-grade.
- **Cross-session memory** — The AI remembers your skin type, past concerns, and routines across sessions using ADK's memory tools.
- **Fully automated deployment** — Infrastructure-as-Code scripts for GCP setup, Agent Engine deployment, and CI/CD pipeline for the Flutter app.

## What We Learned

- **Eval-driven development is essential for agents.** Without automated evaluation, prompt changes are guesswork. Our eval pipeline caught subtle routing and safety issues early.
- **Observability is not optional.** BigQuery analytics surfaced patterns (like agent routing biases) that we would have never found through manual testing.
- **Model Armor is a game-changer** for AI safety. Custom regex-based content filters are fragile and incomplete — Google's ML-powered sanitization provides far better coverage with less maintenance.
- **The `AgentTool` pattern** is the key to making complex multi-agent systems work with Gemini Live API's native audio mode.

## Built With

- google-adk
- gemini-live-api
- gemini-2.5-flash
- google-cloud-run
- vertex-ai-agent-engine
- vertex-ai-search
- google-cloud-model-armor
- bigquery
- firebase-auth
- firebase-cloud-messaging
- flutter
- fastapi
- python
- dart
