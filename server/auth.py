"""Firebase Auth verification for WebSocket connections.

Verifies Firebase ID tokens on WebSocket connect to authenticate users.
On Cloud Run, uses Application Default Credentials automatically.
In local dev, set SKIP_AUTH=true in .env to bypass.
"""

import os
import logging
from typing import Optional

from fastapi import WebSocket

logger = logging.getLogger(__name__)

# Email allowlist — only these users can connect.
# Set via ALLOWED_EMAILS env var (comma-separated) or defaults below.
_ALLOWED_EMAILS = os.environ.get(
    "ALLOWED_EMAILS",
    "muhammad@borobudur.ai",
).lower().split(",")

# Lazy-init Firebase Admin SDK
_firebase_app = None


def _init_firebase():
    """Initialize Firebase Admin SDK (once)."""
    global _firebase_app
    if _firebase_app is not None:
        return

    import firebase_admin
    from firebase_admin import credentials

    # On Cloud Run: auto-discovers credentials via metadata server
    # Locally: uses GOOGLE_APPLICATION_CREDENTIALS or gcloud ADC
    project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
    try:
        _firebase_app = firebase_admin.initialize_app(
            options={"projectId": project_id}
        )
        logger.info(f"Firebase Admin SDK initialized for project: {project_id}")
    except ValueError:
        # Already initialized
        _firebase_app = firebase_admin.get_app()


def verify_firebase_token(id_token: str) -> Optional[dict]:
    """Verify a Firebase ID token and return decoded claims.

    Returns:
        dict with uid, email, etc. on success, None on failure.
    """
    _init_firebase()

    from firebase_admin import auth

    try:
        decoded = auth.verify_id_token(id_token, check_revoked=True)
        user_email = decoded.get("email", "").lower()

        # Check email allowlist
        if user_email not in _ALLOWED_EMAILS:
            logger.warning(f"Access denied for email: {user_email}")
            return None

        return {
            "uid": decoded["uid"],
            "email": user_email,
            "name": decoded.get("name", ""),
            "email_verified": decoded.get("email_verified", False),
        }
    except auth.RevokedIdTokenError:
        logger.warning("Firebase token has been revoked")
        return None
    except auth.ExpiredIdTokenError:
        logger.warning("Firebase token has expired")
        return None
    except auth.InvalidIdTokenError as e:
        logger.warning(f"Invalid Firebase token: {e}")
        return None
    except Exception as e:
        logger.error(f"Firebase token verification error: {e}")
        return None


async def verify_websocket_token(websocket: WebSocket) -> Optional[dict]:
    """Extract and verify Firebase token from WebSocket connection.

    Token can be provided via:
    1. Query parameter: ws://host/ws/uid/sid?token=<JWT>
    2. Authorization header: Bearer <JWT> (set during upgrade)

    In local dev with SKIP_AUTH=true, returns a mock user.

    Returns:
        User dict on success, None on failure (connection accepted then
        closed with code 4001 so the client gets a proper close frame).
    """
    # Skip auth in local dev
    if os.environ.get("SKIP_AUTH", "").lower() == "true":
        logger.info("Auth skipped (SKIP_AUTH=true)")
        return {"uid": "local_dev_user", "email": "dev@local", "name": "Dev User", "email_verified": True}

    # Try query parameter first (mobile apps often use this for WebSocket)
    token = websocket.query_params.get("token")

    # Fall back to Authorization header
    if not token:
        auth_header = websocket.headers.get("authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]

    if not token:
        logger.warning("No auth token provided")
        await websocket.accept()
        await websocket.close(code=4001, reason="Authentication required")
        return None

    # Verify the token
    user = verify_firebase_token(token)
    if user is None:
        await websocket.accept()
        await websocket.close(code=4001, reason="Invalid or expired token")
        return None

    logger.info(f"Authenticated user: {user['uid']} ({user.get('email', 'no email')})")
    return user
