"""Agent factories — DRY creation of identical agent instances.

ADK enforces a single-parent rule: each agent instance can only belong
to one workflow parent. When the same specialist (e.g., routine_builder)
is needed in multiple workflows, we use factory functions here to create
fresh instances with the same configuration but unique names.

This keeps the configuration in ONE place while satisfying ADK's constraint.
"""

import os
from google.adk.agents import Agent
from google.adk.tools.vertex_ai_search_tool import VertexAiSearchTool

from ..tools.skin_tools import save_analysis_to_state

_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
_PROMPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "prompts")

# ─── Datastore IDs (single source of truth) ───
DATASTORES = {
    "ingredients": f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/skincare-ingredients_1772285876335",
    "interactions": f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/test-first-bigquery-table_1772277060480",
    "skin_conditions": f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/skin-conditions_1772285802369",
    "routines": f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/routine-templates_1772285770039",
    "kol_content": f"projects/{_PROJECT_ID}/locations/global/collections/default_collection/dataStores/kol-content_1772297553445",
}


def _load_prompt(filename: str) -> str:
    with open(os.path.join(_PROMPTS_DIR, filename), "r", encoding="utf-8") as f:
        return f.read()


# ─── Factory functions ───

def create_skin_analyzer(name: str = "skin_analyzer", **overrides) -> Agent:
    """Create a skin analyzer agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Analyzes skin conditions from video/images and user descriptions.",
        instruction=_load_prompt("skin_analyzer.txt"),
        tools=[save_analysis_to_state],
        **overrides,
    )


def create_skin_condition(name: str = "skin_condition", **overrides) -> Agent:
    """Create a skin condition agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Provides information about skin conditions, symptoms, triggers, and care.",
        instruction=_load_prompt("skin_condition.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["skin_conditions"], bypass_multi_tools_limit=True)],
        **overrides,
    )


def create_routine_builder(name: str = "routine_builder", **overrides) -> Agent:
    """Create a routine builder agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Builds personalized morning and evening skincare routines.",
        instruction=_load_prompt("routine_builder.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["routines"], bypass_multi_tools_limit=True)],
        **overrides,
    )


def create_ingredient_checker(name: str = "ingredient_checker", **overrides) -> Agent:
    """Create an ingredient checker agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Analyzes skincare ingredients for safety, efficacy, and suitability.",
        instruction=_load_prompt("ingredient_checker.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["ingredients"], bypass_multi_tools_limit=True)],
        **overrides,
    )


def create_ingredient_interaction(name: str = "ingredient_interaction", **overrides) -> Agent:
    """Create an ingredient interaction agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Checks ingredient compatibility and interactions.",
        instruction=_load_prompt("ingredient_interaction.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["interactions"], bypass_multi_tools_limit=True)],
        **overrides,
    )


def create_kol_content(name: str = "kol_content", **overrides) -> Agent:
    """Create a KOL content agent instance."""
    return Agent(
        name=name,
        model="gemini-2.5-flash",
        description="Finds relevant KOL and influencer skincare videos.",
        instruction=_load_prompt("kol_content.txt"),
        tools=[VertexAiSearchTool(data_store_id=DATASTORES["kol_content"], bypass_multi_tools_limit=True)],
        **overrides,
    )
