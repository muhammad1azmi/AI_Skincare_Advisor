"""Shared server configuration — single source of truth for env vars.

All server modules should import project config from here
instead of reading os.environ directly with hardcoded defaults.
"""

import os

PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
