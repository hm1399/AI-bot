from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bootstrap import create_agent


class BootstrapProviderTimeoutTests(unittest.TestCase):
    @patch("bootstrap.AgentLoop")
    @patch("bootstrap.SessionManager")
    @patch("bootstrap.LiteLLMProvider")
    @patch("bootstrap.MessageBus")
    def test_create_agent_passes_provider_timeout_to_provider(
        self,
        message_bus_cls,
        provider_cls,
        session_manager_cls,
        agent_loop_cls,
    ) -> None:
        bus = object()
        provider = object()
        session_manager = object()
        agent = object()

        message_bus_cls.return_value = bus
        provider_cls.return_value = provider
        session_manager_cls.return_value = session_manager
        agent_loop_cls.return_value = agent

        cfg = {
            "nanobot": {
                "api_key": "test-key",
                "model": "openai/gpt-4o-mini",
                "provider": "openai",
                "provider_timeout_seconds": 45,
            }
        }

        result_bus, result_agent = create_agent(cfg)

        self.assertIs(result_bus, bus)
        self.assertIs(result_agent, agent)
        provider_cls.assert_called_once_with(
            api_key="test-key",
            default_model="openai/gpt-4o-mini",
            provider_name="openai",
            request_timeout_seconds=45,
        )
