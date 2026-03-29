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

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from starlette.requests import Request

from google.adk.apps import App
from google.adk.runners import Runner
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
from server.auth import verify_websocket_token, verify_firebase_token

# --- Structured Logging ---
_LOG_DIR = os.path.join(_root_dir, "logs")
os.makedirs(_LOG_DIR, exist_ok=True)

_log_format = '{"time":"%(asctime)s","level":"%(levelname)s","module":"%(module)s","message":"%(message)s"}'

# Console handler
_console_handler = logging.StreamHandler()
_console_handler.setLevel(logging.INFO)
_console_handler.setFormatter(logging.Formatter(_log_format))

# File handler — rotating, 5MB max, keep last 3 files
from logging.handlers import RotatingFileHandler
_file_handler = RotatingFileHandler(
    os.path.join(_LOG_DIR, "server.log"),
    maxBytes=5 * 1024 * 1024,  # 5 MB
    backupCount=3,
    encoding="utf-8",
)
_file_handler.setLevel(logging.INFO)  # Only meaningful events in file
_file_handler.setFormatter(logging.Formatter(_log_format))

# Root logger config
logging.basicConfig(level=logging.INFO, handlers=[_console_handler, _file_handler])
logger = logging.getLogger("skincare_advisor")

# Silence noisy ADK & library modules that flood logs with raw audio blobs
for _noisy in [
    "base_llm_flow", "audio_cache_manager", "gemini_llm_connection",
    "protocol", "connection", "connectionpool", "retry", "_channel",
    "proactor_events", "google_llm",
]:
    logging.getLogger(_noisy).setLevel(logging.WARNING)

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


# ─── Security Headers Middleware ───
# Protects against XSS, clickjacking, MIME sniffing, and downgrade attacks.
@web_app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    return response


# ─── SKIP_AUTH Production Safety Net ───
# Prevents accidental auth bypass in non-dev environments (e.g. Cloud Run).
_ENV = os.environ.get("ENV", "dev")
_SKIP_AUTH = os.environ.get("SKIP_AUTH", "").lower() == "true"

if _SKIP_AUTH and _ENV != "dev":
    logger.critical(
        "SECURITY: SKIP_AUTH=true is FORBIDDEN in non-dev environments. "
        "Forcing authentication ON."
    )
    os.environ["SKIP_AUTH"] = "false"


# ─── REST Endpoint Auth Dependency ───
async def require_auth(authorization: str = Header(None)) -> dict:
    """FastAPI dependency — requires a valid Firebase JWT.

    Extracts the Bearer token from the Authorization header,
    verifies it via Firebase Admin SDK, and returns the decoded user.
    Raises HTTPException(401) on failure.
    """
    if os.environ.get("SKIP_AUTH", "").lower() == "true":
        return {"uid": "local_dev_user", "email": "dev@local"}

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")

    token = authorization[7:]
    user = verify_firebase_token(token)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return user

# --- BigQuery Agent Analytics Plugin ---
from server.config import PROJECT_ID as _PROJECT_ID, LOCATION as _LOCATION

