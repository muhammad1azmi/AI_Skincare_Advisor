"""Skin Analyzer Agent — uses Gemini Vision for real-time skin analysis."""

import os
from google.adk.agents import Agent
from ..tools.skin_tools import save_analysis_to_state

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "skin_analyzer.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

skin_analyzer_agent = Agent(
    name="skin_analyzer",
    model="gemini-2.5-flash",
    description="Analyzes skin conditions from video/images and user descriptions. "
                "Handles requests like 'look at my skin', 'what do you see?', "
                "skin concern analysis, and real-time video skin assessment.",
    instruction=_INSTRUCTION,
    tools=[save_analysis_to_state],
)
