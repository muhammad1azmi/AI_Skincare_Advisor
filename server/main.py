"""AI Skincare Advisor — FastAPI + WebSocket Streaming Server.

This server implements the ADK Gemini Live API Bidi-Streaming lifecycle
for real-time voice/video skincare consultations.

Usage:
- LOCAL DEV:  python -m server.main  (InMemory session/memory)
- WITH AE:   Set AGENT_ENGINE_ID in .env (VertexAi session/memory)
- PRODUCTION: python scripts/deploy.py (Agent Engine Runtime)

Architecture:
- ADK App with BigQuery Agent Analytics Plugin for observability
- OpenTelemetry distributed tracing (trace_id, span_id)
- Firebase Auth JWT verification on WebSocket connections
- CORS restricted to allowed origins only
- Dual-mode: VertexAi or InMemory services based on AGENT_ENGINE_ID

5-Phase Lifecycle:
1. App Init — Create Agent, App (w/ BQ plugin), Runner
2. Auth — Verify Firebase JWT on WebSocket connect
3. Session Init — Create/get session, RunConfig, LiveRequestQueue
4. Bidi-Streaming — Concurrent upstream/downstream WebSocket tasks
5. Cleanup — Close queue on disconnect
"""

import asyncio
import base64
import collections
import json
import logging
import os
import time
import traceback

from dotenv import load_dotenv

# Load environment variables (local dev only; Cloud Run uses --set-env-vars)
_root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(_root_dir, ".env"))
load_dotenv(os.path.join(_root_dir, "app", ".env"))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from google.adk.apps import App
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.sessions import VertexAiSessionService, InMemorySessionService
from google.adk.memory import VertexAiMemoryBankService, InMemoryMemoryService
from google.adk.agents.live_request_queue import LiveRequestQueue
from google.adk.plugins.bigquery_agent_analytics_plugin import (
    BigQueryAgentAnalyticsPlugin,
    BigQueryLoggerConfig,
)
from google.genai import types

# OpenTelemetry — enables distributed tracing in BigQuery logs
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
trace.set_tracer_provider(TracerProvider())

# Import the root agent and auth module
import sys
sys.path.insert(0, os.path.join(_root_dir, "app"))
from skincare_advisor.agent import root_agent
from server.auth import verify_websocket_token

# --- Structured Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","module":"%(module)s","message":"%(message)s"}',
)
logger = logging.getLogger("skincare_advisor")

# --- Phase 1: App Initialization ---
web_app = FastAPI(
    title="AI Skincare Advisor",
    description="Real-time multimodal skincare consultation via Gemini Live API",
    version="1.0.0",
    docs_url=None,    # Disable Swagger UI in production
    redoc_url=None,   # Disable ReDoc in production
)

# CORS — restrict to known origins only
_ALLOWED_ORIGINS = os.environ.get(
    "ALLOWED_ORIGINS",
    "http://localhost:3000,http://localhost:8080",
).split(",")

web_app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)

# --- BigQuery Agent Analytics Plugin ---
_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
_LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")

bq_config = BigQueryLoggerConfig(
    enabled=True,
    gcs_bucket_name=os.environ.get("GCS_BUCKET_NAME"),
    log_multi_modal_content=True,
    max_content_length=500 * 1024,  # 500 KB limit for inline text
    batch_size=1,                   # Low latency (increase for high throughput)
    shutdown_timeout=10.0,
    custom_tags={
        "env": os.environ.get("ENV", "dev"),
        "version": "1.0.0",
    },
    log_session_metadata=True,
)
bq_plugin = BigQueryAgentAnalyticsPlugin(
    project_id=_PROJECT_ID,
    dataset_id=os.environ.get("BQ_DATASET_ID", "adk_agent_logs"),
    table_id="agent_events_ai_skincare_advisor",
    config=bq_config,
    location=_LOCATION,
)

# Session & Memory services — dual mode (Vertex AI or InMemory)
_AGENT_ENGINE_ID = os.environ.get("AGENT_ENGINE_ID")

