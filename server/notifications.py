"""Push notification service — Firebase Cloud Messaging (FCM).

Sends push notifications to registered devices for:
- Skincare routine reminders (morning/evening)
- Follow-up consultation nudges
- New product/ingredient alerts
"""

import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)


def _init_firebase():
    """Ensure Firebase Admin SDK is initialized."""
    import firebase_admin
    try:
        firebase_admin.get_app()
    except ValueError:
        project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
        firebase_admin.initialize_app(options={"projectId": project_id})


async def send_notification(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send a push notification to a single device.

    Args:
        token: FCM device token.
        title: Notification title.
        body: Notification body text.
        data: Optional data payload for the app.

    Returns:
        True if sent successfully, False otherwise.
    """
    _init_firebase()
    from firebase_admin import messaging

    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=data or {},
        token=token,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                icon="notification_icon",
                color="#6C63FF",
                channel_id="skincare_reminders",
            ),
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    badge=1,
                    sound="default",
                ),
            ),
        ),
    )

    try:
        response = messaging.send(message)
        logger.info(f"Notification sent: {response}")
        return True
    except messaging.UnregisteredError:
        logger.warning(f"Device token unregistered: {token[:20]}...")
        return False
    except Exception as e:
        logger.error(f"Failed to send notification: {e}")
        return False


async def send_routine_reminder(
    token: str,
    routine_type: str = "morning",
) -> bool:
    """Send a skincare routine reminder.

    Args:
        token: FCM device token.
        routine_type: "morning" or "evening".
    """
    if routine_type == "morning":
        title = "☀️ Morning Routine Reminder"
        body = "Time to start your morning skincare routine! Your skin will thank you."
    else:
        title = "🌙 Evening Routine Reminder"
        body = "Don't forget your evening skincare routine before bed!"

    return await send_notification(
        token=token,
        title=title,
        body=body,
        data={"type": "routine_reminder", "routine": routine_type},
    )


async def send_followup_nudge(token: str) -> bool:
    """Send a consultation follow-up nudge."""
    return await send_notification(
        token=token,
        title="💬 How's your skin doing?",
        body="It's been a while since your last consultation. Want to check in with your advisor?",
        data={"type": "followup", "action": "open_consultation"},
    )
