# How I Built a Real-Time AI Skincare Advisor with Google ADK and Gemini Live API

*I created this piece of content for the purposes of entering the #GeminiLiveAgentChallenge hackathon.*

---

## It Started with a Frustrating Appointment

A few months ago, I tried booking a dermatologist. The earliest slot was six weeks out, and the consultation fee was $200. When I finally got in, the doctor spent about ten minutes looking at my skin, gave me a generic routine, and sent me on my way.

On the drive home, I thought: what if I could just *show* my skin to an AI and talk through my concerns in real time? Not a chatbot where I type "my skin is dry" and get a wall of text back — a real conversation where the AI can actually *see* what I'm describing.

That was the spark for **Glow**.

## The First Prototype Was Terrible

My first attempt was simple: a text chatbot built with the Gemini API. You'd describe your skin in text, and it would respond. It worked, technically. But it missed the entire point.

Skincare is visual. When someone says "I have these spots on my cheek," the difference between post-inflammatory hyperpigmentation and fungal acne changes the advice completely. And typing out skin concerns feels unnatural — people want to *talk* about their skin while *showing* it.

So I threw away the chatbot and started over with the **Gemini Live API**. This was the turning point.

## Discovering Gemini Live API and ADK

The Gemini Live API enables bidirectional streaming — you send audio and video in real time, and the model responds with voice. It's not request-response; it's a continuous stream. You can interrupt the AI mid-sentence, and it stops and listens. It feels like a real conversation.

But I quickly realized a single model call wouldn't cut it. Skincare spans too many domains: analyzing skin conditions, checking ingredient interactions, building personalized routines, tracking progress over time. One model with one prompt would either be mediocre at everything or hallucinate wildly.

That's when I found **Google ADK** (Agent Development Kit). ADK lets you build multi-agent systems where a root orchestrator routes requests to specialist agents, each with their own knowledge, tools, and prompts. This was exactly what I needed.

I designed **11 specialist agents** — a Skin Analyzer that processes camera frames, a Routine Builder grounded with Vertex AI Search, an Ingredient Interaction agent that catches dangerous combinations (like vitamin C + retinol in the same step), a Progress Tracker that compares your skin over time, and more.

The root orchestrator listens to the user, decides which specialist to call, waits for the result, and speaks it back — all in real time over voice.

## The AgentTool Breakthrough

The biggest technical wall I hit was that the Live API doesn't support mixing tool types. Most of my sub-agents use `VertexAiSearchTool` for RAG-grounded responses — they query real skincare knowledge datastores, not just whatever the model remembers from training. But `VertexAiSearchTool` doesn't work inside a live streaming session.

I was stuck for a while. Then I found the `AgentTool` pattern in ADK's documentation. Instead of using sub-agents directly (which would inherit the live session), you wrap each sub-agent as an `AgentTool`. When the orchestrator calls it, ADK spins up a completely independent execution context — new Runner, new session, standard async mode. The sub-agent runs its Vertex AI Search queries happily in isolation, and the text result flows back to the live model like any tool response.

This single pattern unlocked the entire multi-agent architecture. Without it, I would have been limited to a single agent with no grounding.

## Security Kept Me Up at Night

Here's the thing about building an AI that sees people's skin and listens to their health concerns — you can't ship it with just "hope the model behaves." This is health-adjacent. People will ask it to prescribe medication. People will try to jailbreak it. And the camera stream means you're processing sensitive biometric-adjacent data.

I ended up building **five layers of security**, and each layer exists because the one above it isn't enough:

First, I integrated **Google Cloud Model Armor** — it's an ML-powered service that sanitizes both inputs and outputs. It catches prompt injection, jailbreak attempts, PII leakage, harmful content, and malicious URLs. Before I found Model Armor, I was writing regex patterns to detect prompt injections. That approach was fragile and always one step behind attackers. Model Armor replaced all of it with a single API call.

But Model Armor doesn't know about skincare-specific boundaries. It won't block "prescribe me tretinoin" because that's a legitimate sentence — just not one a skincare advisor should respond to. So I added a **`before_model_callback`** with domain-specific medical pattern matching.

Then I added an **`after_model_callback`** that screens the AI's output — even if the input wasn't flagged, the model might still generate medical-sounding language. This layer catches it.

