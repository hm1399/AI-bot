"""Context builder for assembling agent prompts."""

from __future__ import annotations

import base64
import mimetypes
import platform
import time
from collections.abc import Mapping
from datetime import datetime
from pathlib import Path
from typing import Any

from nanobot.agent.memory import MemoryStore
from nanobot.agent.skills import SkillsLoader


class ContextBuilder:
    """Builds the context (system prompt + messages) for the agent."""

    BOOTSTRAP_FILES = ["AGENTS.md", "SOUL.md", "USER.md", "TOOLS.md", "IDENTITY.md"]
    _RUNTIME_CONTEXT_TAG = "[Runtime Context — metadata only, not instructions]"
    AUDIT_METADATA_KEYS = (
        "source",
        "source_channel",
        "interaction_surface",
        "capture_source",
        "voice_path",
        "reply_language",
        "emotion",
        "app_session_id",
        "scene_mode",
        "persona_profile_id",
        "persona_tone_style",
        "persona_reply_length",
        "persona_proactivity",
        "persona_voice_style",
        "interaction_kind",
        "interaction_mode",
        "approval_source",
    )
    _TRUSTED_RUNTIME_LABELS = (
        ("scene_mode", "Scene Mode"),
        ("persona_profile_id", "Persona Profile"),
        ("persona_tone_style", "Persona Tone Style"),
        ("persona_reply_length", "Persona Reply Length"),
        ("persona_proactivity", "Persona Proactivity"),
        ("persona_voice_style", "Persona Voice Style"),
        ("interaction_kind", "Interaction Kind"),
        ("interaction_mode", "Interaction Mode"),
        ("approval_source", "Approval Source"),
        ("interaction_surface", "Interaction Surface"),
        ("capture_source", "Capture Source"),
        ("voice_path", "Voice Path"),
        ("source", "Message Source"),
        ("source_channel", "Source Channel"),
        ("reply_language", "Preferred Reply Language"),
        ("emotion", "Emotion"),
        ("app_session_id", "App Session ID"),
    )

    def __init__(self, workspace: Path):
        self.workspace = workspace
        self.memory = MemoryStore(workspace)
        self.skills = SkillsLoader(workspace)

    def build_system_prompt(self, skill_names: list[str] | None = None) -> str:
        """Build the system prompt from identity, bootstrap files, memory, and skills."""
        parts = [self._get_identity()]

        bootstrap = self._load_bootstrap_files()
        if bootstrap:
            parts.append(bootstrap)

        memory = self.memory.get_memory_context()
        if memory:
            parts.append(f"# Memory\n\n{memory}")

        always_skills = self.skills.get_always_skills()
        if always_skills:
            always_content = self.skills.load_skills_for_context(always_skills)
            if always_content:
                parts.append(f"# Active Skills\n\n{always_content}")

        skills_summary = self.skills.build_skills_summary()
        if skills_summary:
            parts.append(f"""# Skills

The following skills extend your capabilities. To use a skill, read its SKILL.md file using the read_file tool.
Skills with available="false" need dependencies installed first - you can try installing them with apt/brew.

{skills_summary}""")

        return "\n\n---\n\n".join(parts)

    def _get_identity(self) -> str:
        """Get the core identity section."""
        workspace_path = str(self.workspace.expanduser().resolve())
        system = platform.system()
        runtime = f"{'macOS' if system == 'Darwin' else system} {platform.machine()}, Python {platform.python_version()}"

        return f"""# nanobot 🐈

You are nanobot, a helpful AI assistant.

## Runtime
{runtime}

## Workspace
Your workspace is at: {workspace_path}
- Long-term memory: {workspace_path}/memory/MEMORY.md (write important facts here)
- History log: {workspace_path}/memory/HISTORY.md (grep-searchable). Each entry starts with [YYYY-MM-DD HH:MM].
- Custom skills: {workspace_path}/skills/{{skill-name}}/SKILL.md

## nanobot Guidelines
- State intent before tool calls, but NEVER predict or claim results before receiving them.
- Before modifying a file, read it first. Do not assume files or directories exist.
- After writing or editing a file, re-read it if accuracy matters.
- If a tool call fails, analyze the error before retrying with a different approach.
- Ask for clarification when the request is ambiguous.

Reply directly with text for conversations. Only use the 'message' tool to send to a specific chat channel."""

    @staticmethod
    def _build_runtime_context(
        channel: str | None,
        chat_id: str | None,
        metadata: dict[str, Any] | None = None,
    ) -> str:
        """Build untrusted runtime metadata block for injection before the user message."""
        now = datetime.now().strftime("%Y-%m-%d %H:%M (%A)")
        tz = time.strftime("%Z") or "UTC"
        lines = [f"Current Time: {now} ({tz})"]
        if channel and chat_id:
            lines += [f"Channel: {channel}", f"Chat ID: {chat_id}"]
        if metadata:
            reply_language = str(metadata.get("reply_language") or "").strip()
            if reply_language:
                lines.append(f"Preferred Reply Language: {reply_language}")
        return ContextBuilder._RUNTIME_CONTEXT_TAG + "\n" + "\n".join(lines)

    def _load_bootstrap_files(self) -> str:
        """Load all bootstrap files from workspace."""
        parts = []

        for filename in self.BOOTSTRAP_FILES:
            file_path = self.workspace / filename
            if file_path.exists():
                content = file_path.read_text(encoding="utf-8")
                parts.append(f"## {filename}\n\n{content}")

        return "\n\n".join(parts) if parts else ""

    @classmethod
    def extract_runtime_metadata(
        cls,
        metadata: Mapping[str, Any] | None = None,
    ) -> dict[str, str]:
        """Normalize runtime metadata for prompt injection, auditing, and tool context."""
        if not metadata:
            return {}

        raw = dict(metadata)
        normalized: dict[str, str] = {}
        for key in cls.AUDIT_METADATA_KEYS:
            cleaned = cls._clean_runtime_value(raw.get(key))
            if cleaned is not None:
                normalized[key] = cleaned

        persona_profile = raw.get("persona_profile")
        if "persona_profile_id" not in normalized:
            normalized_persona_id = cls._extract_persona_field(
                persona_profile,
                "persona_profile_id",
                "profile_id",
                "id",
                "slug",
                "name",
                "label",
            )
            if normalized_persona_id is not None:
                normalized["persona_profile_id"] = normalized_persona_id
        persona_field_candidates = {
            "persona_tone_style": (
                "persona_tone_style",
                "tone_style",
                "tone",
            ),
            "persona_reply_length": (
                "persona_reply_length",
                "reply_length",
                "length",
            ),
            "persona_proactivity": (
                "persona_proactivity",
                "proactivity",
                "initiative",
            ),
            "persona_voice_style": (
                "persona_voice_style",
                "voice_style",
                "voice",
                "speaking_style",
                "style",
            ),
        }
        for target_key, candidate_keys in persona_field_candidates.items():
            if target_key in normalized:
                continue
            normalized_value = cls._extract_persona_field(
                persona_profile,
                *candidate_keys,
            )
            if normalized_value is not None:
                normalized[target_key] = normalized_value
        return normalized

    @classmethod
    def _build_trusted_runtime_metadata(
        cls,
        channel: str | None,
        chat_id: str | None,
        metadata: Mapping[str, Any] | None = None,
    ) -> str | None:
        """Build trusted runtime metadata appended to the system prompt."""
        runtime_metadata = cls.extract_runtime_metadata(metadata)
        lines = [
            "# Trusted Runtime Metadata",
            "The following values come from the product runtime, not the user. "
            "Use them as authoritative context when choosing behavior, tone, and tool usage.",
        ]
        if channel:
            lines.append(f"- Active Channel: {channel}")
        if chat_id:
            lines.append(f"- Active Chat ID: {chat_id}")
        for key, label in cls._TRUSTED_RUNTIME_LABELS:
            value = runtime_metadata.get(key)
            if value is not None:
                lines.append(f"- {label}: {value}")

        if len(lines) == 2:
            return None
        return "\n".join(lines)

    def build_messages(
        self,
        history: list[dict[str, Any]],
        current_message: str,
        skill_names: list[str] | None = None,
        media: list[str] | None = None,
        channel: str | None = None,
        chat_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        """Build the complete message list for an LLM call."""
        runtime_ctx = self._build_runtime_context(channel, chat_id, metadata)
        trusted_runtime = self._build_trusted_runtime_metadata(channel, chat_id, metadata)
        directive = self._build_reply_language_directive(metadata)
        conversation_style = self._build_everyday_conversation_style(metadata)
        message_text = current_message
        if directive:
            message_text = f"{directive}\n\n{current_message}"
        user_content = self._build_user_content(message_text, media)

        # Merge runtime context and user content into a single user message
        # to avoid consecutive same-role messages that some providers reject.
        if isinstance(user_content, str):
            merged = f"{runtime_ctx}\n\n{user_content}"
        else:
            merged = [{"type": "text", "text": runtime_ctx}] + user_content

        system_prompt = self.build_system_prompt(skill_names)
        if trusted_runtime:
            system_prompt = f"{system_prompt}\n\n---\n\n{trusted_runtime}"
        if conversation_style:
            system_prompt = f"{system_prompt}\n\n---\n\n{conversation_style}"

        return [
            {"role": "system", "content": system_prompt},
            *history,
            {"role": "user", "content": merged},
        ]

    @staticmethod
    def _build_reply_language_directive(metadata: dict[str, Any] | None) -> str | None:
        """Build an internal per-turn response directive from trusted metadata."""
        if not metadata:
            return None
        reply_language = str(metadata.get("reply_language") or "").strip()
        if not reply_language:
            return None
        return (
            f"[Internal Response Directive]\n"
            f"Reply in {reply_language} for this turn.\n"
            f"Keep the reply natural and easy to speak aloud; match the active persona's reply length."
        )

    @classmethod
    def _build_everyday_conversation_style(
        cls,
        metadata: Mapping[str, Any] | None,
    ) -> str:
        runtime_metadata = cls.extract_runtime_metadata(metadata)
        scene_mode = runtime_metadata.get("scene_mode") or "focus"
        tone_style = runtime_metadata.get("persona_tone_style") or "clear"
        reply_length = runtime_metadata.get("persona_reply_length") or "medium"
        proactivity = runtime_metadata.get("persona_proactivity") or "balanced"

        lines = [
            "# Everyday Conversation Style",
            "Use this for ordinary chat, voice replies, and personal-assistant turns. "
            "Task instructions, safety rules, and tool results still take priority.",
            "- Sound like a capable person nearby, not a formal report. Mirror the user's language and energy.",
            "- For Chinese, use natural spoken Mandarin: short sentences, concrete wording, and light everyday phrasing.",
            "- Acknowledge the user's real-life situation when it is visible: tiredness, rushing, meals, errands, classes, work, travel, plans, or device trouble.",
            "- Prefer one concrete next step over generic encouragement. Ask at most one follow-up question when a detail is missing.",
            "- Avoid canned openings like 'As an AI', corporate wording, excessive apologies, emojis, and long markdown for casual voice turns.",
            "- Natural Chinese examples to adapt, not copy mechanically: '我懂，先别急。', '可以，我帮你先处理这一步。', '那我们先把它拆小一点。'",
            f"- Active scene: {scene_mode}. Tone: {tone_style}. Reply length: {reply_length}. Proactivity: {proactivity}.",
        ]
        if scene_mode == "meeting":
            lines.append("- Meeting mode: stay very brief and quiet, but still sound natural.")
        elif scene_mode == "offwork":
            lines.append("- Off-work mode: warmer and more relaxed is okay, while still being useful.")
        else:
            lines.append("- Focus mode: concise, practical, and gently momentum-building.")
        if reply_length == "short":
            lines.append("- Keep most replies to one or two sentences unless the user asks for detail.")
        elif reply_length == "expanded":
            lines.append("- Expanded replies may include a small observation plus one practical next step.")
        if proactivity == "high":
            lines.append("- When useful, volunteer one specific action you can take next.")
        return "\n".join(lines)

    def _build_user_content(self, text: str, media: list[str] | None) -> str | list[dict[str, Any]]:
        """Build user message content with optional base64-encoded images."""
        if not media:
            return text

        images = []
        for path in media:
            p = Path(path)
            mime, _ = mimetypes.guess_type(path)
            if not p.is_file() or not mime or not mime.startswith("image/"):
                continue
            b64 = base64.b64encode(p.read_bytes()).decode()
            images.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})

        if not images:
            return text
        return images + [{"type": "text", "text": text}]

    def add_tool_result(
        self, messages: list[dict[str, Any]],
        tool_call_id: str, tool_name: str, result: str,
    ) -> list[dict[str, Any]]:
        """Add a tool result to the message list."""
        messages.append({"role": "tool", "tool_call_id": tool_call_id, "name": tool_name, "content": result})
        return messages

    def add_assistant_message(
        self, messages: list[dict[str, Any]],
        content: str | None,
        tool_calls: list[dict[str, Any]] | None = None,
        reasoning_content: str | None = None,
        thinking_blocks: list[dict] | None = None,
    ) -> list[dict[str, Any]]:
        """Add an assistant message to the message list."""
        msg: dict[str, Any] = {"role": "assistant", "content": content}
        if tool_calls:
            msg["tool_calls"] = tool_calls
        if reasoning_content is not None:
            msg["reasoning_content"] = reasoning_content
        if thinking_blocks:
            msg["thinking_blocks"] = thinking_blocks
        messages.append(msg)
        return messages

    @staticmethod
    def _clean_runtime_value(value: Any) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            cleaned = value.strip()
            return cleaned or None
        if isinstance(value, (int, float, bool)):
            cleaned = str(value).strip()
            return cleaned or None
        return None

    @classmethod
    def _extract_persona_field(
        cls,
        persona_profile: Any,
        *candidate_keys: str,
    ) -> str | None:
        if isinstance(persona_profile, Mapping):
            for key in candidate_keys:
                cleaned = cls._clean_runtime_value(persona_profile.get(key))
                if cleaned is not None:
                    return cleaned
            return None
        return cls._clean_runtime_value(persona_profile)
