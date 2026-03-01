"""AI Skincare Advisor — Root Orchestrator Agent.

This is the main agent module for the AI Skincare Advisor multi-agent system.
It defines the root orchestrator that coordinates 8 specialist agents
via AgentTool wrappers (avoids Vertex AI mixed-tool-type errors).
"""

import os
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool
from google.genai import types

# Import all specialist agents
from .sub_agents import (
    skin_analyzer_agent,
    routine_builder_agent,
    ingredient_checker_agent,
    ingredient_interaction_agent,
    skin_condition_agent,
    qa_agent,
    kol_content_agent,
    progress_tracker_agent,
)

# Load root orchestrator prompt
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "prompts", "root_orchestrator.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _ROOT_INSTRUCTION = f.read()


# --- Safety Callback ---
def _safety_guardrail(
    callback_context,
    llm_request,
):
    """Screen user inputs for medical diagnosis requests.

    This before_model_callback checks if the user is asking for medical diagnoses
    or prescription recommendations, which are outside the agent's scope.
    """
    # Extract the last user message text
    try:
        last_content = llm_request.contents[-1] if llm_request.contents else None
        if last_content and last_content.parts:
            user_text = " ".join(
                part.text.lower() for part in last_content.parts if hasattr(part, "text") and part.text
            )
        else:
            return None
    except (IndexError, AttributeError):
        return None

    # Check for explicit medical request patterns
    medical_patterns = [
        "prescribe me",
        "prescribe medication",
        "diagnose me",
        "give me a diagnosis",
        "what medication should",
        "what prescription",
        "write me a prescription",
    ]

    for pattern in medical_patterns:
        if pattern in user_text:
            return types.Content(
                parts=[
                    types.Part(
                        text="I appreciate your trust, but I'm an AI skincare advisor — not a doctor or dermatologist. "
                        "I can't prescribe medications or provide medical diagnoses. "
                        "For medical concerns, please consult a healthcare professional or dermatologist. "
                        "I'm happy to help with general skincare advice, routines, and ingredient information though! "
                        "What else can I help you with?"
                    )
                ]
            )

    return None  # Allow processing


# --- Root Orchestrator Agent ---
# Using AgentTool instead of sub_agents to avoid Vertex AI's
# "Multiple tools are supported only when they are all search tools" error.
# sub_agents auto-adds transfer_to_agent (function tools) which conflicts
# with VertexAiSearchTool (search tools) in the specialist agents.
# AgentTool wraps each specialist as a function call, keeping their
# internal tools isolated.
root_agent = Agent(
    name="skincare_advisor",
    model="gemini-2.5-flash",
    description="AI Skincare Advisor — Root Orchestrator. "
                "Routes user requests to specialized skincare agents for analysis, "
                "routine building, ingredient checking, and KOL content recommendations.",
    instruction=_ROOT_INSTRUCTION,
    tools=[
        AgentTool(agent=skin_analyzer_agent),
        AgentTool(agent=routine_builder_agent),
        AgentTool(agent=ingredient_checker_agent),
        AgentTool(agent=ingredient_interaction_agent),
        AgentTool(agent=skin_condition_agent),
        AgentTool(agent=qa_agent),
        AgentTool(agent=kol_content_agent),
        AgentTool(agent=progress_tracker_agent),
    ],
    before_model_callback=_safety_guardrail,
)

