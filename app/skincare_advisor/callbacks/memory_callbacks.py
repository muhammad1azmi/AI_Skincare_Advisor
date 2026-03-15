"""Memory Bank callbacks — extracts long-term memories after each agent turn.

Uses Vertex AI Memory Bank via ADK's CallbackContext to persist user
preferences, skin type, concerns, routine history etc. across sessions.

Docs:
- https://cloud.google.com/agent-builder/agent-engine/memory-bank/quickstart-adk
- https://google.github.io/adk-docs/sessions/memory/
"""

import logging
from google.adk.agents.callback_context import CallbackContext

logger = logging.getLogger(__name__)


async def generate_memories_callback(callback_context: CallbackContext):
    """After-agent callback that sends recent events to Memory Bank.

    Uses add_events_to_memory (incremental) instead of add_session_to_memory
    (full session) to minimize re-processing of already-seen events.

    Per Google's recommendation:
    - add_events_to_memory: ideal for incremental processing (each turn)
    - add_session_to_memory: only call at end of session to avoid re-processing

    The Memory Bank LLM will automatically:
    - Extract meaningful info (skin type, preferences, concerns, routines)
    - Consolidate with existing memories (update, not duplicate)
    - Ignore non-informative turns
    """
    try:
        # Send the last few events (current turn) for memory extraction
        recent_events = callback_context.session.events[-5:-1]
        if recent_events:
            await callback_context.add_events_to_memory(events=recent_events)
            logger.debug(
                "Memory Bank: sent %d events for memory generation",
                len(recent_events),
            )
    except Exception as e:
        # Memory generation is best-effort — never block the agent response
        logger.warning("Memory Bank: failed to generate memories — %s", e)

    return None
