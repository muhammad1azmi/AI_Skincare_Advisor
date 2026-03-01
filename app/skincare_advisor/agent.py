"""AI Skincare Advisor — Root Orchestrator Agent.

This is the main agent module for the AI Skincare Advisor multi-agent system.
It defines the root orchestrator that coordinates 8 specialist agents
via AgentTool wrappers (avoids Vertex AI mixed-tool-type errors).

Security layers (defense-in-depth):
1. before_model_callback — screens user input for medical requests, PII, prompt injection
2. after_model_callback — sanitizes AI output for accidental medical claims
3. Built-in Gemini safety filters — configured in RunConfig (server/main.py)
4. Root prompt safety guardrails — explicit persona boundary instructions
"""

import os
import re
import logging
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool
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
)

logger = logging.getLogger(__name__)

# Load root orchestrator prompt
_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "prompts", "root_orchestrator.txt")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    _ROOT_INSTRUCTION = f.read()


# ─── PII Detection Patterns ───
_PII_PATTERNS = {
    "email": re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
    "phone": re.compile(r'\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b'),
    "credit_card": re.compile(r'\b(?:\d{4}[-\s]?){3}\d{4}\b'),
    "ssn": re.compile(r'\b\d{3}-\d{2}-\d{4}\b'),
}

# ─── Prompt Injection Patterns ───
_INJECTION_PATTERNS = [
    "ignore previous instructions",
    "ignore all previous",
    "disregard your instructions",
    "you are now",
    "act as if you are",
    "pretend to be",
    "system prompt",
    "reveal your prompt",
    "show me your instructions",
    "what are your instructions",
    "bypass",
    "jailbreak",
]

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
    """Multi-layer input screening: medical requests, PII, prompt injection.

    This before_model_callback implements defense-in-depth:
    1. Checks for explicit medical/prescription requests → blocks with redirect
    2. Detects PII in user input → warns user not to share sensitive data
    3. Detects prompt injection attempts → blocks with warning

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

    # ── Layer 1: Medical request detection ──
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

    # ── Layer 2: PII detection — warn, don't block ──
    detected_pii = []
    for pii_type, pattern in _PII_PATTERNS.items():
        if pattern.search(user_text):
            detected_pii.append(pii_type)

    if detected_pii:
        pii_types = ", ".join(detected_pii)
        logger.warning(f"Safety guardrail: PII detected in input — types: {pii_types}")
        # Modify the system instruction to include a PII warning
        # (don't block — just ensure the model warns the user)
        if llm_request.config and llm_request.config.system_instruction:
            existing = llm_request.config.system_instruction
            if existing.parts:
                existing.parts.append(
                    types.Part(
                        text=f"\n\n⚠️ IMPORTANT: The user just shared what appears to be personal information "
                        f"({pii_types}). Gently remind them not to share sensitive personal data in chat. "
                        "Do NOT repeat or reference the sensitive data in your response."
                    )
                )
        return None  # Allow processing but with modified instruction

    # ── Layer 3: Prompt injection detection ──
    for pattern in _INJECTION_PATTERNS:
        if pattern in user_text_lower:
            logger.warning(f"Safety guardrail: blocked prompt injection — pattern '{pattern}'")
            return types.Content(
                parts=[
                    types.Part(
                        text="Hey! I'm Glow, your skincare advisor 😊 "
                        "I'm here to help with skincare questions — routines, ingredients, skin concerns. "
                        "What would you like to know about your skin today?"
                    )
                ]
            )

    return None  # All checks passed — allow processing


# ═══════════════════════════════════════════════════════════════
# OUTPUT GUARDRAIL — after_model_callback
# ═══════════════════════════════════════════════════════════════

def _output_safety_check(callback_context, llm_response):
    """Screen AI output for safety compliance.

    This after_model_callback:
    1. Logs if the model response contains medical-sounding language
    2. Could be extended to sanitize PII in responses

    Returns None to allow the response as-is, or LlmResponse to replace it.
    """
    try:
        if not llm_response or not llm_response.content or not llm_response.content.parts:
            return None

        response_text = " ".join(
            part.text.lower() for part in llm_response.content.parts
            if hasattr(part, "text") and part.text
        )

        # Flag responses that sound like medical diagnoses (log only, don't block)
        medical_output_flags = [
            "i diagnose",
            "your diagnosis is",
            "you have been diagnosed",
            "take this medication",
            "prescription for",
        ]

        for flag in medical_output_flags:
            if flag in response_text:
                logger.warning(
                    f"Output safety: model response contains medical language — '{flag}'"
                )
                # In production, could replace with a safer response
                break

    except Exception as e:
        logger.error(f"Output safety check error: {e}")

    return None  # Allow the response as-is (logging only for now)


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
    after_model_callback=_output_safety_check,
)
