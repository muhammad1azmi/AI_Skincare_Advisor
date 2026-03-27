"""KOL Content Agent — uses Vertex AI Search on KOL Google Sheets data."""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
_DATASTORE_ID = f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/kol-content_1772297553445"

# Load prompt from file
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "prompts", "kol_content.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _INSTRUCTION = f.read()

kol_content_agent = Agent(
    name="kol_content_agent",
    model="gemini-2.5-flash",
    description="Finds relevant KOL (Key Opinion Leader) and influencer skincare videos. "
                "Provides video URLs and content recommendations from trusted skincare creators "
                "matching the user's specific concerns and topics.",
    instruction=_INSTRUCTION,
    tools=[VertexAiSearchTool(data_store_id=_DATASTORE_ID, bypass_multi_tools_limit=True)],
)
