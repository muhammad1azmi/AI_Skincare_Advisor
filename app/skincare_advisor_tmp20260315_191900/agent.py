"""AI Skincare Advisor — Root Orchestrator Agent.

This is the main agent module for the AI Skincare Advisor multi-agent system.
It defines the root orchestrator that coordinates 8 specialist agents
via AgentTool wrappers (avoids Vertex AI mixed-tool-type errors).

Security layers (defense-in-depth):
1. Google Cloud Model Armor — ML-powered prompt/response sanitization
   (prompt injection, jailbreak, PII/SDP, harmful content, malicious URLs)
2. before_model_callback — domain-specific medical request blocking
3. after_model_callback — Model Armor response screening + medical logging
4. Built-in Gemini safety filters — configured in RunConfig (server/main.py)
5. Root prompt safety guardrails — explicit persona boundary instructions
"""

import os
import logging
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from google.adk.models import LlmResponse
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
    # Workflow agents (design pattern enhancements)
    parallel_ingredient_agent,
    consultation_pipeline_agent,
    routine_review_agent,
)
from .callbacks import generate_memories_callback

logger = logging.getLogger(__name__)

# Load root orchestrator prompt
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "prompts", "root_orchestrator.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _ROOT_INSTRUCTION = f.read()


# ─── Model Armor Integration ───
try:
    from skincare_advisor.model_armor import model_armor
except ImportError:
    try:
        from server.model_armor import model_armor
    except ImportError:
        # Graceful fallback if module not importable (e.g., during eval tests)
        model_armor = None
        logger.warning("Model Armor module not available — using basic guardrails only")

# ─── Medical Patterns ───
_MEDICAL_PATTERNS = [
    "prescribe me",
    "prescribe medication",
    "diagnose me",
    "give me a diagnosis",
    "what medication should",
    "what prescription",
    "write me a prescription",
    "prescribe a steroid",
    "prescribe antibiotic",
    "prescribe tretinoin",
    "write a prescription",
    "medical diagnosis for",
]


# ═══════════════════════════════════════════════════════════════
# INPUT GUARDRAIL — before_model_callback
# ═══════════════════════════════════════════════════════════════

def _safety_guardrail(callback_context, llm_request):
    """Multi-layer input screening via Model Armor + domain-specific checks.

    This before_model_callback implements defense-in-depth:
    1. Domain-specific: blocks explicit medical/prescription requests
    2. Model Armor: ML-powered detection for prompt injection, jailbreak,
       PII/sensitive data, harmful content, and malicious URLs

    Returns Content to block the request, or None to allow processing.
    """
    # Extract the last user message text
    try:
        last_content = llm_request.contents[-1] if llm_request.contents else None
        if last_content and last_content.parts:
            user_text = " ".join(
                part.text for part in last_content.parts
                if hasattr(part, "text") and part.text
            )
            user_text_lower = user_text.lower()
        else:
            return None
    except (IndexError, AttributeError):
        return None

    # ── Layer 1: Medical request detection (domain-specific) ──
    # Model Armor doesn't know about skincare-specific medical boundaries,
    # so this stays as a custom check.
    for pattern in _MEDICAL_PATTERNS:
        if pattern in user_text_lower:
            logger.warning(f"Safety guardrail: blocked medical request — pattern '{pattern}'")
            return types.Content(
                parts=[
                    types.Part(
                        text="I appreciate your trust, but I'm Glow — an AI skincare advisor, not a doctor. "
                        "I can't prescribe medications or provide medical diagnoses. "
                        "For medical concerns, please consult a healthcare professional or dermatologist. "
                        "I'm happy to help with general skincare advice, routines, and ingredient information! "
                        "What else can I help you with?"
                    )
                ]
            )

    # ── Layer 2: Model Armor — ML-powered sanitization ──
    # Replaces the old regex-based PII and injection detection with
    # Google-managed ML models for superior accuracy.
    if model_armor and model_armor.enabled:
        result = model_armor.sanitize_prompt(user_text)
        if result.is_blocked:
            logger.warning(
                f"Model Armor blocked prompt — reason: {result.blocked_reason}"
            )
            # Tailor the response based on what was detected
            if "Prompt injection" in result.blocked_reason:
                return types.Content(
                    parts=[
                        types.Part(
                            text="Hey! I'm Glow, your skincare advisor 😊 "
                            "I'm here to help with skincare questions — "
                            "routines, ingredients, skin concerns. "
                            "What would you like to know about your skin today?"
                        )
                    ]
                )
            elif "Sensitive data" in result.blocked_reason:
                return types.Content(
                    parts=[
                        types.Part(
                            text="⚠️ It looks like your message contains "
                            "sensitive personal information. For your privacy, "
                            "please don't share data like credit card numbers, "
                            "social security numbers, or passwords in our chat. "
                            "What skincare question can I help you with?"
                        )
                    ]
                )
            else:
                # Generic block for RAI violations, malicious URLs, etc.
                return types.Content(
                    parts=[
                        types.Part(
                            text="I wasn't able to process that message. "
                            "I'm here to help with skincare advice — "
                            "routines, ingredients, and skin concerns. "
                            "How can I help you today?"
                        )
                    ]
                )

    return None  # All checks passed — allow processing