if _AGENT_ENGINE_ID:
    # Production mode: Vertex AI Agent Engine managed services
    session_service = VertexAiSessionService(
        project=_PROJECT_ID,
        location=_LOCATION,
        agent_engine_id=_AGENT_ENGINE_ID,
    )
    memory_service = VertexAiMemoryBankService(
        project=_PROJECT_ID,
        location=_LOCATION,
        agent_engine_id=_AGENT_ENGINE_ID,
    )
    logger.info("Vertex AI services initialized (Agent Engine: %s)", _AGENT_ENGINE_ID)
else:
    # Local dev mode: InMemory services (no GCP dependency)
    session_service = InMemorySessionService()
    memory_service = InMemoryMemoryService()
    logger.info("Local dev mode — using InMemory session/memory services")

# ADK App with BigQuery Analytics plugin (replaces raw Runner)
adk_app = App(
    name="skincare_advisor",
    root_agent=root_agent,
    plugins=[bq_plugin],
    session_service=session_service,
    memory_service=memory_service,
)
runner = adk_app.runner

logger.info("ADK App initialized with BigQuery Agent Analytics plugin")

# Track active streaming sessions
active_queues: dict[str, LiveRequestQueue] = {}

# Rate limiting: per-session message tracking
# { session_id: deque of timestamps }
_rate_limits: dict[str, collections.deque] = {}
_RATE_LIMIT_WINDOW = 60  # seconds
_RATE_LIMIT_MAX_MESSAGES = 30  # max text messages per window

# In-memory storage for FCM tokens (use Firestore in production)
fcm_tokens: dict[str, str] = {}  # user_id -> fcm_token


@web_app.on_event("shutdown")
async def shutdown_event():
    """Graceful shutdown — close all active LiveRequestQueues."""
    logger.info(f"Shutting down: closing {len(active_queues)} active session(s)")
    for sid, queue in list(active_queues.items()):
        try:
            queue.close()
            logger.info(f"Session {sid}: closed on shutdown")
        except Exception:
            pass
    active_queues.clear()


@web_app.get("/")
async def health_check():
    """Enriched health check — verifies system readiness."""
    return {
        "status": "healthy",
        "app": "AI Skincare Advisor",
        "version": "1.0.0",
        "model": root_agent.model,
        "session_service": type(session_service).__name__,
        "memory_service": type(memory_service).__name__,
        "mode": "agent_engine" if _AGENT_ENGINE_ID else "local_dev",
        "agent_engine_id": _AGENT_ENGINE_ID or "not_set",
        "plugins": ["BigQueryAgentAnalyticsPlugin"],
        "active_sessions": len(active_queues),
        "agents": [
            "skincare_advisor (root orchestrator)",
            "skin_analyzer (vision + FunctionTool)",
            "routine_builder (VertexAiSearchTool)",
            "ingredient_checker (VertexAiSearchTool)",
            "ingredient_interaction_agent (VertexAiSearchTool)",
            "skin_condition_agent (VertexAiSearchTool)",
            "qa_agent (VertexAiSearchTool)",
            "kol_content_agent (VertexAiSearchTool)",
            "progress_tracker (FunctionTool)",
        ],
        "grounding": "Vertex AI Search datastores (5 agents)",
        "safety": "Model Armor (PI, PII/SDP, RAI, malicious URIs) + medical guardrail",
    }


@web_app.post("/api/register-token")
async def register_fcm_token(data: dict):
    """Register a device FCM token for push notifications.

    Body: {"user_id": "...", "token": "..."}
    """
    user_id = data.get("user_id")
    token = data.get("token")
    if not user_id or not token:
        return {"error": "user_id and token required"}, 400
    fcm_tokens[user_id] = token
    logger.info(f"FCM token registered for user {user_id}")
    return {"status": "ok"}


@web_app.post("/api/send-notification")
async def send_push_notification(data: dict):
    """Send a push notification to a user.

    Body: {"user_id": "...", "title": "...", "body": "...", "data": {...}}
    """
    from server.notifications import send_notification

    user_id = data.get("user_id")
    token = fcm_tokens.get(user_id)
    if not token:
        return {"error": "No FCM token registered for user"}

    result = await send_notification(
        token=token,
        title=data.get("title", "AI Skincare Advisor"),
        body=data.get("body", ""),
        data=data.get("data"),
    )
    return {"status": "sent" if result else "failed"}


