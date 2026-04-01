from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from config import (
    DEFAULT_PROVIDER_TIMEOUT_SECONDS,
    generate_nanobot_config,
    validate_config,
)


class ConfigValidationTests(unittest.TestCase):
    def test_generate_nanobot_config_uses_default_provider_timeout(self) -> None:
        cfg = {
            "nanobot": {
                "api_key": "test-key",
                "provider": "openrouter",
                "model": "openai/gpt-4o-mini",
            }
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            with patch("config.WORKSPACE_DIR", tmp_path), patch("config.NANOBOT_CONFIG_JSON", tmp_path / "config.json"):
                generate_nanobot_config(cfg)

            payload = json.loads((tmp_path / "config.json").read_text(encoding="utf-8"))

        self.assertEqual(
            payload["providers"]["openrouter"]["timeoutSeconds"],
            DEFAULT_PROVIDER_TIMEOUT_SECONDS,
        )

    def test_rejects_short_device_token(self) -> None:
        errors = validate_config({
            "nanobot": {"api_key": "test-key"},
            "server": {"port": 8765},
            "device": {"auth_token": "short"},
        })
        self.assertTrue(any("device.auth_token" in err for err in errors))

    def test_rejects_short_app_token(self) -> None:
        errors = validate_config({
            "nanobot": {"api_key": "test-key"},
            "server": {"port": 8765},
            "app": {"auth_token": "short"},
        })
        self.assertTrue(any("app.auth_token" in err for err in errors))

    def test_reports_missing_runtime_dependency(self) -> None:
        def fake_find_spec(name: str):
            if name == "websockets":
                return None
            return object()

        with patch("config.importlib.util.find_spec", side_effect=fake_find_spec):
            errors = validate_config({
                "nanobot": {"api_key": "test-key"},
                "server": {"port": 8765},
                "whatsapp": {"enabled": True},
                "device": {"auth_token": "local-secret-123"},
            })

        self.assertTrue(any("websockets" in err for err in errors))

    def test_rejects_non_positive_provider_timeout(self) -> None:
        errors = validate_config({
            "nanobot": {
                "api_key": "test-key",
                "provider_timeout_seconds": 0,
            },
            "server": {"port": 8765},
        })

        self.assertTrue(any("provider_timeout_seconds" in err for err in errors))

    def test_accepts_numeric_string_provider_timeout(self) -> None:
        cfg = {
            "nanobot": {
                "api_key": "test-key",
                "provider_timeout_seconds": "45.5",
            },
            "server": {"port": 8765},
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            (tmp_path / "SOUL.md").write_text("# soul\n", encoding="utf-8")

            with patch("config.WORKSPACE_DIR", tmp_path), patch(
                "config.importlib.util.find_spec",
                return_value=object(),
            ):
                errors = validate_config(cfg)

        self.assertFalse(any("provider_timeout_seconds" in err for err in errors))
