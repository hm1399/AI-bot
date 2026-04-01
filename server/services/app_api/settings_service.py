from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from nanobot.providers.litellm_provider import LiteLLMProvider

from .json_store import JsonObjectStore


class SettingsService:
    def __init__(self, cfg: dict[str, Any], runtime_dir: Path) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        self.cfg = cfg
        self.overlay_store = JsonObjectStore(runtime_dir / "app_settings.json")
        self.secrets_store = JsonObjectStore(runtime_dir / "app_secrets.json")

    def get_public_settings(self) -> dict[str, Any]:
        settings = self._base_settings()
        settings.update(self.overlay_store.load())
        settings["llm_api_key_configured"] = bool(self._get_secret_value())
        settings.pop("llm_api_key", None)
        return settings

    def update_settings(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("settings payload must be an object")

        overlay = self.overlay_store.load()
        for key, value in payload.items():
            if key == "llm_api_key":
                self._set_secret_value(value)
                continue
            overlay[key] = self._normalize_field(key, value)

        self.overlay_store.save(overlay)
        self._apply_runtime_updates(overlay)
        return self.get_public_settings()

    async def test_llm_connection(
        self,
        payload: dict[str, Any] | None = None,
    ) -> tuple[bool, dict[str, Any] | None, dict[str, Any] | None]:
        payload = payload or {}
        if not isinstance(payload, dict):
            return False, None, {
                "code": "INVALID_ARGUMENT",
                "message": "settings payload must be an object",
                "status": 400,
            }

        candidate = self.get_public_settings()
        secret = self._get_secret_value()

        for key, value in payload.items():
            if key == "llm_api_key":
                if value is None or (isinstance(value, str) and not value.strip()):
                    secret = ""
                elif isinstance(value, str):
                    secret = value.strip()
                else:
                    return False, None, {
                        "code": "INVALID_ARGUMENT",
                        "message": "llm_api_key must be a string or null",
                        "status": 400,
                    }
                continue
            candidate[key] = self._normalize_field(key, value)

        provider = str(candidate.get("llm_provider") or "").strip()
        model = str(candidate.get("llm_model") or "").strip()
        base_url = candidate.get("llm_base_url")
        if not provider or not model or not secret:
            return False, None, {
                "code": "LLM_NOT_CONFIGURED",
                "message": "llm provider, model, and api key are required",
                "status": 400,
            }

        client = LiteLLMProvider(
            api_key=secret,
            api_base=base_url,
            default_model=model,
            provider_name=provider,
            request_timeout_seconds=10,
        )
        response = await client.chat(
            [{"role": "user", "content": "Reply with ok"}],
            max_tokens=8,
            temperature=0,
        )
        if response.is_timeout:
            return False, None, {
                "code": "UPSTREAM_TIMEOUT",
                "message": response.error.message if response.error else "upstream timeout",
                "status": 504,
            }
        if response.is_error:
            message = response.error.message if response.error else (response.content or "upstream error")
            lower = message.lower()
            if any(token in lower for token in ("unauthorized", "invalid api key", "incorrect api key", "auth", "401", "forbidden")):
                return False, None, {
                    "code": "UPSTREAM_AUTH_FAILED",
                    "message": message,
                    "status": 502,
                }
            return False, None, {
                "code": "UPSTREAM_AUTH_FAILED",
                "message": message,
                "status": 502,
            }
        return True, {
            "success": True,
            "provider": provider,
            "model": model,
            "message": "connection ok",
        }, None

    def _base_settings(self) -> dict[str, Any]:
        server_cfg = self.cfg.get("server", {})
        nanobot_cfg = self.cfg.get("nanobot", {})
        asr_cfg = self.cfg.get("asr", {})
        tts_cfg = self.cfg.get("tts", {})
        app_settings = deepcopy(self.cfg.get("app", {}).get("settings", {}))
        return {
            "server_url": server_cfg.get("host", "127.0.0.1"),
            "server_port": server_cfg.get("port", 8765),
            "llm_provider": nanobot_cfg.get("provider", "openrouter"),
            "llm_model": nanobot_cfg.get("model", ""),
            "llm_base_url": nanobot_cfg.get("api_base"),
            "stt_provider": asr_cfg.get("provider", "funasr"),
            "stt_model": asr_cfg.get("model", "FunAudioLLM/SenseVoiceSmall"),
            "stt_language": asr_cfg.get("language", "auto"),
            "tts_provider": tts_cfg.get("provider", "edge_tts"),
            "tts_model": tts_cfg.get("model", "edge_tts"),
            "tts_voice": tts_cfg.get("voice", "zh-CN-XiaoxiaoNeural"),
            "tts_speed": app_settings.get("tts_speed", 1.0),
            "device_volume": app_settings.get("device_volume", 75),
            "led_enabled": app_settings.get("led_enabled", True),
            "led_brightness": app_settings.get("led_brightness", 50),
            "led_mode": app_settings.get("led_mode", "breathing"),
            "led_color": app_settings.get("led_color", "#0000ff"),
            "wake_word": app_settings.get("wake_word", "Hey Assistant"),
            "auto_listen": app_settings.get("auto_listen", True),
            "llm_api_key_configured": bool(self._get_secret_value()),
        }

    def _set_secret_value(self, value: Any) -> None:
        secrets = self.secrets_store.load()
        if value is None:
            secrets.pop("llm_api_key", None)
        elif isinstance(value, str):
            cleaned = value.strip()
            if cleaned:
                secrets["llm_api_key"] = cleaned
            else:
                secrets.pop("llm_api_key", None)
        else:
            raise ValueError("llm_api_key must be a string or null")

        self.secrets_store.save(secrets)
        self.cfg.setdefault("nanobot", {})["api_key"] = secrets.get("llm_api_key", "")

    def _get_secret_value(self) -> str:
        secrets = self.secrets_store.load()
        candidate = secrets.get("llm_api_key")
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
        raw_cfg = self.cfg.get("nanobot", {}).get("api_key", "")
        return raw_cfg.strip() if isinstance(raw_cfg, str) else ""

    def _apply_runtime_updates(self, overlay: dict[str, Any]) -> None:
        server_cfg = self.cfg.setdefault("server", {})
        nanobot_cfg = self.cfg.setdefault("nanobot", {})
        asr_cfg = self.cfg.setdefault("asr", {})
        tts_cfg = self.cfg.setdefault("tts", {})
        app_cfg = self.cfg.setdefault("app", {})
        app_settings = app_cfg.setdefault("settings", {})

        mapping = {
            "server_url": (server_cfg, "host"),
            "server_port": (server_cfg, "port"),
            "llm_provider": (nanobot_cfg, "provider"),
            "llm_model": (nanobot_cfg, "model"),
            "llm_base_url": (nanobot_cfg, "api_base"),
            "stt_provider": (asr_cfg, "provider"),
            "stt_model": (asr_cfg, "model"),
            "stt_language": (asr_cfg, "language"),
            "tts_provider": (tts_cfg, "provider"),
            "tts_model": (tts_cfg, "model"),
            "tts_voice": (tts_cfg, "voice"),
        }
        app_setting_keys = {
            "tts_speed",
            "device_volume",
            "led_enabled",
            "led_brightness",
            "led_mode",
            "led_color",
            "wake_word",
            "auto_listen",
        }

        for key, value in overlay.items():
            if key in mapping:
                target, field = mapping[key]
                target[field] = value
            elif key in app_setting_keys:
                app_settings[key] = value

    @staticmethod
    def _normalize_field(key: str, value: Any) -> Any:
        optional_string_keys = {"llm_base_url"}
        string_keys = {
            "server_url",
            "llm_provider",
            "llm_model",
            "stt_provider",
            "stt_model",
            "stt_language",
            "tts_provider",
            "tts_model",
            "tts_voice",
            "led_mode",
            "led_color",
            "wake_word",
        }
        bool_keys = {"led_enabled", "auto_listen"}
        int_keys = {"server_port", "device_volume", "led_brightness"}
        float_keys = {"tts_speed"}

        if key in string_keys:
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{key} must be a non-empty string")
            return value.strip()
        if key in optional_string_keys:
            if value is None:
                return None
            if not isinstance(value, str):
                raise ValueError(f"{key} must be a string or null")
            cleaned = value.strip()
            return cleaned or None
        if key in bool_keys:
            if not isinstance(value, bool):
                raise ValueError(f"{key} must be a boolean")
            return value
        if key in int_keys:
            if not isinstance(value, int):
                raise ValueError(f"{key} must be an integer")
            if key == "server_port" and not (1 <= value <= 65535):
                raise ValueError("server_port must be between 1 and 65535")
            if key in {"device_volume", "led_brightness"} and not (0 <= value <= 100):
                raise ValueError(f"{key} must be between 0 and 100")
            return value
        if key in float_keys:
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise ValueError(f"{key} must be a number")
            if float(value) <= 0:
                raise ValueError(f"{key} must be greater than 0")
            return float(value)
        raise ValueError(f"unsupported settings field: {key}")