@web_app.get("/api/sessions/{user_id}")
async def list_user_sessions(user_id: str, token: str = ""):
    """List all past sessions for a user.

    Query params:
        token: Firebase ID token for authentication.

    Returns list of session metadata.
    """
    # Skip auth in local dev
    if os.environ.get("SKIP_AUTH", "").lower() != "true":
        if not token:
            return {"error": "Authentication required"}, 401
        from server.auth import verify_firebase_token
        firebase_user = verify_firebase_token(token)
        if firebase_user is None:
            return {"error": "Invalid or expired token"}, 401
        # Prevent impersonation — enforce matching UID
        if firebase_user["uid"] != user_id:
            return {"error": "Forbidden"}, 403

    try:
        sessions = await session_service.list_sessions(
            app_name="skincare_advisor",
            user_id=user_id,
        )

        session_list = []
        for s in (sessions or []):
            # Extract last message preview from session events
            last_message = ""
            message_count = 0
            if hasattr(s, "events") and s.events:
                for event in reversed(s.events):
                    message_count += 1
                    if hasattr(event, "content") and event.content:
                        for part in event.content.parts:
                            if hasattr(part, "text") and part.text:
                                last_message = part.text[:100]
                                break
                    if last_message:
                        break

            session_list.append({
                "session_id": s.id,
                "create_time": getattr(s, "create_time", None),
                "last_update_time": getattr(s, "last_update_time", None),
                "last_message": last_message or "Voice/image consultation",
                "message_count": message_count,
            })

        return {"sessions": session_list, "total": len(session_list)}

    except Exception as e:
        logger.error(f"Failed to list sessions for {user_id}: {e}")
        return {"sessions": [], "total": 0}


@web_app.post("/api/trigger-reminders")
async def trigger_reminders(data: dict = {}):
    """Trigger routine reminders and personalized product deals for all users.

    Designed to be called by Cloud Scheduler (or manually in dev).

    Body (optional):
        routine_type: "morning" | "evening"
        include_deals: true  — include personalized product discount notifications
        concerns: ["acne", "oily"]  — override skin concerns (otherwise read from session)
    """
    from server.notifications import (
        send_routine_reminder,
        send_product_discount,
    )

    routine_type = data.get("routine_type", "morning")
    include_deals = data.get("include_deals", True)
    override_concerns = data.get("concerns")  # optional manual override
    results = {"sent": 0, "failed": 0, "deals_sent": 0}

    for idx, (uid, token) in enumerate(fcm_tokens.items()):
        # Send routine reminder
        ok = await send_routine_reminder(token=token, routine_type=routine_type)
        if ok:
            results["sent"] += 1
        else:
            results["failed"] += 1

        # Send personalized product discount
        if include_deals:
            # Try to read user's skin concerns from their latest session
            user_concerns = override_concerns
            if not user_concerns:
                try:
                    sessions = await session_service.list_sessions(
                        app_name="skincare_advisor", user_id=uid,
                    )
                    if sessions:
                        latest = sessions[-1]
                        state = getattr(latest, "state", {}) or {}
                        # The agent stores skin analysis results in session state
                        analysis = state.get("latest_analysis", {})
                        if isinstance(analysis, dict):
                            user_concerns = analysis.get("concerns", [])
                        if not user_concerns:
                            user_concerns = state.get("skin_concerns", [])
                except Exception as e:
                    logger.debug(f"Could not read session for {uid}: {e}")

            deal_ok = await send_product_discount(
                token=token,
                concerns=user_concerns,
                deal_index=idx,
            )
            if deal_ok:
                results["deals_sent"] += 1

    logger.info(f"Trigger-reminders complete: {results}")
    return results


