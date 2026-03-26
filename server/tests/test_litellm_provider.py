from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from nanobot.providers.litellm_provider import LiteLLMProvider


class LiteLLMProviderErrorTests(unittest.IsolatedAsyncioTestCase):
    async def test_chat_classifies_total_request_timeout(self) -> None:
        provider = LiteLLMProvider(
            api_key="test-key",
            default_model="openai/gpt-4o-mini",
            request_timeout_seconds=0.01,
        )

        async def slow_completion(**kwargs):
            await asyncio.sleep(0.05)

        with patch("nanobot.providers.litellm_provider.acompletion", side_effect=slow_completion):
            response = await provider.chat(messages=[{"role": "user", "content": "hello"}])

        self.assertEqual(response.finish_reason, "error")
        self.assertIsNotNone(response.error)
        self.assertEqual(response.error.kind, "timeout")
        self.assertTrue(response.is_timeout)

    async def test_chat_does_not_misclassify_regular_errors_as_timeout(self) -> None:
        provider = LiteLLMProvider(
            api_key="test-key",
            default_model="openai/gpt-4o-mini",
            request_timeout_seconds=1.0,
        )

        with patch("nanobot.providers.litellm_provider.acompletion", side_effect=RuntimeError("boom")):
            response = await provider.chat(messages=[{"role": "user", "content": "hello"}])

        self.assertEqual(response.finish_reason, "error")
        self.assertIsNotNone(response.error)
        self.assertEqual(response.error.kind, "provider_error")
        self.assertFalse(response.is_timeout)
        self.assertIn("boom", response.error.message)
