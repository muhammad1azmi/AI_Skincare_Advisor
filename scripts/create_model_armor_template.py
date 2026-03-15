"""Create a Model Armor template for the AI Skincare Advisor.

Filters:
  - RAI: Hate speech, Harassment, Dangerous, Sexually Explicit (all HIGH)
  - Prompt Injection & Jailbreak: ENABLED (LOW_AND_ABOVE)
  - Malicious URIs: ENABLED
  - Sensitive Data Protection (SDP): ENABLED (basic config)

Usage:
    python scripts/create_model_armor_template.py
"""

import os
import sys

from dotenv import load_dotenv

_root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(_root_dir, "app", ".env"))

PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
LOCATION_ID = os.environ.get("MODEL_ARMOR_LOCATION", "us-central1")
TEMPLATE_ID = "skincare-advisor-safety"


def main():
    from google.api_core.client_options import ClientOptions
    from google.cloud import modelarmor_v1

    # Create the Model Armor client
    client = modelarmor_v1.ModelArmorClient(
        transport="rest",
        client_options=ClientOptions(
            api_endpoint=f"modelarmor.{LOCATION_ID}.rep.googleapis.com"
        ),
    )

    # Build the template with all filters
    template = modelarmor_v1.Template(
        filter_config=modelarmor_v1.FilterConfig(
            rai_settings=modelarmor_v1.RaiFilterSettings(
                rai_filters=[
                    modelarmor_v1.RaiFilterSettings.RaiFilter(
                        filter_type=modelarmor_v1.RaiFilterType.HATE_SPEECH,
                        confidence_level=modelarmor_v1.DetectionConfidenceLevel.MEDIUM_AND_ABOVE,
                    ),
                    modelarmor_v1.RaiFilterSettings.RaiFilter(
                        filter_type=modelarmor_v1.RaiFilterType.HARASSMENT,
                        confidence_level=modelarmor_v1.DetectionConfidenceLevel.MEDIUM_AND_ABOVE,
                    ),
                    modelarmor_v1.RaiFilterSettings.RaiFilter(
                        filter_type=modelarmor_v1.RaiFilterType.DANGEROUS,
                        confidence_level=modelarmor_v1.DetectionConfidenceLevel.MEDIUM_AND_ABOVE,
                    ),
                    modelarmor_v1.RaiFilterSettings.RaiFilter(
                        filter_type=modelarmor_v1.RaiFilterType.SEXUALLY_EXPLICIT,
                        confidence_level=modelarmor_v1.DetectionConfidenceLevel.MEDIUM_AND_ABOVE,
                    ),
                ]
            ),
            pi_and_jailbreak_filter_settings=modelarmor_v1.PiAndJailbreakFilterSettings(
                filter_enforcement=modelarmor_v1.PiAndJailbreakFilterSettings.PiAndJailbreakFilterEnforcement.ENABLED,
                confidence_level=modelarmor_v1.DetectionConfidenceLevel.LOW_AND_ABOVE,
            ),
            malicious_uri_filter_settings=modelarmor_v1.MaliciousUriFilterSettings(
                filter_enforcement=modelarmor_v1.MaliciousUriFilterSettings.MaliciousUriFilterEnforcement.ENABLED,
            ),
        ),
    )

    request = modelarmor_v1.CreateTemplateRequest(
        parent=f"projects/{PROJECT_ID}/locations/{LOCATION_ID}",
        template_id=TEMPLATE_ID,
        template=template,
    )

    print(f"Creating Model Armor template '{TEMPLATE_ID}'...")
    print(f"  Project:  {PROJECT_ID}")
    print(f"  Location: {LOCATION_ID}")
    print()

    try:
        response = client.create_template(request=request)
        print(f"✓ Template created: {response.name}")
        print()
        print(f"Add this to app/.env:")
        print(f"  MODEL_ARMOR_TEMPLATE_ID={TEMPLATE_ID}")
    except Exception as e:
        if "already exists" in str(e).lower():
            print(f"Template '{TEMPLATE_ID}' already exists — that's fine!")
            print()
            print(f"Add this to app/.env:")
            print(f"  MODEL_ARMOR_TEMPLATE_ID={TEMPLATE_ID}")
        else:
            print(f"ERROR: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