@web_app.websocket("/ws/{user_id}/{session_id}")
async def websocket_streaming(websocket: WebSocket, user_id: str, session_id: str):
    """WebSocket endpoint for Gemini Live API bidi-streaming.

    Handles real-time voice/video/text skincare consultations.
    Requires a valid Firebase Auth token (query param or header).

    Protocol (client → server):
    - Binary frames: Raw PCM audio bytes (16kHz, 16-bit, mono)
    - Text frames (JSON): {"type": "text", "text": "..."} for text messages
    - Text frames (JSON): {"type": "image", "data": "<base64>", "mimeType": "image/jpeg"}
    - Text frames (JSON): {"type": "end"} to close session

    Protocol (server → client):
    - Text frames: Full ADK event JSON via event.model_dump_json()
      - event.content.parts[].text → text responses
      - event.content.parts[].inline_data → audio responses (base64 PCM 24kHz)
      - event.input_transcription → user speech transcript
      - event.output_transcription → model speech transcript
    """
    # --- Phase 2: Firebase Auth ---
    firebase_user = await verify_websocket_token(websocket)
    if firebase_user is None:
        return  # Connection rejected (4001 sent by auth module)

    # Use Firebase UID as the user_id for session security
    # (ignore URL param — prevents impersonation)
    authenticated_user_id = firebase_user["uid"]

    await websocket.accept()
    logger.info(f"Session {session_id}: WebSocket connected for user {authenticated_user_id} ({firebase_user.get('email', '')})")

    # --- Phase 3: Session Initialization ---
    session = await session_service.get_session(
        app_name="skincare_advisor",
        user_id=authenticated_user_id,
        session_id=session_id,
    )
    if session is None:
        session = await session_service.create_session(
            app_name="skincare_advisor",
            user_id=authenticated_user_id,
            session_id=session_id,
        )
        logger.info(f"Session {session_id}: Created new session")
    else:
        logger.info(f"Session {session_id}: Resumed existing session")

    # Create LiveRequestQueue for this session (in async context per ADK best practice)
    live_request_queue = LiveRequestQueue()
    active_queues[session_id] = live_request_queue

    # Configure for bidi-streaming with audio + text responses
    # Per ADK docs: use StreamingMode.BIDI for bidirectional streaming
    run_config = RunConfig(
        response_modalities=["AUDIO"],
        streaming_mode=StreamingMode.BIDI,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name="Aoede",  # Friendly, warm voice
                )
            )
        ),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        max_llm_calls=500,
    )

    logger.info(f"Session {session_id}: User: {firebase_user.get('name', authenticated_user_id)}")

    # --- Phase 4: Bidi-Streaming ---
    async def upstream_task():
        """Receive messages from WebSocket and queue them for the agent.

        Per ADK docs (Part 2):
        - Text: use send_content(Content) for turn-by-turn messages
        - Audio: use send_realtime(Blob) for continuous PCM streaming
        - Images: use send_realtime(Blob) for JPEG frames
        - End: use close() for graceful termination
        """
        try:
            while True:
                # Use receive() to handle both binary and text frames
                message = await websocket.receive()

                if "bytes" in message:
                    # Binary frame = raw PCM audio (16kHz, 16-bit, mono)
                    # Per ADK docs: send audio via send_realtime(Blob)
                    audio_data = message["bytes"]
                    audio_blob = types.Blob(
                        mime_type="audio/pcm;rate=16000",
                        data=audio_data,
                    )
                    live_request_queue.send_realtime(audio_blob)

                elif "text" in message:
                    # Text frame = JSON message
                    text_data = message["text"]
                    try:
                        json_message = json.loads(text_data)
                    except json.JSONDecodeError:
                        logger.warning(f"Session {session_id}: Malformed JSON from client")
                        await websocket.send_text(json.dumps({
                            "error": "invalid_json",
                            "message": "Message must be valid JSON",
                        }))
                        continue

                    msg_type = json_message.get("type")
                    if not msg_type:
                        logger.warning(f"Session {session_id}: Missing 'type' field")
                        await websocket.send_text(json.dumps({
                            "error": "missing_type",
                            "message": "Message must include a 'type' field",
                        }))
                        continue

                    if msg_type == "text":
                        # Text message → send_content for turn-by-turn
                        user_text = json_message.get("text", "").strip()
                        if not user_text:
                            continue  # ignore empty messages

                        # ── Rate limiting ──
                        now = time.monotonic()
                        if session_id not in _rate_limits:
                            _rate_limits[session_id] = collections.deque()
                        q = _rate_limits[session_id]
                        # Purge old timestamps
                        while q and now - q[0] > _RATE_LIMIT_WINDOW:
                            q.popleft()
                        if len(q) >= _RATE_LIMIT_MAX_MESSAGES:
                            logger.warning(f"Session {session_id}: Rate limited")
                            await websocket.send_text(json.dumps({
                                "error": "rate_limited",
                                "message": f"Too many messages. Max {_RATE_LIMIT_MAX_MESSAGES} per {_RATE_LIMIT_WINDOW}s.",
                            }))
                            continue
                        q.append(now)

                        content = types.Content(
                            role="user",
                            parts=[types.Part(text=user_text)],
                        )
                        live_request_queue.send_content(content)

                    elif msg_type == "image":
                        # Image frame (base64 JPEG) → send_realtime(Blob)
                        # Per ADK docs: Do NOT use send_content with inline_data
                        raw_data = json_message.get("data")
                        if not raw_data:
                            continue  # ignore empty image frames
                        image_data = base64.b64decode(raw_data)
                        image_blob = types.Blob(
                            mime_type=json_message.get("mimeType", "image/jpeg"),
                            data=image_data,
                        )
                        live_request_queue.send_realtime(image_blob)

                    elif msg_type == "end":
                        # Client signals end of conversation
                        live_request_queue.close()
                        break

                    else:
                        logger.warning(f"Session {session_id}: Unknown type '{msg_type}'")
                        await websocket.send_text(json.dumps({
                            "error": "unknown_type",
                            "message": f"Unknown message type: {msg_type}",
                        }))

        except WebSocketDisconnect:
            logger.info(f"Session {session_id}: Client disconnected (upstream)")
        except Exception as e:
            logger.error(f"Session {session_id}: Upstream error: {e}")
            traceback.print_exc()

    async def downstream_task():
        """Stream agent responses back to WebSocket.

        Per ADK docs (Part 3):
        - Forward full ADK events as JSON using event.model_dump_json()
        - Events may contain: content (text/audio), transcription, turn signals
        """
        try:
            async for event in runner.run_live(
                user_id=authenticated_user_id,
                session_id=session_id,
                live_request_queue=live_request_queue,
                run_config=run_config,
            ):
                # Forward the full ADK event as JSON to the client.
                # This includes all event fields: content, transcription,
                # turn_complete, interrupted, etc.
                # Per ADK bidi-demo pattern: event.model_dump_json()
                event_json = event.model_dump_json(
                    exclude_none=True, by_alias=True
                )
                await websocket.send_text(event_json)

        except WebSocketDisconnect:
            logger.info(f"Session {session_id}: Client disconnected (downstream)")
        except Exception as e:
            logger.error(f"Session {session_id}: Downstream error: {e}", exc_info=True)
            # Notify client of the error before the connection closes
            try:
                await websocket.send_text(json.dumps({
                    "error": "server_error",
                    "message": "An internal error occurred. Please reconnect.",
                }))
            except Exception:
                pass  # Client may already be disconnected

    # Run upstream and downstream concurrently
    try:
        await asyncio.gather(upstream_task(), downstream_task())
    except Exception as e:
        logger.error(f"Session {session_id}: Session error: {e}", exc_info=True)
        try:
            await websocket.send_text(json.dumps({
                "error": "session_error",
                "message": "Session encountered an error. Please try again.",
            }))
        except Exception:
            pass
    finally:
        # --- Phase 5: Cleanup ---
        # Per ADK docs: Always close the queue to prevent zombie sessions
        live_request_queue.close()
        active_queues.pop(session_id, None)
        _rate_limits.pop(session_id, None)
        logger.info(f"Session {session_id}: Session cleaned up")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        web_app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8080)),
    )
