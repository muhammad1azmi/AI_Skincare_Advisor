"""Routine Builder Agent — uses Vertex AI Search on routine templates."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/routine-templates_1772285770039"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "routine_builder.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

routine_builder_agent = Agent(
    name="routine_builder",
    model="gemini-2.5-flash",
    description="Builds personalized morning and evening skincare routines. "
                "Handles requests like 'build me a routine', 'morning skincare', "
                "'what should I apply?', routine customization and product layering.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
    output_key="current_routine",
)
