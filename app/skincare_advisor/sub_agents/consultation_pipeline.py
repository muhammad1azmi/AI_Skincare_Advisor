"""Full Consultation Pipeline — sequential skin analysis → condition → routine → KOL.

Uses ADK SequentialAgent to chain specialist agents in a fixed order where
each step builds on the previous one's output via session state.

Architecture:
    SequentialAgent [
        skin_analyzer (→ state: skin_analysis_result)
        skin_condition (→ state: skin_condition_result)
        routine_builder (→ state: current_routine)
        consultation_synthesis (merges all state into cohesive summary)
        kol_content_agent (finds relevant KOL videos based on all findings)
    ]
"""

import os
from google.adk.agents import Agent
from google.adk.agents.sequential_agent import SequentialAgent

from .agent_factories import (
    create_skin_analyzer,
    create_skin_condition,
    create_routine_builder,
    create_kol_content,
)

_PROMPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "prompts")
with open(os.path.join(_PROMPTS_DIR, "consultation_synthesis.txt"), "r", encoding="utf-8") as f:
    _SYNTHESIS_INSTRUCTION = f.read()


# Dedicated instances for this pipeline (ADK single-parent rule)
consultation_pipeline_agent = SequentialAgent(
    name="consultation_pipeline_agent",
    sub_agents=[
        create_skin_analyzer("pipe_skin_analyzer", output_key="skin_analysis_result"),
        create_skin_condition("pipe_skin_condition", output_key="skin_condition_result"),
        create_routine_builder("pipe_routine_builder", output_key="current_routine"),
        Agent(
            name="consultation_synthesis",
            model="gemini-2.5-flash",
            description="Synthesizes skin analysis, condition, and routine into a cohesive summary.",
            instruction=_SYNTHESIS_INSTRUCTION,
            output_key="consultation_summary",
        ),
        create_kol_content("pipe_kol_content"),
    ],
    description="Full skincare consultation pipeline. Analyzes skin, assesses "
                "conditions, builds a personalized routine, synthesizes findings, "
                "and recommends relevant KOL content. Use when the user requests "
                "a comprehensive consultation or says 'analyze everything'.",
)