# ═══════════════════════════════════════════════════════════════
# OUTPUT GUARDRAIL — after_model_callback
# ═══════════════════════════════════════════════════════════════

def _output_safety_check(callback_context, llm_response):
    """Screen AI output via Model Armor + domain-specific medical checks.

    This after_model_callback:
    1. Screens model output through Model Armor (PII leakage, harmful content)
    2. Logs if the model response contains medical-sounding language

    Returns None to allow the response as-is, or LlmResponse to replace it.
    """
    try:
        if not llm_response or not llm_response.content or not llm_response.content.parts:
            return None

        response_text = " ".join(
            part.text for part in llm_response.content.parts
            if hasattr(part, "text") and part.text
        )

        if not response_text.strip():
            return None

        # ── Layer 1: Model Armor response screening ──
        if model_armor and model_armor.enabled:
            result = model_armor.sanitize_response(response_text)
            if result.is_blocked:
                logger.warning(
                    f"Model Armor blocked response — "
                    f"reason: {result.blocked_reason}"
                )
                return LlmResponse(
                    content=types.Content(
                        parts=[
                            types.Part(
                                text="I want to make sure I give you safe "
                                "and helpful advice. Let me rephrase — "
                                "could you ask your question in a different "
                                "way so I can help you better with your "
                                "skincare needs?"
                            )
                        ]
                    )
                )

        # ── Layer 2: Medical language flagging (log only) ──
        response_text_lower = response_text.lower()
        medical_output_flags = [
            "i diagnose",
            "your diagnosis is",
            "you have been diagnosed",
            "take this medication",
            "prescription for",
        ]

        for flag in medical_output_flags:
            if flag in response_text_lower:
                logger.warning(
                    f"Output safety: model response contains "
                    f"medical language — '{flag}'"
                )
                break

    except Exception as e:
        logger.error(f"Output safety check error: {e}")

    return None  # Allow the response


# ─── Root Orchestrator Agent ───
# Using AgentTool instead of sub_agents to avoid Vertex AI's
# "Multiple tools are supported only when they are all search tools" error.
root_agent = Agent(
    name="skincare_advisor",
    model="gemini-2.5-flash",
    description="AI Skincare Advisor — Root Orchestrator. "
                "Routes user requests to specialized skincare agents for analysis, "
                "routine building, ingredient checking, and KOL content recommendations.",
    instruction=_ROOT_INSTRUCTION,
    # Gemini built-in safety filters — defense-in-depth layer
    generate_content_config=types.GenerateContentConfig(
        safety_settings=[
            types.SafetySetting(
                category="HARM_CATEGORY_DANGEROUS_CONTENT",
                threshold="BLOCK_MEDIUM_AND_ABOVE",
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_HARASSMENT",
                threshold="BLOCK_MEDIUM_AND_ABOVE",
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_HATE_SPEECH",
                threshold="BLOCK_MEDIUM_AND_ABOVE",
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_SEXUALLY_EXPLICIT",
                threshold="BLOCK_MEDIUM_AND_ABOVE",
            ),
        ],
    ),
    tools=[
        # Individual specialist agents (simple routing)
        AgentTool(agent=skin_analyzer_agent),
        AgentTool(agent=routine_builder_agent),
        AgentTool(agent=ingredient_checker_agent),
        AgentTool(agent=ingredient_interaction_agent),
        AgentTool(agent=skin_condition_agent),
        AgentTool(agent=qa_agent),
        AgentTool(agent=kol_content_agent),
        AgentTool(agent=progress_tracker_agent),
        # Workflow agents (composite design patterns)
        AgentTool(agent=parallel_ingredient_agent),
        AgentTool(agent=consultation_pipeline_agent),
        AgentTool(agent=routine_review_agent),
        # Memory Bank — retrieves user memories (skin type, preferences,
        # concerns, routine history) at the start of every turn
        PreloadMemoryTool(),
    ],
    before_model_callback=_safety_guardrail,
    after_model_callback=_output_safety_check,
    # Memory Bank — saves new memories (skin observations, user preferences)
    # after each agent turn for cross-session persistence
    after_agent_callback=generate_memories_callback,
)
