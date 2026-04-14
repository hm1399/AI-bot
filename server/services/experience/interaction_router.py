from __future__ import annotations

from typing import Any

from .models import build_physical_interaction_result, clean_optional_string


_SHAKE_CONTENT_POOLS: dict[str, tuple[dict[str, str | None], ...]] = {
    "decision": (
        {
            "title": "随机决策",
            "short_result": "decision_ready",
            "display_text": "随机决策：先推进当前最阻塞的一步。",
            "voice_text": "随机决策，先推进当前最阻塞的一步。",
            "animation_hint": "focus",
            "led_hint": "blue",
        },
        {
            "title": "随机决策",
            "short_result": "decision_ready",
            "display_text": "随机决策：先选最容易开始的一步，马上动手。",
            "voice_text": "随机决策，先选最容易开始的一步，马上动手。",
            "animation_hint": "focus",
            "led_hint": "blue",
        },
        {
            "title": "随机决策",
            "short_result": "decision_ready",
            "display_text": "随机决策：别再横跳了，先把当前待确认动作定下来。",
            "voice_text": "随机决策，别再横跳了，先把当前待确认动作定下来。",
            "animation_hint": "focus",
            "led_hint": "blue",
        },
    ),
    "fortune": (
        {
            "title": "今日提示",
            "short_result": "fortune_ready",
            "display_text": "今日提示：稳住节奏，先把当前主线做实。",
            "voice_text": "今日提示，稳住节奏，先把当前主线做实。",
            "animation_hint": "idle",
            "led_hint": "blue",
        },
        {
            "title": "今日提示",
            "short_result": "fortune_ready",
            "display_text": "今日提示：先收一个最小闭环，再决定下一步。",
            "voice_text": "今日提示，先收一个最小闭环，再决定下一步。",
            "animation_hint": "idle",
            "led_hint": "blue",
        },
        {
            "title": "今日提示",
            "short_result": "fortune_ready",
            "display_text": "今日提示：先把最容易拖延的一步做掉，后面会顺很多。",
            "voice_text": "今日提示，先把最容易拖延的一步做掉，后面会顺很多。",
            "animation_hint": "idle",
            "led_hint": "blue",
        },
    ),
    "random": (
        {
            "title": "随机模式",
            "short_result": "random_ready",
            "display_text": "随机模式：给自己三分钟，先收一个最小闭环。",
            "voice_text": "随机模式，给自己三分钟，先收一个最小闭环。",
            "animation_hint": "celebrate",
            "led_hint": "purple",
        },
        {
            "title": "随机模式",
            "short_result": "random_ready",
            "display_text": "随机模式：先完成眼前最短的一步，再看要不要继续。",
            "voice_text": "随机模式，先完成眼前最短的一步，再看要不要继续。",
            "animation_hint": "celebrate",
            "led_hint": "purple",
        },
        {
            "title": "随机模式",
            "short_result": "random_ready",
            "display_text": "随机模式：现在就挑一个最不费脑子的动作，做完再切下一步。",
            "voice_text": "随机模式，现在就挑一个最不费脑子的动作，做完再切下一步。",
            "animation_hint": "celebrate",
            "led_hint": "purple",
        },
    ),
}


class ExperienceInteractionRouter:
    def pick_shake_mode(
        self,
        *,
        scene_mode: str,
        physical_state: dict[str, Any] | None = None,
        daily_shake_state: dict[str, Any] | None = None,
        requested_mode: str | None = None,
    ) -> str:
        _ = scene_mode
        _ = clean_optional_string(requested_mode)
        physical = dict(physical_state or {})
        daily = dict(daily_shake_state or {})
        if bool(physical.get("pending_confirmation")):
            return "decision"
        if int(daily.get("valid_shake_count") or 0) <= 0:
            return "fortune"
        return "random"

    def route_shake(
        self,
        *,
        session_id: str | None,
        scene_mode: str,
        physical_state: dict[str, Any],
        daily_shake_state: dict[str, Any] | None = None,
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

        mode = self.pick_shake_mode(
            scene_mode=scene_mode,
            physical_state=physical_state,
            daily_shake_state=daily_shake_state,
            requested_mode=requested_mode,
        )
        content = self._pick_shake_content(
            mode,
            session_id=session_id,
            scene_mode=scene_mode,
            daily_shake_state=daily_shake_state,
            action_title=str(physical_state.get("pending_action_title") or "").strip() or None,
            action_kind=str(physical_state.get("pending_action_kind") or "").strip() or None,
        )
        return build_physical_interaction_result(
            interaction_kind="shake",
            mode=mode,
            title=str(content["title"]),
            short_result=str(content["short_result"]),
            display_text=str(content["display_text"]),
            voice_text=str(content["voice_text"]),
            animation_hint=clean_optional_string(content.get("animation_hint")),
            led_hint=clean_optional_string(content.get("led_hint")),
            history_entry={
                "scene_mode": scene_mode,
                "session_id": session_id,
                "mode": mode,
            },
        )

    def _pick_shake_content(
        self,
        mode: str,
        *,
        session_id: str | None,
        scene_mode: str,
        daily_shake_state: dict[str, Any] | None,
        action_title: str | None = None,
        action_kind: str | None = None,
    ) -> dict[str, str | None]:
        if mode == "decision":
            decision_subject = self._decision_subject(
                action_title=action_title,
                action_kind=action_kind,
            )
            if decision_subject is not None:
                return {
                    "title": "随机决策",
                    "short_result": "decision_ready",
                    "display_text": f"随机决策：这次先定「{decision_subject}」。",
                    "voice_text": f"随机决策，这次先定{decision_subject}。",
                    "animation_hint": "focus",
                    "led_hint": "blue",
                }
        pool = _SHAKE_CONTENT_POOLS.get(mode) or _SHAKE_CONTENT_POOLS["fortune"]
        if len(pool) == 1:
            return dict(pool[0])
        daily = dict(daily_shake_state or {})
        seed_input = "|".join(
            [
                mode,
                str(session_id or ""),
                str(scene_mode or ""),
                str(daily.get("date") or ""),
                str(daily.get("valid_shake_count") or 0),
            ]
        )
        index = sum(ord(ch) for ch in seed_input) % len(pool)
        return dict(pool[index])

    @staticmethod
    def _decision_subject(
        *,
        action_title: str | None,
        action_kind: str | None,
    ) -> str | None:
        if action_title:
            return action_title
        if not action_kind:
            return None
        return action_kind.replace("_", " ").strip() or None
