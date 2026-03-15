"""Deploy AI Skincare Advisor to Vertex AI Agent Engine Runtime.

Deploys the ADK agent with EXPERIMENTAL server mode for bidi-streaming
(Gemini Live API — real-time voice/video consultations).

Usage:
    python scripts/deploy.py                     # first deployment
    python scripts/deploy.py --update             # update existing

Prerequisites:
    - gcloud auth application-default login
    - GCS staging bucket created
    - .env configured with AGENT_ENGINE_ID (for updates)

Environment variables (from app/.env):
    GOOGLE_CLOUD_PROJECT    — GCP project ID
    GOOGLE_CLOUD_LOCATION   — Region (e.g., us-central1)
    AGENT_ENGINE_ID         — Existing Agent Engine ID (for updates)
    GCS_STAGING_BUCKET      — GCS bucket for staging (gs://bucket-name)
"""

import argparse
import asyncio
import os
import sys

from dotenv import load_dotenv

# Load environment variables
_root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(_root_dir, "app", ".env"))

# Add app to path so skincare_advisor package is importable
sys.path.insert(0, os.path.join(_root_dir, "app"))


PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "boreal-graph-465506-f2")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
STAGING_BUCKET = os.environ.get("GCS_STAGING_BUCKET")
AGENT_ENGINE_ID = os.environ.get("AGENT_ENGINE_ID")

# Package requirements for Agent Engine Runtime
REQUIREMENTS = [
    "google-cloud-aiplatform[agent_engines,adk]",
    "google-adk[eval]",
    "google-cloud-modelarmor",
    "firebase-admin",
    "opentelemetry-sdk",
    "cloudpickle>=3.0",
    "pydantic",
]


async def deploy(update: bool = False):
    """Deploy or update the agent on Agent Engine Runtime."""
    import vertexai
    from vertexai import types as vertexai_types
    from vertexai.agent_engines import AdkApp

    if not STAGING_BUCKET:
        print("ERROR: GCS_STAGING_BUCKET not set in .env")
        print("  Create a bucket: gsutil mb gs://your-project-staging")
        print("  Then add to app/.env: GCS_STAGING_BUCKET=gs://your-project-staging")
        sys.exit(1)

    print("=" * 60)
    print("  AI Skincare Advisor — Agent Engine Deployment")
    print("=" * 60)
    print(f"  Project:        {PROJECT_ID}")
    print(f"  Location:       {LOCATION}")
    print(f"  Staging Bucket: {STAGING_BUCKET}")
    print(f"  Mode:           {'UPDATE' if update else 'CREATE'}")
    print(f"  Server Mode:    EXPERIMENTAL (bidi-streaming)")
    if update and AGENT_ENGINE_ID:
        print(f"  Agent Engine:   {AGENT_ENGINE_ID}")
    print("=" * 60)
    print()

    # Initialize Vertex AI client
    client = vertexai.Client(project=PROJECT_ID, location=LOCATION)

    # Import agent and create AdkApp
    from skincare_advisor.agent import root_agent

    adk_app = AdkApp(agent=root_agent)

    # Extra packages: upload the skincare_advisor source directory
    # so the runtime can import it when unpickling the agent
    extra_packages = [os.path.join(_root_dir, "app", "skincare_advisor")]

    # Environment variables for the Agent Engine runtime
    env_vars = {
        "MODEL_ARMOR_TEMPLATE_ID": os.environ.get(
            "MODEL_ARMOR_TEMPLATE_ID", "skincare-advisor-safety"
        ),
        "MODEL_ARMOR_LOCATION": os.environ.get(
            "MODEL_ARMOR_LOCATION", "us-central1"
        ),
    }

    # Deployment config
    config = {
        "staging_bucket": STAGING_BUCKET,
        "requirements": REQUIREMENTS,
        "extra_packages": extra_packages,
        "env_vars": env_vars,
        "display_name": "AI Skincare Advisor",
        "description": "Real-time multimodal skincare consultation via Gemini Live API",
        # EXPERIMENTAL mode required for bidi-streaming (live audio/video)
        "agent_server_mode": vertexai_types.AgentServerMode.EXPERIMENTAL,
    }

    if update and AGENT_ENGINE_ID:
        # Update existing Agent Engine instance
        print("Updating existing Agent Engine...")
        agent_engine_name = (
            f"projects/{PROJECT_ID}/locations/{LOCATION}"
            f"/reasoningEngines/{AGENT_ENGINE_ID}"
        )
        agent_engine = client.agent_engines.update(
            name=agent_engine_name,
            agent=adk_app,
            config=config,
        )
    else:
        # Create new Agent Engine instance
        print("Creating new Agent Engine (this may take several minutes)...")
        agent_engine = client.agent_engines.create(
            agent=adk_app,
            config=config,
        )

    resource_name = agent_engine.api_resource.name
    engine_id = resource_name.split("/")[-1]

    print()
    print("=" * 60)
    print("  ✓ Deployment successful!")
    print("=" * 60)
    print(f"  Resource:       {resource_name}")
    print(f"  Agent Engine ID: {engine_id}")
    print()
    print("  Next steps:")
    print(f"    1. Update app/.env: AGENT_ENGINE_ID={engine_id}")
    print()
    print("  Query URL:")
    print(f"    https://{LOCATION}-aiplatform.googleapis.com/v1/"
          f"projects/{PROJECT_ID}/locations/{LOCATION}/"
          f"reasoningEngines/{engine_id}:query")
    print()
    print("  Bidi-streaming (Python):")
    print("    async with client.aio.live.agent_engines.connect(")
    print(f'        agent_engine="{resource_name}",')
    print('        config={"class_method": "bidi_stream_query"},')
    print("    ) as connection:")
    print("        ...")
    print()
    print("  Monitor: https://console.cloud.google.com/vertex-ai/agents/agent-engines")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Deploy AI Skincare Advisor to Agent Engine"
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Update existing Agent Engine (requires AGENT_ENGINE_ID in .env)",
    )
    args = parser.parse_args()
    asyncio.run(deploy(update=args.update))


if __name__ == "__main__":
    main()
