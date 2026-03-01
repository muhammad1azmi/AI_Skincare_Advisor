"""AI Skincare Advisor — FastAPI + WebSocket Streaming Server.

This server implements the ADK Gemini Live API Bidi-Streaming lifecycle
for real-time voice/video skincare consultations.

Security:
- Firebase Auth JWT verification on WebSocket connections
- CORS restricted to allowed origins only
- No secrets in code (all from env vars)
- Non-root container user (Dockerfile)
- VertexAiSessionService for persistent, managed sessions

4-Phase Lifecycle:
1. App Init — Create Agent, SessionService, Runner
2. Auth — Verify Firebase JWT on WebSocket connect
3. Session Init — Create/get session, RunConfig, LiveRequestQueue
4. Bidi-Streaming — Concurrent upstream/downstream WebSocket tasks
5. Cleanup — Close queue on disconnect
"""

import asyncio
import base64
import json
import os
import traceback

from dotenv import load_dotenv

# Load environment variables (local dev only; Cloud Run uses --set-env-vars)
_root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(_root_dir, ".env"))
load_dotenv(os.path.join(_root_dir, "app", ".env"))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from google.adk.runners import Runner
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.sessions import VertexAiSessionService
from google.adk.agents.live_request_queue import LiveRequestQueue
from google.genai import types

# Import the root agent and auth module
import sys
sys.path.insert(0, os.path.join(_root_dir, "app"))
from skincare_advisor.agent import root_agent
from server.auth import verify_websocket_token

# --- Phase 1: App Initialization ---
app = FastAPI(
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)

# Session service — Vertex AI Agent Engine managed sessions
session_service = VertexAiSessionService(
    project=os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2"),
    location=os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1"),
    agent_engine_id=os.environ.get("AGENT_ENGINE_ID"),
)

# Runner manages agent execution
runner = Runner(
    agent=root_agent,
    app_name="skincare_advisor",
    session_service=session_service,
)

# Track active streaming sessions
active_queues: dict[str, LiveRequestQueue] = {}

# In-memory storage for FCM tokens (use Firestore in production)
fcm_tokens: dict[str, str] = {}  # user_id -> fcm_token


@app.get("/")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "app": "AI Skincare Advisor",
        "version": "1.0.0",
        "agents": [
            "skincare_advisor (root)",
            "skin_analyzer",
            "routine_builder",
            "ingredient_checker",
            "ingredient_interaction_agent",
            "skin_condition_agent",
            "qa_agent",
            "kol_content_agent",
            "progress_tracker",
        ],
    }


@app.post("/api/register-token")
async def register_fcm_token(data: dict):
    """Register a device FCM token for push notifications.

    Body: {"user_id": "...", "token": "..."}
    """
    user_id = data.get("user_id")
    token = data.get("token")
    if not user_id or not token:
        return {"error": "user_id and token required"}, 400
    fcm_tokens[user_id] = token
    print(f"[FCM] Registered token for user {user_id}")
    return {"status": "ok"}


@app.post("/api/send-notification")
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


@app.websocket("/ws/{user_id}/{session_id}")
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
    print(f"[Session {session_id}] WebSocket connected for user {authenticated_user_id} ({firebase_user.get('email', '')})")

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
        print(f"[Session {session_id}] Created new session")
    else:
        print(f"[Session {session_id}] Resumed existing session")

    # Create LiveRequestQueue for this session (in async context per ADK best practice)
    live_request_queue = LiveRequestQueue()
    active_queues[session_id] = live_request_queue

    # Configure for bidi-streaming with audio + text responses
    # Per ADK docs: use StreamingMode.BIDI for bidirectional streaming
    run_config = RunConfig(
        response_modalities=["AUDIO", "TEXT"],
        streaming_mode=StreamingMode.BIDI,
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name="Aoede",  # Friendly, warm voice
                )
            )
        ),
    )

    print(f"[Session {session_id}] User: {firebase_user.get('name', authenticated_user_id)}")

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
                    json_message = json.loads(text_data)

                    if json_message.get("type") == "text":
                        # Text message → send_content for turn-by-turn
                        content = types.Content(
                            role="user",
                            parts=[types.Part(text=json_message["text"])],
                        )
                        live_request_queue.send_content(content)

                    elif json_message.get("type") == "image":
                        # Image frame (base64 JPEG) → send_realtime(Blob)
                        # Per ADK docs: Do NOT use send_content with inline_data
                        image_data = base64.b64decode(json_message["data"])
                        image_blob = types.Blob(
                            mime_type=json_message.get("mimeType", "image/jpeg"),
                            data=image_data,
                        )
                        live_request_queue.send_realtime(image_blob)

                    elif json_message.get("type") == "end":
                        # Client signals end of conversation
                        live_request_queue.close()
                        break

        except WebSocketDisconnect:
            print(f"[Session {session_id}] Client disconnected (upstream)")
        except Exception as e:
            print(f"[Session {session_id}] Upstream error: {e}")
            traceback.print_exc()

    async def downstream_task():
        """Stream agent responses back to WebSocket.

        Per ADK docs (Part 3):
        - Forward full ADK events as JSON using event.model_dump_json()
        - Events may contain: content (text/audio), transcription, turn signals
        """
        try:
            async for event in runner.run_live(
                session=session,
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
            print(f"[Session {session_id}] Client disconnected (downstream)")
        except Exception as e:
            print(f"[Session {session_id}] Downstream error: {e}")
            traceback.print_exc()

    # Run upstream and downstream concurrently
    try:
        await asyncio.gather(upstream_task(), downstream_task())
    except Exception as e:
        print(f"[Session {session_id}] Session error: {e}")
    finally:
        # --- Phase 5: Cleanup ---
        # Per ADK docs: Always close the queue to prevent zombie sessions
        live_request_queue.close()
        active_queues.pop(session_id, None)
        print(f"[Session {session_id}] Session cleaned up")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8080)),
    )
