
import os
import vertexai
from vertexai.agent_engines import AdkApp

if False:
  from google.adk.agents import config_agent_utils
  root_agent = config_agent_utils.from_config("./skincare_advisor_tmp20260315_191900/root_agent.yaml")
else:
  from .agent import root_agent

if False: # Whether or not to use Express Mode
  vertexai.init(api_key=os.environ.get("GOOGLE_API_KEY"))
else:
  vertexai.init(
    project=os.environ.get("GOOGLE_CLOUD_PROJECT"),
    location=os.environ.get("GOOGLE_CLOUD_LOCATION"),
  )

adk_app = AdkApp(
    agent=root_agent,
    enable_tracing=None,
)
