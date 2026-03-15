"""AI Skincare Advisor — ADK Agent Package.

This package exports the root_agent for ADK discovery.
ADK looks for `root_agent` in __init__.py or agent.py.
"""

from .agent import root_agent

__all__ = ["root_agent"]
