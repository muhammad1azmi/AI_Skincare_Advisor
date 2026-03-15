"""Parallel Ingredient Check — runs safety + interaction checks concurrently.

Uses ADK ParallelAgent to fan out to ingredient_checker and
ingredient_interaction_agent simultaneously, then a synthesis agent
merges the results into a single cohesive response.

Architecture:
    SequentialAgent [
        ParallelAgent [ingredient_checker ‖ ingredient_interaction],
        IngredientSynthesisAgent (merges results from state)
    ]
"""

import os
from google.adk.agents import Agent
from google.adk.agents.parallel_agent import ParallelAgent
from google.adk.agents.sequential_agent import SequentialAgent

from .agent_factories import create_ingredient_checker, create_ingredient_interaction

_PROMPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "prompts")
with open(os.path.join(_PROMPTS_DIR, "ingredient_synthesis.txt"), "r", encoding="utf-8") as f:
    _SYNTHESIS_INSTRUCTION = f.read()


# Dedicated instances for this workflow (ADK single-parent rule)
_parallel_check = ParallelAgent(
    name="parallel_ingredient_check",
    sub_agents=[
        create_ingredient_checker("par_ingredient_checker", output_key="ingredient_safety_result"),
        create_ingredient_interaction("par_ingredient_interaction", output_key="ingredient_interaction_result"),
    ],
    description="Runs ingredient safety and interaction checks concurrently.",
)

_synthesis_agent = Agent(
    name="ingredient_synthesis",
    model="gemini-2.5-flash",
    description="Merges parallel ingredient safety and interaction results "
                "into a single cohesive response.",
    instruction=_SYNTHESIS_INSTRUCTION,
)

parallel_ingredient_agent = SequentialAgent(
    name="parallel_ingredient_agent",
    sub_agents=[_parallel_check, _synthesis_agent],
    description="Comprehensive ingredient analysis that checks safety AND "
                "interactions in parallel, then synthesizes into one response. "
                "Use when the user asks about an ingredient's safety AND its "
                "compatibility with other ingredients simultaneously.",
)
