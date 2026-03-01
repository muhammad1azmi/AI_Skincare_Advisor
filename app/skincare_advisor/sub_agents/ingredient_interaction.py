"""Ingredient Interaction Agent — uses Vertex AI Search on ingredient interactions."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/test-first-bigquery-table_1772277060480"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "ingredient_interaction.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

ingredient_interaction_agent = Agent(
    name="ingredient_interaction_agent",
    model="gemini-2.5-flash",
    description="Checks ingredient compatibility and interactions. "
                "Handles questions like 'can I use retinol with vitamin C?', "
                "'will these products conflict?', ingredient mixing safety.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
)
