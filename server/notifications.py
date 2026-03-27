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
        from server.config import PROJECT_ID
        project_id = PROJECT_ID
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


async def send_progress_milestone(token: str, total_notes: int) -> bool:
    """Send a congratulatory notification when a progress milestone is reached.

    Args:
        token: FCM device token.
        total_notes: Total number of progress notes recorded.
    """
    milestones = {
        3: ("🎯 3rd Check-in!", "You're building a great skincare habit! Keep tracking your progress."),
        5: ("⭐ 5 Check-ins!", "Amazing consistency! Your skin journey is on the right track."),
        10: ("🏆 10 Check-ins!", "Incredible dedication! You're a skincare pro. Check your progress timeline!"),
        25: ("💎 25 Check-ins!", "Outstanding commitment! Your skin has come a long way. Review your transformation!"),
    }

    title, body = milestones.get(
        total_notes,
        (f"📊 Check-in #{total_notes}", "Great job keeping up with your skincare tracking!"),
    )

    return await send_notification(
        token=token,
        title=title,
        body=body,
        data={"type": "progress_milestone", "total_notes": str(total_notes)},
    )


async def send_product_discount(
    token: str,
    concerns: list[str] | None = None,
    deal_index: int = 0,
) -> bool:
    """Send a personalized product discount notification.

    Matches products from the catalog to the user's skin concerns.
    Notifications include a buy_url for direct e-commerce purchase.

    Args:
        token: FCM device token.
        concerns: User's skin concerns (e.g., ["acne", "oily"]).
            If None, sends a universally relevant product.
        deal_index: Offset into matched products list.

    Returns:
        True if sent successfully, False otherwise.
    """
    from server.product_catalog import (
        get_products_for_concerns,
        format_product_for_notification,
    )

    # Get personalized product recommendations
    products = get_products_for_concerns(
        concerns=concerns or [],
        limit=5,
    )

    if not products:
        logger.warning("No products matched user concerns")
        return False

    # Pick one product (cycling through matches)
    product = products[deal_index % len(products)]
    notif = format_product_for_notification(product)

    return await send_notification(
        token=token,
        title=notif["title"],
        body=notif["body"],
        data=notif["data"],
    )

