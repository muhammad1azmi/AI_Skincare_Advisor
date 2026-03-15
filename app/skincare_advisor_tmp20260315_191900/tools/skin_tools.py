"""Custom tools for skin analysis — session state based."""

import json
from datetime import datetime, timezone
from google.adk.tools import FunctionTool
from google.adk.tools.tool_context import ToolContext


def save_analysis_to_state(
    concerns: list[str],
    severity: str,
    observations: str,
    recommendations: list[str],
    tool_context: "ToolContext",
) -> dict:
    """Saves a skin analysis result to the session state for progress tracking.

    Args:
        concerns: List of identified skin concerns (e.g., ["dryness", "acne", "redness"]).
        severity: Overall severity assessment — "mild", "moderate", or "consult-dermatologist".
        observations: Detailed text observations about the skin condition.
        recommendations: List of recommended actions or products.
        tool_context: ADK ToolContext (injected automatically).

    Returns:
        dict: Confirmation of saved analysis.
    """
    analysis = {
        "concerns": concerns,
        "severity": severity,
        "observations": observations,
        "recommendations": recommendations,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    # Store in session state
    history = tool_context.state.get("skin_analysis_history", [])
    history.append(analysis)
    tool_context.state["skin_analysis_history"] = history
    tool_context.state["latest_analysis"] = analysis

    return {
        "status": "saved",
        "message": f"Analysis saved with {len(concerns)} concerns identified.",
        "severity": severity,
    }
