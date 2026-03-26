from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from config import validate_config


class ConfigValidationTests(unittest.TestCase):
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
