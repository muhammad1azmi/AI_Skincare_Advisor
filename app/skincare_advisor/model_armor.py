"""Model Armor — Google Cloud managed AI safety & security layer.

This module wraps the Model Armor Python SDK to provide prompt and
response sanitization for the AI Skincare Advisor.

Filters enabled (configured via gcloud template):
- Responsible AI (hate speech, harassment, sexually explicit, dangerous)
- Prompt injection & jailbreak detection
- Sensitive Data Protection (PII: credit cards, SSN, API keys, etc.)
- Malicious URI detection
- CSAM (always-on)

Usage:
    from server.model_armor import model_armor

    result = model_armor.sanitize_prompt("user input text")
    if result.is_blocked:
        # Block the request
        print(result.blocked_reason)

Environment variables:
    GOOGLE_CLOUD_PROJECT      — GCP project ID (required)
    MODEL_ARMOR_LOCATION      — Region (default: us-central1)
    MODEL_ARMOR_TEMPLATE_ID   — Template ID created via gcloud
"""

import logging
import os
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger("skincare_advisor.model_armor")


@dataclass
class SanitizationResult:
    """Result from a Model Armor sanitization call."""

    is_blocked: bool = False
    match_state: str = "NO_MATCH_FOUND"
    blocked_reason: str = ""
    details: dict = field(default_factory=dict)
    error: Optional[str] = None


