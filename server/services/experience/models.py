from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping


SCENE_MODES = ("focus", "offwork", "meeting")
SCENE_MODE_LABELS = {
    "focus": "Focus",
    "offwork": "Off Work",
    "meeting": "Meeting",
}
SCENE_MODE_DESCRIPTIONS = {
    "focus": "Shorter replies and fewer non-urgent interruptions.",
    "offwork": "Warmer tone and lighter interaction rules.",
    "meeting": "Keep responses brief and stay as silent as possible.",
}
DEFAULT_SCENE_MODE = "focus"

PERSONA_FIELD_KEYS = (
    "tone_style",
    "reply_length",
    "proactivity",
    "voice_style",
)
PERSONA_TONE_STYLES = ("clear", "warm", "concise", "formal")
PERSONA_REPLY_LENGTHS = ("short", "medium", "expanded")
PERSONA_PROACTIVITY_LEVELS = ("low", "balanced", "high")
PERSONA_VOICE_STYLES = ("calm", "bright", "quiet")
PERSONA_FIELD_ALLOWED_VALUES = {
    "tone_style": set(PERSONA_TONE_STYLES),
    "reply_length": set(PERSONA_REPLY_LENGTHS),
    "proactivity": set(PERSONA_PROACTIVITY_LEVELS),
    "voice_style": set(PERSONA_VOICE_STYLES),
}
PERSONA_FIELD_ALIASES = {
    "tone_style": {
        "balanced": "clear",
        "neutral": "clear",
        "direct": "concise",
    },
    "reply_length": {
        "balanced": "medium",
        "long": "expanded",
    },
    "proactivity": {
        "medium": "balanced",
    },
    "voice_style": {
        "natural": "calm",
        "soft": "bright",
        "steady": "calm",
        "discreet": "quiet",
        "whisper": "quiet",
        "playful": "bright",
    },
}
DEFAULT_PERSONA_PRESET = "balanced"
DEFAULT_PERSONA_FIELDS = {
    "tone_style": "clear",
    "reply_length": "medium",
    "proactivity": "balanced",
    "voice_style": "calm",
}
PERSONA_PRESETS: dict[str, dict[str, str]] = {
    "balanced": {
        "label": "Balanced",
        "tone_style": "clear",
        "reply_length": "medium",
        "proactivity": "balanced",
        "voice_style": "calm",
    },
    "focus_brief": {
        "label": "Focus Brief",
        "tone_style": "concise",
        "reply_length": "short",
        "proactivity": "low",
        "voice_style": "quiet",
    },
    "companion_warm": {
        "label": "Companion Warm",
        "tone_style": "warm",
        "reply_length": "expanded",
        "proactivity": "high",
        "voice_style": "bright",
    },
    "meeting_brief": {
        "label": "Meeting Brief",
        "tone_style": "formal",
        "reply_length": "short",
        "proactivity": "low",
        "voice_style": "quiet",
    },
}
SCENE_PERSONA_PRESETS = {
    "focus": "focus_brief",
    "offwork": "companion_warm",
    "meeting": "meeting_brief",
}
SHAKE_MODES = ("fortune", "decision", "random")
INTERACTION_THROTTLE_SECONDS = {
    "tap": 0.75,
    "shake": 1.5,
    "hold": 0.25,
}


def build_experience_catalog(
    *,
    runtime_path: str = "/api/app/v1/experience",
    interactions_path: str = "/api/app/v1/experience/interactions",
    settings_path: str = "/api/app/v1/settings",
    session_path_template: str = "/api/app/v1/sessions/{session_id}",
) -> dict[str, Any]:
    return {
        "available": True,
        "runtime_path": runtime_path,
        "interactions_path": interactions_path,
        "settings_path": settings_path,
        "session_path_template": session_path_template,
        "scene_modes": [
            {
                "id": scene_mode,
                "label": SCENE_MODE_LABELS.get(scene_mode, scene_mode.title()),
                "description": SCENE_MODE_DESCRIPTIONS.get(scene_mode, ""),
            }
            for scene_mode in SCENE_MODES
        ],
        "persona_presets": [
            {
                "id": preset_id,
                "profile_id": preset_id,
                "preset": preset_id,
                "label": preset["label"],
                **{
                    key: preset[key]
                    for key in PERSONA_FIELD_KEYS
                    if key in preset
                },
            }
            for preset_id, preset in PERSONA_PRESETS.items()
        ],
    }


def clean_optional_string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    cleaned = value.strip()
    return cleaned or None