bq_config = BigQueryLoggerConfig(
    enabled=True,
    gcs_bucket_name=os.environ.get("GCS_BUCKET_NAME"),
    log_multi_modal_content=True,
    max_content_length=500 * 1024,  # 500 KB limit for inline text
    batch_size=1,                   # Low latency (increase for high throughput)
    shutdown_timeout=10.0,
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

# ADK App with BigQuery Analytics plugin
adk_app = App(
    name="skincare_advisor",
    root_agent=root_agent,
    plugins=[bq_plugin],
)

# Runner with session/memory services (these moved from App to Runner in ADK v1.x)
runner = Runner(
    app_name="skincare_advisor",
    agent=root_agent,
    plugins=[bq_plugin],
    session_service=session_service,
    memory_service=memory_service,
)

# Live Runner — MUST use InMemorySessionService.
# VertexAiSessionService's agent_engines.sessions.events API is incompatible
# with run_live() and causes the live stream to close immediately.
live_session_service = InMemorySessionService()
live_runner = Runner(
    app_name="skincare_advisor",
    agent=root_agent,
    plugins=[bq_plugin],
    session_service=live_session_service,
    memory_service=memory_service,
)

logger.info("ADK Runner initialized with BigQuery Agent Analytics plugin")

# Track active streaming sessions
active_queues: dict[str, LiveRequestQueue] = {}

# Rate limiting: per-session message tracking
# { session_id: deque of timestamps }
_rate_limits: dict[str, collections.deque] = {}
_RATE_LIMIT_WINDOW = 60  # seconds
_RATE_LIMIT_MAX_MESSAGES = 30  # max text messages per window

# ─── Payload Size Limits ───
# Prevent memory exhaustion and abuse via oversized payloads.
_MAX_TEXT_LENGTH = 5_000           # max chars per text message
_MAX_IMAGE_B64_SIZE = 10_000_000   # ~10 MB base64 ≈ 7.5 MB decoded
_MAX_AUDIO_CHUNK_SIZE = 1_000_000  # ~1 MB PCM ≈ 30s at 16kHz/16-bit
_ALLOWED_IMAGE_MIMES = {"image/jpeg", "image/png", "image/webp"}

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
    """Minimal health check — no internal architecture details exposed."""
    return {
        "status": "healthy",
        "app": "AI Skincare Advisor",
        "version": "1.0.0",
    }


@web_app.post("/api/register-token")
async def register_fcm_token(data: dict, user: dict = Depends(require_auth)):
    """Register a device FCM token for push notifications.

    Body: {"user_id": "...", "token": "..."}
    Requires: Authorization: Bearer <firebase_jwt>
    """
    user_id = data.get("user_id")
    token = data.get("token")
    if not user_id or not token:
        raise HTTPException(status_code=400, detail="user_id and token required")
    # Users can only register tokens for themselves
    if user["uid"] != user_id:
        raise HTTPException(status_code=403, detail="Cannot register token for another user")
    fcm_tokens[user_id] = token
    logger.info(f"FCM token registered for user {user_id}")
    return {"status": "ok"}


@web_app.post("/api/send-notification")
async def send_push_notification(data: dict, user: dict = Depends(require_auth)):
    """Send a push notification to a user.

    Body: {"user_id": "...", "title": "...", "body": "...", "data": {...}}
    Requires: Authorization: Bearer <firebase_jwt>
    Users can only send notifications to themselves.
    """
    from server.notifications import send_notification

    user_id = data.get("user_id")
    # Users can only send notifications to themselves
    if user["uid"] != user_id:
        raise HTTPException(status_code=403, detail="Cannot send notifications to another user")
    token = fcm_tokens.get(user_id)
    if not token:
        raise HTTPException(status_code=404, detail="No FCM token registered for user")

    result = await send_notification(
        token=token,
        title=data.get("title", "AI Skincare Advisor"),
        body=data.get("body", ""),
        data=data.get("data"),
    )
    return {"status": "sent" if result else "failed"}


@web_app.get("/api/sessions/{user_id}")
async def list_user_sessions(user_id: str, user: dict = Depends(require_auth)):
    """List all past sessions for a user.

    Requires: Authorization: Bearer <firebase_jwt>
    Users can only list their own sessions.
    """
    if user["uid"] != user_id:
        raise HTTPException(status_code=403, detail="Cannot access another user's sessions")

    try:
        sessions = await session_service.list_sessions(
            app_name="skincare_advisor",
            user_id=user_id,
        )

        session_list = []
        for s in (sessions or []):
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
async def trigger_reminders(data: dict = {}, user: dict = Depends(require_auth)):
    """Trigger routine reminders and personalized product deals for all users.

    Admin-only endpoint — only the app owner can trigger mass notifications.
    Requires: Authorization: Bearer <firebase_jwt>
    """
    # Admin check: restrict to specific admin UID(s)
    _ADMIN_UIDS = os.environ.get("ADMIN_UIDS", "").split(",")
    if user["uid"] not in _ADMIN_UIDS and _ADMIN_UIDS != [""]:
        raise HTTPException(status_code=403, detail="Admin access required")
    from server.notifications import (
        send_routine_reminder,
        send_product_discount,
    )

    routine_type = data.get("routine_type", "morning")
    include_deals = data.get("include_deals", True)
    override_concerns = data.get("concerns")
    results = {"sent": 0, "failed": 0, "deals_sent": 0}

    for idx, (uid, token) in enumerate(fcm_tokens.items()):
        ok = await send_routine_reminder(token=token, routine_type=routine_type)
        if ok:
            results["sent"] += 1
        else:
            results["failed"] += 1

        if include_deals:
            user_concerns = override_concerns
            if not user_concerns:
                try:
                    sessions = await session_service.list_sessions(
                        app_name="skincare_advisor", user_id=uid,
                    )
                    if sessions:
                        latest = sessions[-1]
                        state = getattr(latest, "state", {}) or {}
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


@web_app.websocket("/ws-test")
async def websocket_test(websocket: WebSocket):
    """Minimal WebSocket echo endpoint for infra testing."""
    await websocket.accept()
    logger.info("ws-test: connection accepted")
    try:
        while True:
            data = await websocket.receive_text()
            logger.info(f"ws-test: got '{data}'")
            await websocket.send_text(f"echo: {data}")
    except WebSocketDisconnect:
        logger.info("ws-test: client disconnected")
    except Exception as e:
        logger.error(f"ws-test: error {e}")


@web_app.websocket("/ws/{user_id}/{session_id}")
async def websocket_streaming(websocket: WebSocket, user_id: str, session_id: str):
    """WebSocket endpoint for Gemini Live API bidi-streaming."""
    # --- Phase 2: Firebase Auth ---
    logger.info(f"Session {session_id}: WS handler entered, checking auth...")
    firebase_user = await verify_websocket_token(websocket)
    if firebase_user is None:
        logger.warning(f"Session {session_id}: Auth failed, rejecting")
        return

    authenticated_user_id = firebase_user["uid"]

    # ─── User ID Path Enforcement ───
    # Prevent authenticated user A from connecting to /ws/userB/session.
    # The URL path user_id MUST match the JWT uid.
    if authenticated_user_id != user_id and os.environ.get("SKIP_AUTH", "").lower() != "true":
        logger.warning(
            f"Session {session_id}: UID MISMATCH — "
            f"path={user_id} jwt={authenticated_user_id}. Rejecting."
        )
        await websocket.accept()
        await websocket.close(code=4003, reason="User ID mismatch")
        return

    logger.info(f"Session {session_id}: Auth OK for {authenticated_user_id}, accepting WebSocket...")
    await websocket.accept()
    logger.info(f"Session {session_id}: WebSocket accepted for user {authenticated_user_id}")

    # Send immediate status to client
    try:
        await websocket.send_text(json.dumps({"type": "status", "message": "Connected. Initializing session..."}))
    except Exception:
        pass

    # Top-level try/except to catch ANY crash after accept
    try:
        # --- Phase 3: Session Initialization ---
        # Live sessions use InMemorySessionService (VertexAiSessionService is
        # incompatible with run_live — its events.list() API blocks the stream).
        logger.info(f"Session {session_id}: Creating InMemory live session...")
        try:
            session = await asyncio.wait_for(
                live_session_service.create_session(
                    app_name="skincare_advisor",
                    user_id=authenticated_user_id,
                ),
                timeout=30,
            )
            # Use the auto-generated session ID for all subsequent operations
            actual_session_id = session.id
            logger.info(f"Session {session_id}: Created live session {actual_session_id}")
        except asyncio.TimeoutError:
            logger.error(f"Session {session_id}: Session service timed out (30s)")
            await websocket.send_text(json.dumps({"error": "session_timeout", "message": "Session service timed out"}))
            await websocket.close(code=1011, reason="Session service timeout")
            return
        except Exception as e:
            logger.error(f"Session {session_id}: Session init failed: {traceback.format_exc()}")
            await websocket.send_text(json.dumps({"error": "session_error", "message": str(e)}))
            await websocket.close(code=1011, reason=f"Session error: {e}")
            return

        live_request_queue = LiveRequestQueue()
        active_queues[session_id] = live_request_queue

        run_config = RunConfig(
            response_modalities=["AUDIO"],
            streaming_mode=StreamingMode.BIDI,
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Aoede")
                )
            ),
            input_audio_transcription=types.AudioTranscriptionConfig(),
            output_audio_transcription=types.AudioTranscriptionConfig(),
            max_llm_calls=50,
        )

        logger.info(f"Session {session_id}: Connecting to Gemini Live, model={root_agent.model}")
        await websocket.send_text(json.dumps({"type": "status", "message": "Connecting to Glow..."}))

        # Send a minimal greeting prompt so the agent speaks first.
        # Keep it SHORT so the model just says hi without calling tools.
        greeting_content = types.Content(
            role="user",
            parts=[types.Part(text="Hi!")],
        )
        live_request_queue.send_content(greeting_content)

        # --- Phase 4: Bidi-Streaming ---
        async def upstream_task():
            audio_chunk_count = 0
            try:
                while True:
                    message = await websocket.receive()
                    if "bytes" in message:
                        # ── Audio size validation ──
                        if len(message["bytes"]) > _MAX_AUDIO_CHUNK_SIZE:
                            logger.warning(f"Session {session_id}: Oversized audio chunk ({len(message['bytes'])} bytes), dropping")
                            continue
                        audio_chunk_count += 1
                        if audio_chunk_count <= 3:
                            logger.debug(f"Audio chunk #{audio_chunk_count} size={len(message['bytes'])} bytes")
                        audio_blob = types.Blob(mime_type="audio/pcm;rate=16000", data=message["bytes"])
                        live_request_queue.send_realtime(audio_blob)
                    elif "text" in message:
                        try:
                            json_message = json.loads(message["text"])
                        except json.JSONDecodeError:
                            continue
                        msg_type = json_message.get("type")
                        if msg_type == "text":
                            user_text = json_message.get("text", "").strip()
                            if not user_text:
                                continue
                            # ── Text length validation ──
                            if len(user_text) > _MAX_TEXT_LENGTH:
                                await websocket.send_text(json.dumps({"error": "message_too_long", "max": _MAX_TEXT_LENGTH}))
                                continue
                            now = time.monotonic()
                            if session_id not in _rate_limits:
                                _rate_limits[session_id] = collections.deque()
                            q = _rate_limits[session_id]
                            while q and now - q[0] > _RATE_LIMIT_WINDOW:
                                q.popleft()
                            if len(q) >= _RATE_LIMIT_MAX_MESSAGES:
                                await websocket.send_text(json.dumps({"error": "rate_limited"}))
                                continue
                            q.append(now)
                            content = types.Content(role="user", parts=[types.Part(text=user_text)])
                            live_request_queue.send_content(content)
                        elif msg_type == "image":
                            raw_data = json_message.get("data")
                            if raw_data:
                                # ── Image size validation ──
                                if len(raw_data) > _MAX_IMAGE_B64_SIZE:
                                    await websocket.send_text(json.dumps({"error": "image_too_large", "max_mb": 10}))
                                    continue
                                # ── Image MIME type validation ──
                                mime = json_message.get("mimeType", "image/jpeg")
                                if mime not in _ALLOWED_IMAGE_MIMES:
                                    await websocket.send_text(json.dumps({"error": "unsupported_image_type", "allowed": list(_ALLOWED_IMAGE_MIMES)}))
                                    continue
                                image_blob = types.Blob(
                                    mime_type=mime,
                                    data=base64.b64decode(raw_data),
                                )
                                live_request_queue.send_realtime(image_blob)
                        elif msg_type == "end":
                            live_request_queue.close()
                            break
                    elif message.get("type") == "websocket.disconnect":
                        live_request_queue.close()
                        break
            except WebSocketDisconnect:
                logger.info(f"Session {session_id}: Client disconnected (upstream)")
            except Exception as e:
                logger.error(f"Session {session_id}: Upstream error: {traceback.format_exc()}")

        async def downstream_task():
            try:
                logger.debug(f"Starting run_live model={root_agent.model} user={authenticated_user_id} session={actual_session_id}")
                event_count = 0
                session_ready_sent = False
                async for event in live_runner.run_live(
                    user_id=authenticated_user_id,
                    session_id=actual_session_id,
                    live_request_queue=live_request_queue,
                    run_config=run_config,
                ):
                    event_count += 1
                    if event_count <= 3:
                        logger.debug(f"Event #{event_count} content={'yes' if event.content else 'no'} partial={getattr(event, 'partial', None)} transcription_in={event.input_transcription is not None} transcription_out={event.output_transcription is not None}")

                    # Send "Session ready" only once Gemini is actually responding
                    if not session_ready_sent:
                        session_ready_sent = True
                        await websocket.send_text(json.dumps({"type": "status", "message": "Session ready. Start speaking!"}))
                        logger.info(f"Session {session_id}: Gemini connected, first event received")
                    # ── Forward sub-agent tool events to the Flutter client ──
                    # These let the client show "Analyzing ingredients..." and
                    # display detailed text results from sub-agent tools.
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            if part.function_call:
                                logger.info(
                                    f"Session {session_id}: Tool call → "
                                    f"{part.function_call.name}({part.function_call.args})"
                                )
                                await websocket.send_text(json.dumps({
                                    "toolEvent": "call",
                                    "toolName": part.function_call.name,
                                }))
                            elif part.function_response:
                                # Extract the text result from the sub-agent
                                result = part.function_response.response
                                result_text = ""
                                if isinstance(result, dict):
                                    result_text = result.get("result", str(result))
                                elif isinstance(result, str):
                                    result_text = result
                                else:
                                    result_text = str(result)
                                logger.info(
                                    f"Session {session_id}: Tool result ← "
                                    f"{part.function_response.name} "
                                    f"({len(result_text)} chars)"
                                )
                                await websocket.send_text(json.dumps({
                                    "toolEvent": "result",
                                    "toolName": part.function_response.name,
                                    "toolResult": result_text,
                                }))

                    # Split audio (binary frames) from non-audio (JSON text frames).
                    # This avoids base64 encoding overhead for audio data.
                    sent_audio = False
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            if (part.inline_data
                                    and part.inline_data.mime_type
                                    and part.inline_data.mime_type.startswith("audio/")):
                                # Send raw PCM bytes as binary WebSocket frame
                                await websocket.send_bytes(part.inline_data.data)
                                sent_audio = True

                    # For non-audio events (transcription, text, turn_complete, etc.)
                    # or events that have BOTH audio and text content, send JSON.
                    # We strip inline_data from JSON to avoid double-sending audio.
                    if not sent_audio:
                        event_json = event.model_dump_json(exclude_none=True, by_alias=True)
                        await websocket.send_text(event_json)
                    else:
                        # Audio was sent as binary. Also check for transcription/turn_complete
                        # in the same event and send those as JSON separately.
                        has_transcription = (event.input_transcription is not None
                                             or event.output_transcription is not None)
                        has_turn_complete = getattr(event, 'turn_complete', False)
                        if has_transcription or has_turn_complete:
                            # Build a minimal JSON with just the non-audio fields
                            meta = {}
                            if event.input_transcription is not None:
                                meta["inputTranscription"] = {
                                    "text": event.input_transcription.text,
                                    "finished": event.input_transcription.finished,
                                }
                            if event.output_transcription is not None:
                                meta["outputTranscription"] = {
                                    "text": event.output_transcription.text,
                                    "finished": event.output_transcription.finished,
                                }
                            if has_turn_complete:
                                meta["turnComplete"] = True
                            await websocket.send_text(json.dumps(meta))

                logger.debug(f"run_live loop ended after {event_count} events")
            except WebSocketDisconnect:
                logger.info(f"Session {session_id}: Client disconnected (downstream)")
            except Exception as e:
                logger.error(f"Session {session_id}: DOWNSTREAM ERROR: {traceback.format_exc()}")
                try:
                    await websocket.send_text(json.dumps({"error": "server_error", "message": str(e)}))
                except Exception:
                    pass

        try:
            await asyncio.gather(upstream_task(), downstream_task())
        except Exception as e:
            logger.error(f"Session {session_id}: gather error: {traceback.format_exc()}")
        finally:
            live_request_queue.close()
            active_queues.pop(session_id, None)
            _rate_limits.pop(session_id, None)
            logger.info(f"Session {session_id}: Session cleaned up")

    except Exception as e:
        # Catch-all: log full traceback for ANY unhandled crash after accept
        logger.error(f"Session {session_id}: FATAL ERROR: {traceback.format_exc()}")
        try:
            await websocket.send_text(json.dumps({"error": "fatal", "message": str(e)}))
            await websocket.close(code=1011, reason="Internal server error")
        except Exception:
            pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        web_app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8080)),
        # Increase WebSocket keepalive timeouts so long-running tool calls
        # (e.g. routine_review_agent taking 30-60s) don't trigger
        # "keepalive ping timeout" errors on the client connection.
        ws_ping_interval=30,   # Send a ping every 30s (default: 20s)
        ws_ping_timeout=120,   # Wait up to 120s for pong (default: 20s)
    )
