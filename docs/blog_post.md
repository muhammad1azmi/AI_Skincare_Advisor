# How I Built a Real-Time AI Skincare Advisor with Google ADK and Gemini Live API

*I created this piece of content for the purposes of entering the #GeminiLiveAgentChallenge hackathon.*

---

## The Problem

Getting personalized skincare advice is surprisingly hard. A dermatologist visit costs $150–$300, wait times can stretch to weeks, and in many parts of the world, dermatologists simply aren't available. Meanwhile, online skincare advice is a mess — conflicting opinions, product sponsorships disguised as recommendations, and zero personalization.

Most "AI skincare tools" are just chatbots. You type, they reply. They can't see your skin, can't hear you describe your concerns naturally, and definitely can't be interrupted mid-sentence when they go off on a tangent.

I wanted to build something different: **an AI that can see, hear, and speak — like video-calling a skincare expert who actually knows you.**

## Meet Glow

Glow is a mobile app that provides real-time, multimodal skincare consultations. You open the app, tap "Start Consultation," and begin talking to an AI advisor while pointing your camera at your skin. The AI:

- **Sees** your skin through live camera streaming (1 FPS JPEG frames)
- **Listens** to your concerns via real-time audio streaming (PCM 16kHz)
- **Speaks back** with natural voice responses
- **Handles interruptions** — talk over it, and it stops and listens
- **Remembers you** across sessions — your skin type, past concerns, routines

It's built entirely on Google's AI stack: **ADK** (Agent Development Kit) for multi-agent orchestration, **Gemini 2.5 Flash** via the **Live API** for real-time multimodal reasoning, and **Google Cloud** for production hosting.

## The Architecture: Three Pillars

### 1. Security-First 🛡️

Glow handles health-adjacent conversations and live camera data. Security couldn't be an afterthought — it had to be the foundation. I implemented **5 layers of defense-in-depth**:

**Google Cloud Model Armor** is the star here. It's a managed ML-powered service that sanitizes both inputs and outputs, catching prompt injection attempts, jailbreak attacks, PII leakage, harmful content, and malicious URLs. Before Model Armor, I was writing regex patterns to catch injection attacks — fragile, incomplete, and constantly needing updates. Model Armor replaced all of that with a single API call.

On top of Model Armor, I added **domain-specific guardrails** via ADK's `before_model_callback` and `after_model_callback`. The before-callback catches explicit medical requests ("prescribe me tretinoin") and redirects users to healthcare professionals. The after-callback screens the AI's output for medical language that shouldn't appear in a skincare advisor's response.

Then there are **Gemini's built-in safety filters** (configured to `BLOCK_MEDIUM_AND_ABOVE`) and **explicit prompt guardrails** in the root orchestrator's instructions.

Five layers might sound excessive, but for a health-adjacent AI that processes camera data and voice, defense-in-depth is the only responsible approach.

### 2. Observability-First 📊

"Works on my machine" isn't good enough for an AI agent. You can't improve what you can't measure.

From day one, I instrumented everything. All agent interactions flow into a **BigQuery dataset** (`adk_agent_logs`) where I can analyze routing decisions, response quality, tool call success rates, and session patterns. ADK's built-in **OpenTelemetry integration** captures every agent run, LLM call, and tool invocation as spans, exported to **Cloud Trace**.

This observability infrastructure paid for itself immediately. I discovered that the Skin Analyzer agent was being routed too aggressively — general questions like "what's a good moisturizer?" were being sent to the skin analysis specialist instead of the Q&A agent. BigQuery trace analysis surfaced the pattern, and I tuned the routing prompt accordingly.

### 3. Eval-Driven Development 🧪

Here's a hot take: **most AI agent development is vibes-based**. You tweak a prompt, manually test a few queries, and ship it. This doesn't scale.

I used ADK's evaluation framework to iterate on agent quality scientifically:

- **Routing accuracy tests**: Does the root orchestrator pick the correct specialist for each query type?
- **Safety guardrail tests**: Are medical/prescription requests properly deflected?
- **Response quality evaluations**: Are skincare recommendations relevant, accurate, and appropriately cautious?

Every prompt change goes through the eval pipeline before deployment. This caught several issues early, including cases where the ingredient checker would confidently recommend ingredient combinations that dermatologists advise against.

## The Multi-Agent System

Glow isn't one monolithic AI — it's a team of **11 specialized agents** coordinated by a root orchestrator:

- **Skin Analyzer** — analyzes skin from the live camera feed
- **Routine Builder** — creates personalized AM/PM skincare routines
- **Ingredient Checker** — verifies ingredient safety and efficacy
- **Ingredient Interaction Agent** — checks for harmful ingredient combinations
- **Skin Condition Agent** — identifies and explains skin conditions
- **Q&A Agent** — answers general skincare questions
- **KOL Content Agent** — recommends influencer-curated content from BigQuery
- **Progress Tracker** — tracks skin improvements over time

Plus three **composite workflow agents** that orchestrate multiple sub-agents: parallel ingredient checking, end-to-end consultation pipeline, and iterative routine review.

### The AgentTool Pattern

The biggest technical challenge was making multi-agent orchestration work with Gemini's native-audio live model. The Live API doesn't support mixing tool types within the same session — meaning `VertexAiSearchTool` (used by most sub-agents) won't work directly in a live session.

The solution: **wrap every sub-agent as an `AgentTool`**. When the root orchestrator calls `AgentTool.run_async()`, it creates a completely independent `Runner` + `InMemorySessionService` context. The sub-agent runs in standard async mode (not live streaming), so tools like `VertexAiSearchTool` work perfectly. The text result flows back to the live model like any function response.

This pattern is clean, scalable, and avoids the tool-type conflicts entirely.

## The Tech Stack

| Component | Technology |
|---|---|
| AI Model | Gemini 2.5 Flash (native audio) |
| Agent Framework | Google ADK |
| Real-time Streaming | Gemini Live API + `LiveRequestQueue` |
| Backend | FastAPI on Cloud Run |
| Agent Hosting | Vertex AI Agent Engine (EXPERIMENTAL mode) |
| Security | Google Cloud Model Armor |
| Search & Grounding | Vertex AI Search |
| Analytics | BigQuery |
| Auth | Firebase Auth |
| Push Notifications | Firebase Cloud Messaging |
| Mobile App | Flutter (Android) |
| CI/CD | GitHub Actions → Firebase App Distribution |
| Deployment | Infrastructure-as-Code scripts |

## Key Learnings

1. **Model Armor is a game-changer.** Stop writing regex for prompt injection detection. Google's ML-powered sanitization provides better coverage with zero maintenance.

2. **The AgentTool pattern is essential** for complex multi-agent systems with Gemini Live API. Sub-agents need independent execution contexts.

3. **Eval-driven development saves time.** Automated evaluation caught subtle routing and safety issues that manual testing would have missed.

4. **Observability from day one.** BigQuery analytics surfaced agent behavior patterns (routing biases, error rates) that would have been invisible without instrumentation.

5. **Bidi-streaming is powerful but tricky.** Getting `LiveRequestQueue` working end-to-end on Agent Engine required working through EXPERIMENTAL mode nuances — but the real-time voice + video experience is worth it.

## What's Next

Glow is a proof of concept of what's possible when you combine real-time multimodal AI with production-grade architecture. The vision is to make expert-level skincare advice accessible to anyone with a smartphone — while always encouraging professional consultation for serious concerns.

---

*Built with Google ADK, Gemini 2.5 Flash, and Google Cloud. #GeminiLiveAgentChallenge*