def normalize_scene_mode(
    value: Any,
    *,
    default: str = DEFAULT_SCENE_MODE,
    allow_none: bool = False,
) -> str | None:
    cleaned = clean_optional_string(value)
    if cleaned is None:
        return None if allow_none else default
    lowered = cleaned.lower()
    if lowered in SCENE_MODES:
        return lowered
    return None if allow_none else default


def normalize_persona_token(value: Any) -> str | None:
    cleaned = clean_optional_string(value)
    if cleaned is None:
        return None
    return cleaned.lower().replace(" ", "_")


def normalize_persona_profile(
    value: Any,
    *,
    allow_none: bool = False,
) -> str | None:
    candidate: Any = value
    if isinstance(value, Mapping):
        for key in ("preset", "profile_id", "persona_profile_id", "id", "slug", "name"):
            if key in value:
                candidate = value.get(key)
                break
    normalized = normalize_persona_token(candidate)
    if normalized in PERSONA_PRESETS:
        return normalized
    return None if allow_none else DEFAULT_PERSONA_PRESET


def normalize_persona_fields(
    payload: Mapping[str, Any] | None = None,
    *,
    partial: bool = False,
    allow_none: bool = False,
) -> dict[str, str] | None:
    if payload is None:
        if allow_none:
            return None
        return {} if partial else deepcopy(DEFAULT_PERSONA_FIELDS)

    fields: dict[str, str] = {} if partial else deepcopy(DEFAULT_PERSONA_FIELDS)
    for key in PERSONA_FIELD_KEYS:
        raw = payload.get(key) if isinstance(payload, Mapping) else None
        normalized = normalize_persona_token(raw)
        if normalized is not None:
            normalized = PERSONA_FIELD_ALIASES.get(key, {}).get(normalized, normalized)
        allowed = PERSONA_FIELD_ALLOWED_VALUES.get(key, set())
        if normalized is not None:
            if not allowed or normalized in allowed:
                fields[key] = normalized
    return fields


def merge_persona_fields(*payloads: Mapping[str, Any] | None) -> dict[str, str]:
    merged = deepcopy(DEFAULT_PERSONA_FIELDS)
    for payload in payloads:
        normalized = normalize_persona_fields(payload, partial=True, allow_none=True)
        if not normalized:
            continue
        for key, value in normalized.items():
            merged[key] = value
    return merged


def preset_fields(preset: str | None) -> dict[str, str]:
    if not preset:
        return {}
    normalized = normalize_persona_profile(preset, allow_none=True)
    if normalized is None:
        return {}
    preset_payload = PERSONA_PRESETS.get(normalized) or {}
    return {
        key: value
        for key, value in preset_payload.items()
        if key in PERSONA_FIELD_KEYS and isinstance(value, str) and value.strip()
    }


def persona_fields_from_settings(settings: Mapping[str, Any] | None) -> dict[str, str]:
    settings = settings or {}
    return merge_persona_fields(
        {
            "tone_style": settings.get("persona_tone_style"),
            "reply_length": settings.get("persona_reply_length"),
            "proactivity": settings.get("persona_proactivity"),
            "voice_style": settings.get("persona_voice_style"),
        }
    )


def build_persona_profile(
    profile: Any = None,
    *,
    persona_fields: Mapping[str, Any] | None = None,
) -> dict[str, str]:
    preset = normalize_persona_profile(profile) or DEFAULT_PERSONA_PRESET
    fields = merge_persona_fields(
        preset_fields(preset),
        persona_fields,
    )
    label = (PERSONA_PRESETS.get(preset) or {}).get("label") or preset.replace("_", " ").title()
    return {
        "preset": preset,
        "label": str(label),
        **fields,
    }


def build_physical_interaction_result(
    *,
    interaction_kind: str,
    mode: str,
    title: str,
    short_result: str,
    display_text: str,
    voice_text: str | None,
    animation_hint: str | None = None,
    led_hint: str | None = None,
    feedback_mode: str | None = None,
    history_entry: Any = None,
    approval_source: str | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    payload = {
        "interaction_kind": interaction_kind,
        "mode": mode,
        "title": title,
        "short_result": short_result,
        "display_text": display_text,
        "voice_text": voice_text,
        "animation_hint": animation_hint,
        "led_hint": led_hint,
        "feedback_mode": feedback_mode,
        "approval_source": approval_source,
        "history_entry": deepcopy(history_entry),
        "metadata": deepcopy(dict(metadata or {})) or None,
    }
    return {key: value for key, value in payload.items() if value is not None}
