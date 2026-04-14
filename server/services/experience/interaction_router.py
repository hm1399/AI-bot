from __future__ import annotations

from typing import Any

from .models import SHAKE_MODES, build_physical_interaction_result, clean_optional_string


class ExperienceInteractionRouter:
    def pick_shake_mode(self, *, scene_mode: str, requested_mode: str | None = None) -> str:
        requested = clean_optional_string(requested_mode)
        if requested in SHAKE_MODES and (requested != "random" or scene_mode == "offwork"):
            return str(requested)
        if scene_mode == "offwork":
            return "random"
        if scene_mode == "meeting":
            return "decision"
        return "fortune"

    def route_shake(
        self,
        *,
        session_id: str | None,
        scene_mode: str,
        physical_state: dict[str, Any],
        requested_mode: str | None = None,
    ) -> dict[str, Any]:
        blocked_reason = str(
            (physical_state.get("blocked_reasons") or {}).get("shake")
            or physical_state.get("shake_blocked_reason")
            or ""
        ).strip()
        if not physical_state.get("shake_available"):
            return build_physical_interaction_result(
                interaction_kind="shake",
                mode="blocked",
                title="摇一摇",
                short_result="blocked",
                display_text="当前不适合摇一摇。",
                voice_text="当前不适合摇一摇。",
                animation_hint="idle",
                history_entry={
                    "scene_mode": scene_mode,
                    "session_id": session_id,
                    "blocked_reason": blocked_reason or "unavailable",
                },
                metadata={"blocked_reason": blocked_reason or "unavailable"},
            )

        mode = self.pick_shake_mode(scene_mode=scene_mode, requested_mode=requested_mode)
        if mode == "decision":
            return build_physical_interaction_result(
                interaction_kind="shake",
                mode="decision",
                title="随机决策",
                short_result="decision_ready",
                display_text="随机决策：先推进当前最阻塞的一步。",
                voice_text="随机决策，先推进当前最阻塞的一步。",
                animation_hint="focus",
                led_hint="blue",
                history_entry={
                    "scene_mode": scene_mode,
                    "session_id": session_id,
                    "mode": "decision",
                },
            )
        if mode == "random":
            return build_physical_interaction_result(
                interaction_kind="shake",
                mode="random",
                title="随机模式",
                short_result="random_ready",
                display_text="随机模式：给自己三分钟，先收一个最小闭环。",
                voice_text="随机模式，给自己三分钟，先收一个最小闭环。",
                animation_hint="celebrate",
                led_hint="purple",
                history_entry={
                    "scene_mode": scene_mode,
                    "session_id": session_id,
                    "mode": "random",
                },
            )
        return build_physical_interaction_result(
            interaction_kind="shake",
            mode="fortune",
            title="今日提示",
            short_result="fortune_ready",
            display_text="今日提示：稳住节奏，先把当前主线做实。",
            voice_text="今日提示，稳住节奏，先把当前主线做实。",
            animation_hint="idle",
            led_hint="blue",
            history_entry={
                "scene_mode": scene_mode,
                "session_id": session_id,
                "mode": "fortune",
            },
        )