class ModelArmorService:
    """Wraps the Model Armor Python SDK for prompt/response sanitization.

    Designed for fail-open behavior: if Model Armor is unavailable or
    misconfigured, requests pass through with a warning log — never
    silently blocking all users.
    """

    def __init__(self):
        self._client = None
        self._template_name = None
        self._enabled = False
        self._initialize()

    def _initialize(self):
        """Lazily initialize the Model Armor client."""
        template_id = os.environ.get("MODEL_ARMOR_TEMPLATE_ID")
        if not template_id:
            logger.warning(
                "MODEL_ARMOR_TEMPLATE_ID not set — Model Armor disabled. "
                "Falling back to regex-only guardrails."
            )
            return

        project_id = os.environ.get(
            "GOOGLE_CLOUD_PROJECT", ""
        )
        location_id = os.environ.get("MODEL_ARMOR_LOCATION", "us-central1")

        self._template_name = (
            f"projects/{project_id}/locations/{location_id}"
            f"/templates/{template_id}"
        )

        try:
            from google.api_core.client_options import ClientOptions
            from google.cloud import modelarmor_v1

            self._client = modelarmor_v1.ModelArmorClient(
                transport="rest",
                client_options=ClientOptions(
                    api_endpoint=(
                        f"modelarmor.{location_id}.rep.googleapis.com"
                    )
                ),
            )
            self._enabled = True
            logger.info(
                f"Model Armor initialized — template: {self._template_name}"
            )
        except Exception as e:
            logger.error(f"Failed to initialize Model Armor client: {e}")
            self._enabled = False

    @property
    def enabled(self) -> bool:
        """Whether Model Armor is active and ready."""
        return self._enabled

    def sanitize_prompt(self, text: str) -> SanitizationResult:
        """Screen user input through Model Armor filters.

        Args:
            text: The raw user prompt text (latest message only).

        Returns:
            SanitizationResult with is_blocked=True if any filter matched.
        """
        if not self._enabled:
            return SanitizationResult()  # Pass through

        try:
            from google.cloud import modelarmor_v1

            request = modelarmor_v1.SanitizeUserPromptRequest(
                name=self._template_name,
                user_prompt_data=modelarmor_v1.DataItem(text=text),
            )
            response = self._client.sanitize_user_prompt(request=request)
            return self._parse_result(response.sanitization_result)

        except Exception as e:
            logger.error(f"Model Armor sanitize_prompt failed: {e}")
            # Fail-open: allow the request but log the error
            return SanitizationResult(error=str(e))

    def sanitize_response(self, text: str) -> SanitizationResult:
        """Screen model output through Model Armor filters.

        Args:
            text: The model response text to sanitize.

        Returns:
            SanitizationResult with is_blocked=True if any filter matched.
        """
        if not self._enabled:
            return SanitizationResult()  # Pass through

        try:
            from google.cloud import modelarmor_v1

            request = modelarmor_v1.SanitizeModelResponseRequest(
                name=self._template_name,
                model_response_data=modelarmor_v1.DataItem(text=text),
            )
            response = self._client.sanitize_model_response(request=request)
            return self._parse_result(response.sanitization_result)

        except Exception as e:
            logger.error(f"Model Armor sanitize_response failed: {e}")
            return SanitizationResult(error=str(e))

    @staticmethod
    def _parse_result(sanitization_result) -> SanitizationResult:
        """Parse the raw Model Armor API response into a clean result."""
        match_state = str(sanitization_result.filter_match_state)
        is_blocked = "MATCH_FOUND" in match_state

        # Build human-readable details from each filter
        details = {}
        blocked_reasons = []

        for filter_name, filter_result in (
            sanitization_result.filter_results.items()
        ):
            # Each filter result has a specific sub-field
            if hasattr(filter_result, "rai_filter_result"):
                rai = filter_result.rai_filter_result
                rai_state = str(rai.match_state)
                details["rai"] = {"match_state": rai_state}
                if "MATCH_FOUND" in rai_state:
                    # Collect which RAI categories matched
                    matched_cats = []
                    for cat_name, cat_result in (
                        rai.rai_filter_type_results.items()
                    ):
                        cat_state = str(cat_result.match_state)
                        if "MATCH_FOUND" in cat_state:
                            matched_cats.append(cat_name)
                    details["rai"]["matched_categories"] = matched_cats
                    blocked_reasons.append(
                        f"Harmful content detected: "
                        f"{', '.join(matched_cats)}"
                    )

            if hasattr(filter_result, "pi_and_jailbreak_filter_result"):
                pj = filter_result.pi_and_jailbreak_filter_result
                pj_state = str(pj.match_state)
                details["pi_and_jailbreak"] = {"match_state": pj_state}
                if "MATCH_FOUND" in pj_state:
                    blocked_reasons.append(
                        "Prompt injection or jailbreak attempt detected"
                    )

            if hasattr(filter_result, "sdp_filter_result"):
                sdp = filter_result.sdp_filter_result
                if hasattr(sdp, "inspect_result") and sdp.inspect_result:
                    sdp_state = str(sdp.inspect_result.match_state)
                    details["sdp"] = {"match_state": sdp_state}
                    if "MATCH_FOUND" in sdp_state:
                        # Extract detected info types
                        info_types = []
                        if hasattr(sdp.inspect_result, "findings"):
                            for finding in sdp.inspect_result.findings:
                                if hasattr(finding, "info_type"):
                                    info_types.append(finding.info_type)
                        details["sdp"]["info_types"] = info_types
                        blocked_reasons.append(
                            "Sensitive data detected (PII)"
                        )

            if hasattr(filter_result, "malicious_uri_filter_result"):
                uri = filter_result.malicious_uri_filter_result
                uri_state = str(uri.match_state)
                details["malicious_uris"] = {"match_state": uri_state}
                if "MATCH_FOUND" in uri_state:
                    blocked_reasons.append("Malicious URL detected")

            if hasattr(filter_result, "csam_filter_filter_result"):
                csam = filter_result.csam_filter_filter_result
                csam_state = str(csam.match_state)
                details["csam"] = {"match_state": csam_state}
                if "MATCH_FOUND" in csam_state:
                    blocked_reasons.append("CSAM content detected")

        blocked_reason = "; ".join(blocked_reasons) if blocked_reasons else ""

        if is_blocked:
            logger.warning(
                f"Model Armor BLOCKED — reason: {blocked_reason}, "
                f"details: {details}"
            )
        else:
            logger.debug(f"Model Armor PASSED — details: {details}")

        return SanitizationResult(
            is_blocked=is_blocked,
            match_state=match_state,
            blocked_reason=blocked_reason,
            details=details,
        )


# ── Module-level singleton ──
# Initialized once when the server starts; reused across all requests.
model_armor = ModelArmorService()
