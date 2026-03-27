"""Skin Condition Agent — uses Vertex AI Search on skin conditions database."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/skin-conditions_1772285802369"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "skin_condition.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

skin_condition_agent = Agent(
    name="skin_condition_agent",
    model="gemini-2.5-flash",
    description="Provides information about skin conditions, symptoms, triggers, "
                "and care guidelines. Handles questions like 'what is eczema?', "
                "'I have redness on my face', skin condition identification.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
    output_key="skin_condition_result",
)
