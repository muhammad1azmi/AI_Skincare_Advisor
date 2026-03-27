"""Ingredient Checker Agent — uses Vertex AI Search on ingredient database."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/skincare-ingredients_1772285876335"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "ingredient_checker.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

ingredient_checker_agent = Agent(
    name="ingredient_checker",
    model="gemini-2.5-flash",
    description="Analyzes skincare ingredients for safety, efficacy, and suitability. "
                "Handles questions like 'is this ingredient safe?', 'what does retinol do?', "
                "product ingredient analysis, and comedogenicity checks.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
    output_key="ingredient_safety_result",
)
