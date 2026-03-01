"""Q&A Agent — uses Vertex AI Search on skincare education database."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/skincare-education_1772285841134"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "qa_agent.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

qa_agent = Agent(
    name="qa_agent",
    model="gemini-2.5-flash",
    description="Answers general skincare education questions with evidence-based information. "
                "Handles questions like 'what does hyaluronic acid do?', 'is sunscreen necessary?', "
                "skincare myths, science, and general knowledge.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
)