Layers four and five are Gemini's built-in safety filters and explicit prompt guardrails in the root orchestrator's instructions.

Five layers sounds excessive. But for a health-adjacent AI processing camera data and voice? Defense-in-depth is the only responsible approach.

## The Debugging Nightmare: Live Sessions

The most frustrating bug I encountered was with session management. In production, I use `VertexAiSessionService` for persistent sessions — it stores conversation history so the AI remembers users across sessions. But when I connected it to `run_live()`, the stream would close immediately. No error, no crash — just... silence.

After hours of debugging with OpenTelemetry traces, I discovered the issue: Vertex AI's session service calls an `events.list()` API internally that's incompatible with the live streaming protocol. The API call blocks the stream before it can even start.

The fix was counterintuitive: use `InMemorySessionService` for live sessions (voice/video), while keeping `VertexAiSessionService` for text-based sessions and memory. The live session is ephemeral, but memory persistence still works because `VertexAiMemoryBankService` runs independently.

This is the kind of thing no documentation tells you. It took raw debugging.

## Making the AI Remember You

One of Glow's best features is **cross-session memory**. The AI remembers your skin type, past concerns, products you've tried, and routines you're following. Session three doesn't start from scratch.

I used ADK's `PreloadMemoryTool` and `generate_memories_callback`. After each conversation turn, the callback generates memory snippets — observations about the user's skin, product preferences, and concern history. On the next session, `PreloadMemoryTool` retrieves relevant memories and injects them into context.

The first time a user comes back and the AI says "Last time we talked about the dryness around your nose — how's that been going?", the experience changes completely. It goes from "talking to a tool" to "talking to *my* skincare advisor."

## Observability: You Can't Improve What You Can't Measure

I integrated **BigQuery Agent Analytics** from day one. Every agent interaction — routing decisions, tool calls, response times — flows into a BigQuery dataset. Combined with OpenTelemetry tracing, I can see exactly what happened in any conversation.

This paid off almost immediately. I noticed the Skin Analyzer agent was being called for general questions like "what's a good moisturizer?" — questions that should go to the Q&A agent. The BigQuery logs showed a routing bias in the orchestrator's prompt. I tuned the prompt, re-ran the evaluation suite, and the mis-routing dropped to zero.

Without observability, I never would have noticed this pattern. The model still gave plausible answers through the wrong agent — it just wasn't using the knowledge grounding it should have been.

## Eval-Driven: No More Vibes-Based Development

Here's a hot take: most AI agent development is vibes-based. You tweak a prompt, manually test a few queries, and ship it. This doesn't scale.

I set up ADK's evaluation framework with test suites covering routing accuracy, safety guardrails, and response quality. Every prompt change runs through automated evals before deployment.

The evals caught a critical issue early: the Ingredient Checker was confidently recommending vitamin C and retinol in the same routine step — a combination most dermatologists advise against for sensitive skin. The eval flagged it, I added interaction-checking logic, and the issue was resolved before any user encountered it.

## Deploying to Google Cloud

The production stack runs on **Google Cloud Run** (FastAPI WebSocket server), **Vertex AI Agent Engine** (managed agent hosting with bidi-streaming), **Vertex AI Search** (RAG datastores), **BigQuery** (analytics + KOL content), **Firebase Auth** (Google Sign-In), and **Firebase Cloud Messaging** (push notifications for routine reminders).

I automated everything with infrastructure-as-code scripts — a single `setup-gcp.sh` creates the entire GCP infrastructure, `deploy.py` handles Agent Engine deployment, and GitHub Actions builds and distributes the Flutter APK via Firebase App Distribution.

The whole thing can be reproduced from a fresh GCP project with three scripts and one git push.

## What I Learned

Building Glow taught me that the gap between a demo and a product is enormous. The Live API demo took a day. Making it production-ready — with security, observability, eval-driven quality, persistent memory, and proper error handling — took weeks.

But the result is something I'm genuinely proud of: an AI that can see your skin, hear your concerns, remember your history, and give grounded, safe advice — all in real time, all running on Google Cloud.

The vision is simple: expert-level skincare advice accessible to anyone with a smartphone. While always encouraging professional consultation for serious concerns.

---

*Built with ❤️ using Google ADK, Gemini 2.5 Flash, and Google Cloud for the #GeminiLiveAgentChallenge*

*#GeminiLiveAgentChallenge*
