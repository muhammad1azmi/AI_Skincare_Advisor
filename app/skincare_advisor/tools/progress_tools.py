"""Custom tools for progress tracking — session state based."""

from datetime import datetime, timezone


def save_progress_note(
    observations: str,
    improvements: list[str],
    concerns_remaining: list[str],
    routine_changes: str,
    tool_context: "ToolContext",
) -> dict:
    """Records a progress observation for the user's skincare journey.

    Args:
        observations: Current skin observations and notes.
        improvements: List of improvements noticed since last check.
        concerns_remaining: List of concerns that still need attention.
        routine_changes: Any changes made to the skincare routine since last check.
        tool_context: ADK ToolContext (injected automatically).

    Returns:
        dict: Confirmation with progress note count.
    """
    note = {
        "observations": observations,
        "improvements": improvements,
        "concerns_remaining": concerns_remaining,
        "routine_changes": routine_changes,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    history = tool_context.state.get("progress_history", [])
    history.append(note)
    tool_context.state["progress_history"] = history

    return {
        "status": "saved",
        "message": f"Progress note #{len(history)} recorded.",
        "total_notes": len(history),
    }


def get_progress_history(tool_context: "ToolContext") -> dict:
    """Retrieves the user's complete skincare progress history from session state.

    Args:
        tool_context: ADK ToolContext (injected automatically).

    Returns:
        dict: Progress history with all recorded notes and analyses.
    """
    progress_history = tool_context.state.get("progress_history", [])
    skin_history = tool_context.state.get("skin_analysis_history", [])
    latest_analysis = tool_context.state.get("latest_analysis", None)

    if not progress_history and not skin_history:
        return {
            "status": "no_history",
            "message": "No progress data recorded yet. This appears to be your first visit!",
        }

    return {
        "status": "found",
        "progress_notes": progress_history,
        "skin_analyses": skin_history,
        "latest_analysis": latest_analysis,
        "total_check_ins": len(progress_history) + len(skin_history),
    }
