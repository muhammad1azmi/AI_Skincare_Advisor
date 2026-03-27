r"""Create a Vertex AI Agent Engine instance for VertexAiSessionService.

This is a one-time setup script. The resulting agent_engine_id is needed for:
- server/main.py (VertexAiSessionService)
- Cloud Run deployment (AGENT_ENGINE_ID env var)

Usage:
    python create_agent_engine.py
"""

import asyncio
import vertexai


import os

PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")


async def main():
    print(f"Creating Agent Engine instance...")
    print(f"  Project: {PROJECT_ID}")
    print(f"  Location: {LOCATION}")
    print()

    client = vertexai.Client(project=PROJECT_ID, location=LOCATION)

    # Create an Agent Engine instance (no code deployment needed)
    print("Creating instance (this may take a moment on first use)...")
    agent_engine = client.agent_engines.create()

    # Extract the agent_engine_id
    agent_engine_id = agent_engine.api_resource.name.split("/")[-1]

    print()
    print("=" * 60)
    print("SUCCESS! Agent Engine instance created.")
    print(f"  Full resource name: {agent_engine.api_resource.name}")
    print(f"  Agent Engine ID:    {agent_engine_id}")
    print("=" * 60)
    print()
    print("Next steps:")
    print(f"  1. Add to your .env file:")
    print(f"     AGENT_ENGINE_ID={agent_engine_id}")
    print()
    print(f"  2. Use in Cloud Run deployment:")
    print(f"     --set-env-vars=\"AGENT_ENGINE_ID={agent_engine_id},...\"")
    print()


if __name__ == "__main__":
    asyncio.run(main())
