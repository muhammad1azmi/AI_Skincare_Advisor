"""Progress Tracker Agent — uses custom session state tools."""

import os
from google.adk.agents import Agent
from ..tools.progress_tools import save_progress_note, get_progress_history

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "progress_tracker.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

progress_tracker_agent = Agent(
    name="progress_tracker",
    model="gemini-2.5-flash",
    description="Tracks skincare progress over time. Compares current skin state "
                "against historical observations, identifies trends, and suggests "
                "routine adjustments based on progress.",
    instruction=_INSTRUCTION,
    tools=[save_progress_note, get_progress_history],
)
