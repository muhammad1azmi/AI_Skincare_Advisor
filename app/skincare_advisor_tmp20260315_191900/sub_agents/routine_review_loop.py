"""Routine Review Loop — critic/refiner loop for routine safety validation.

Uses ADK LoopAgent to iteratively review and refine skincare routines
before they reach the user. The critic validates against safety criteria,
and the refiner applies fixes or exits the loop when approved.

Architecture:
    SequentialAgent [
        routine_builder (→ state: current_routine),
        LoopAgent (max 3 iterations) [
            RoutineCriticAgent (→ state: routine_criticism),
            RoutineRefinerAgent (updates state: current_routine, or exit_loop),
        ]
    ]
"""

import os
from google.adk.agents import Agent, LoopAgent
from google.adk.agents.sequential_agent import SequentialAgent
from google.adk.tools.tool_context import ToolContext

from .agent_factories import create_routine_builder

_PROMPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "prompts")


def _load_prompt(filename: str) -> str:
    with open(os.path.join(_PROMPTS_DIR, filename), "r", encoding="utf-8") as f:
        return f.read()


# ─── Exit loop tool ───
def exit_loop(tool_context: ToolContext):
    """Call this function ONLY when the critique indicates the routine is
    approved and no further changes are needed."""
    tool_context.actions.escalate = True
    return {}


# ─── Review Loop ───
_routine_review_loop = LoopAgent(
    name="routine_review_loop",
    sub_agents=[
        Agent(
            name="routine_critic",
            model="gemini-2.5-flash",
            description="Reviews a skincare routine for safety issues.",
            instruction=_load_prompt("routine_critic.txt"),
            include_contents="none",
            output_key="routine_criticism",
        ),
        Agent(
            name="routine_refiner",
            model="gemini-2.5-flash",
            description="Applies critic feedback or calls exit_loop if approved.",
            instruction=_load_prompt("routine_refiner.txt"),
            include_contents="none",
            tools=[exit_loop],
            output_key="current_routine",
        ),
    ],
    max_iterations=3,
)

# ─── Full reviewed routine pipeline ───
# Dedicated routine_builder instance (ADK single-parent rule)
routine_review_agent = SequentialAgent(
    name="routine_review_agent",
    sub_agents=[
        create_routine_builder("review_routine_builder", output_key="current_routine"),
        _routine_review_loop,
    ],
    description="Builds a personalized skincare routine and then validates it "
                "through a safety review loop that checks for ingredient conflicts, "
                "missing SPF, wrong step order, and other safety issues. "
                "Use when the user asks for a routine and safety is important "
                "(e.g., sensitive skin, acne-prone skin, complex multi-step routines).",
)
