from __future__ import annotations

import importlib
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load_bootstrap_module():
    sys.modules.pop("bootstrap", None)
    fake_app_runtime = types.ModuleType("services.app_runtime")

    class FakeAppRuntimeService:
        pass

    fake_app_runtime.AppRuntimeService = FakeAppRuntimeService

    with patch.dict(sys.modules, {"services.app_runtime": fake_app_runtime}):
        return importlib.import_module("bootstrap")


class BootstrapProviderTimeoutTests(unittest.TestCase):
    def test_create_agent_passes_provider_timeout_to_provider(self) -> None:
        bootstrap = _load_bootstrap_module()
        bus = object()
        provider = object()
        session_manager = object()
        agent = object()

        cfg = {
            "nanobot": {
                "api_key": "test-key",
                "model": "openai/gpt-4o-mini",
                "provider": "openai",
                "provider_timeout_seconds": 45,
            }
        }

        with patch.object(bootstrap, "MessageBus", return_value=bus) as message_bus_cls, patch.object(
            bootstrap,
            "LiteLLMProvider",
            return_value=provider,
        ) as provider_cls, patch.object(
            bootstrap,
            "SessionManager",
            return_value=session_manager,
        ) as session_manager_cls, patch.object(
            bootstrap,
            "AgentLoop",
            return_value=agent,
        ) as agent_loop_cls:
            result_bus, result_agent = bootstrap.create_agent(cfg)

        self.assertIs(result_bus, bus)
        self.assertIs(result_agent, agent)
        provider_cls.assert_called_once_with(
            api_key="test-key",
            default_model="openai/gpt-4o-mini",
            provider_name="openai",
            request_timeout_seconds=45,
        )
