r"""Test WebSocket connectivity to the deployed Cloud Run service.

Usage:
    python test_websocket.py

Prerequisites:
    - gcloud auth login (your account must have Cloud Run Invoker role)
    - pip install websockets
"""

import asyncio
import json
import subprocess
import sys

# Cloud Run service URL
SERVICE_URL = "skincare-advisor-4nrerggyra-uc.a.run.app"


def get_identity_token() -> str:
    """Get a Google Identity Token for authenticating with Cloud Run.
    
    Uses the gcloud CLI to generate a token scoped to the service URL.
    For user credentials, we use --impersonate-service-account or 
    simply generate a standard identity token.
    """
    service_url = f"https://{SERVICE_URL}"
    
    # Try with audience first (works with service accounts)
    result = subprocess.run(
        f'gcloud auth print-identity-token --audiences={service_url}',
        capture_output=True, text=True, shell=True
    )
    if result.stdout.strip():
        return result.stdout.strip()
    
    # Fall back to standard identity token (works with user credentials)  
    result = subprocess.run(
        'gcloud auth print-identity-token',
        capture_output=True, text=True, shell=True
    )
    if result.stdout.strip():
        return result.stdout.strip()
    
    return ""


async def test_websocket_connection():
    """Test WebSocket connectivity to the deployed Cloud Run service."""

    token = get_identity_token()
    if not token:
        print("ERROR: Could not get identity token.")
        print("  Run: gcloud auth login")
        return

    print(f"Got identity token: {token[:30]}...")
    print(f"Connecting to wss://{SERVICE_URL}/ws/test_user/test_session")
    print()

    try:
        import websockets
    except ImportError:
        print("Installing websockets...")
        subprocess.run([sys.executable, "-m", "pip", "install", "websockets"], check=True)
        import websockets

    ws_url = f"wss://{SERVICE_URL}/ws/test_user/test_session"
    headers = {"Authorization": f"Bearer {token}"}

    try:
        async with websockets.connect(
            ws_url,
            additional_headers=headers,
            open_timeout=30,
        ) as ws:
            print("✅ Connected! Sending a text message...")

            # Send a simple text message
            message = {
                "mime_type": "text/plain",
                "data": "Hello, can you recommend a good sunscreen?",
            }
            await ws.send(json.dumps(message))
            print(f"Sent: {message['data']}")
            print()

            # Receive responses (wait up to 60 seconds for LLM inference)
            print("Waiting for responses...")
            try:
                async with asyncio.timeout(60):
                    while True:
                        response = await ws.recv()
                        data = json.loads(response)

                        if data.get("turn_complete"):
                            print("\n--- Turn complete ---")
                            break

                        if "text" in data:
                            print(f"{data['text']}", end="", flush=True)

            except asyncio.TimeoutError:
                print("\nTimeout waiting for response (60s)")

            except Exception as e:
                print(f"\nError receiving: {e}")

        print("\n✅ WebSocket test completed successfully!")

    except Exception as e:
        print(f"\n❌ Connection failed: {e}")
        print("\nTroubleshooting:")
        print(f"  1. Check service: gcloud run services describe skincare-advisor --region us-central1 --project boreal-graph-465506-f2")
        print(f"  2. Check logs: gcloud logging read 'resource.labels.service_name=skincare-advisor' --limit=10 --project boreal-graph-465506-f2")
        print(f"  3. Test HTTP first: curl -H 'Authorization: Bearer TOKEN' https://{SERVICE_URL}/")


if __name__ == "__main__":
    asyncio.run(test_websocket_connection())
