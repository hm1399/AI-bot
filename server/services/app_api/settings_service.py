from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from nanobot.providers.litellm_provider import LiteLLMProvider
from services.experience.models import normalize_persona_fields, normalize_scene_mode

from .json_store import JsonObjectStore


_LEGACY_CONNECTION_FIELDS = {"server_url", "server_port"}


class SettingsService:
    def __init__(self, cfg: dict[str, Any], runtime_dir: Path) -> None:
        runtime_dir.mkdir(parents=True, exist_ok=True)
        self.cfg = cfg
        self.overlay_store = JsonObjectStore(runtime_dir / "app_settings.json")
        self.secrets_store = JsonObjectStore(runtime_dir / "app_secrets.json")
        self._load_overlay()

    def get_public_settings(self) -> dict[str, Any]:
        settings = self._base_settings()
        settings.update(self._load_overlay())
        normalized_persona = normalize_persona_fields(
            {
                "tone_style": settings.get("persona_tone_style"),
                "reply_length": settings.get("persona_reply_length"),
                "proactivity": settings.get("persona_proactivity"),
                "voice_style": settings.get("persona_voice_style"),
            }
        )
        settings["default_scene_mode"] = normalize_scene_mode(
            settings.get("default_scene_mode"),
        )
        settings["persona_tone_style"] = normalized_persona["tone_style"]
        settings["persona_reply_length"] = normalized_persona["reply_length"]
        settings["persona_proactivity"] = normalized_persona["proactivity"]
        settings["persona_voice_style"] = normalized_persona["voice_style"]
        settings["llm_api_key_configured"] = bool(self._get_secret_value())
        settings.pop("llm_api_key", None)
        return settings

    def update_settings(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("settings payload must be an object")

        overlay = self._load_overlay()
        for key, value in payload.items():
            if key == "llm_api_key":
                self._set_secret_value(value)
                continue
            if key in _LEGACY_CONNECTION_FIELDS:
                overlay.pop(key, None)
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
            if key in _LEGACY_CONNECTION_FIELDS:
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
        nanobot_cfg = self.cfg.get("nanobot", {})
        asr_cfg = self.cfg.get("asr", {})
        tts_cfg = self.cfg.get("tts", {})
        app_settings = deepcopy(self.cfg.get("app", {}).get("settings", {}))
        return {
            "llm_provider": nanobot_cfg.get("provider", "openrouter"),
            "llm_model": nanobot_cfg.get("model", ""),
            "llm_base_url": nanobot_cfg.get("api_base"),
            "stt_provider": asr_cfg.get("provider", "funasr"),
            "stt_model": asr_cfg.get("model", "FunAudioLLM/SenseVoiceSmall"),
            "stt_language": asr_cfg.get("language", "auto"),
            "tts_provider": tts_cfg.get("provider", "edge_tts"),
            "tts_model": tts_cfg.get("model", "edge_tts"),
            "tts_voice": tts_cfg.get("voice", "en-US-AriaNeural"),
            "tts_speed": app_settings.get("tts_speed", 1.0),
            "device_volume": app_settings.get("device_volume", 75),
            "led_enabled": app_settings.get("led_enabled", True),
            "led_brightness": app_settings.get("led_brightness", 50),
            "led_mode": app_settings.get("led_mode", "breathing"),
            "led_color": app_settings.get("led_color", "#0000ff"),
            "wake_word": app_settings.get("wake_word", "Hey Assistant"),
            "auto_listen": app_settings.get("auto_listen", True),
            "default_scene_mode": app_settings.get("default_scene_mode", "focus"),
            "persona_tone_style": app_settings.get("persona_tone_style", "clear"),
            "persona_reply_length": app_settings.get("persona_reply_length", "medium"),
            "persona_proactivity": app_settings.get("persona_proactivity", "balanced"),
            "persona_voice_style": app_settings.get("persona_voice_style", "calm"),
            "physical_interaction_enabled": app_settings.get("physical_interaction_enabled", True),
            "shake_enabled": app_settings.get("shake_enabled", True),
            "tap_confirmation_enabled": app_settings.get("tap_confirmation_enabled", True),
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

    def _load_overlay(self) -> dict[str, Any]:
        overlay = self.overlay_store.load()
        if not isinstance(overlay, dict):
            overlay = {}
        cleaned = {
            key: value
            for key, value in overlay.items()
            if key not in _LEGACY_CONNECTION_FIELDS
        }
        if cleaned != overlay:
            self.overlay_store.save(cleaned)
        return cleaned

    def _apply_runtime_updates(self, overlay: dict[str, Any]) -> None:
        nanobot_cfg = self.cfg.setdefault("nanobot", {})
        asr_cfg = self.cfg.setdefault("asr", {})
        tts_cfg = self.cfg.setdefault("tts", {})
        app_cfg = self.cfg.setdefault("app", {})
        app_settings = app_cfg.setdefault("settings", {})

        mapping = {
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
            "default_scene_mode",
            "persona_tone_style",
            "persona_reply_length",
            "persona_proactivity",
            "persona_voice_style",
            "physical_interaction_enabled",
            "shake_enabled",
            "tap_confirmation_enabled",
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
        persona_field_mapping = {
            "persona_tone_style": "tone_style",
            "persona_reply_length": "reply_length",
            "persona_proactivity": "proactivity",
            "persona_voice_style": "voice_style",
        }
        enum_string_keys = {
            "default_scene_mode": {"focus", "offwork", "meeting"},
        }
        string_keys = {
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
            "persona_tone_style",
            "persona_reply_length",
            "persona_proactivity",
            "persona_voice_style",
        }
        bool_keys = {
            "led_enabled",
            "auto_listen",
            "physical_interaction_enabled",
            "shake_enabled",
            "tap_confirmation_enabled",
        }
        int_keys = {"device_volume", "led_brightness"}
        float_keys = {"tts_speed"}

        if key == "default_scene_mode":
            if not isinstance(value, str) or not value.strip():
                raise ValueError("default_scene_mode must be a non-empty string")
            return normalize_scene_mode(value)
        if key in persona_field_mapping:
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{key} must be a non-empty string")
            normalized = normalize_persona_fields(
                {persona_field_mapping[key]: value},
                partial=True,
                allow_none=True,
            ) or {}
            if persona_field_mapping[key] not in normalized:
                raise ValueError(f"{key} must be a supported persona option")
            return normalized[persona_field_mapping[key]]
        if key in enum_string_keys:
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"{key} must be a non-empty string")
            cleaned = value.strip().lower()
            if cleaned not in enum_string_keys[key]:
                raise ValueError(
                    f"{key} must be one of: {', '.join(sorted(enum_string_keys[key]))}"
                )
            return cleaned
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
