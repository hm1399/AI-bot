from __future__ import annotations

import random
from typing import Any

from .models import build_physical_interaction_result, clean_optional_string


def _normalize_reply_language(value: Any) -> str | None:
    cleaned = clean_optional_string(value)
    if cleaned is None:
        return None
    lowered = cleaned.lower()
    if lowered.startswith("en") or lowered.startswith("english"):
        return "English"
    if lowered.startswith("zh") or lowered.startswith("chinese"):
        return "Chinese"
    return cleaned


def _prefers_english_reply(value: Any) -> bool:
    return _normalize_reply_language(value) == "English"


_FALLBACK_CONTEXT_ITEMS_ZH: tuple[dict[str, str], ...] = (
    {
        "kind": "fallback",
        "title": "当前节奏",
        "detail": "先别急着切换任务。我们先把眼前这一小步做完。",
    },
    {
        "kind": "fallback",
        "title": "下一步",
        "detail": "现在适合从最容易开始的一步做起，先让状态动起来。",
    },
    {
        "kind": "fallback",
        "title": "主线",
        "detail": "先抓住当前主线，不用一下子想太多，往前推进一点就好。",
    },
    {
        "kind": "fallback",
        "title": "休息一下",
        "detail": "如果刚才有点卡，先喝口水，回来只做一个最小动作。",
    },
    {
        "kind": "fallback",
        "title": "出门前",
        "detail": "出门前先扫一眼钥匙、手机和耳机，少一件都会很麻烦。",
    },
    {
        "kind": "fallback",
        "title": "饭点提醒",
        "detail": "如果已经到饭点，先别硬扛。吃点东西再继续，效率会稳一点。",
    },
    {
        "kind": "fallback",
        "title": "消息处理",
        "detail": "消息可以先分轻重。现在只回最影响后续安排的那一条。",
    },
    {
        "kind": "fallback",
        "title": "收尾",
        "detail": "先把桌面和脑子都收一下尾，再开下一件事会轻松很多。",
    },
    {
        "kind": "fallback",
        "title": "睡前",
        "detail": "如果已经很晚了，先记下明天第一步，不要现在硬展开。",
    },
)

_FALLBACK_CONTEXT_ITEMS_EN: tuple[dict[str, str], ...] = (
    {
        "kind": "fallback",
        "title": "current pace",
        "detail": "Let's not switch too quickly. Finish one small step first.",
    },
    {
        "kind": "fallback",
        "title": "next step",
        "detail": "Start with the easiest next step. Just get things moving.",
    },
    {
        "kind": "fallback",
        "title": "main thread",
        "detail": "Stay with the main thread for now. Move it forward a little.",
    },
    {
        "kind": "fallback",
        "title": "small break",
        "detail": "If you feel stuck, take a sip of water and come back to one tiny action.",
    },
    {
        "kind": "fallback",
        "title": "leaving home",
        "detail": "Before heading out, check keys, phone, and earbuds. Missing one will slow you down.",
    },
    {
        "kind": "fallback",
        "title": "meal time",
        "detail": "If it is meal time, do not push through on empty. Eat something and continue steadier.",
    },
    {
        "kind": "fallback",
        "title": "messages",
        "detail": "Sort messages by impact. Reply to the one that affects the next plan first.",
    },
    {
        "kind": "fallback",
        "title": "wrap up",
        "detail": "Close one loose end before opening the next thing. It will feel lighter.",
    },
    {
        "kind": "fallback",
        "title": "late night",
        "detail": "If it is already late, write down tomorrow's first step instead of expanding the task now.",
    },
)

_CONTEXT_TEMPLATES_ZH: dict[str, tuple[str, ...]] = {
    "conversation": (
        "刚才你提到「{title}」。我们可以先把它拆成一个马上能做的小动作。",
        "我还记得刚才聊到「{title}」。先抓住这一点继续推进就好。",
        "这句我接住了：「{title}」。先不用展开太大，挑一个最顺手的入口。",
        "如果继续沿着「{title}」走，现在最适合先补一个小缺口。",
        "「{title}」这件事先别丢。我们先把下一步说清楚。",
    ),
    "current_task": (
        "你现在的重点应该还是「{title}」。先把它收一下尾，再切下一件事。",
        "先回到「{title}」吧。补上最关键的一步，后面会顺很多。",
        "当前这条线是「{title}」。先处理最卡的地方，不用一次做完。",
        "别急着换频道，先把「{title}」推进到能停手的位置。",
        "「{title}」还在主线上。现在先做一个能看见进展的小动作。",
    ),
    "pending_action": (
        "还有一个动作「{title}」在等你确认。先决定要不要继续执行。",
        "「{title}」还没有处理完。如果它还重要，我们先把确认处理掉。",
        "我看到「{title}」还悬着。先点头或取消，别让它一直占着注意力。",
        "「{title}」需要你拍板。先把这个定了，再继续后面的事。",
        "这个动作「{title}」还在等确认。现在处理掉会清爽很多。",
    ),
    "task": (
        "待办里还有「{title}」。先做最小的一步，不用一次做太大。",
        "要不先从「{title}」开始？处理开头那一步就够了。",
        "「{title}」可以先拆小。现在只做第一步就行。",
        "先碰一下「{title}」，哪怕只整理材料，也算让它动起来。",
        "如果今天要推进「{title}」，先给它留一小段安静时间。",
    ),
    "event": (
        "你后面有「{title}」。先看一下时间，给自己留点缓冲。",
        "别忘了「{title}」。现在先确认准备事项，免得临近才赶。",
        "「{title}」快到的话，先留出路上或切换状态的时间。",
        "关于「{title}」，现在最实用的是先确认地点、材料和提醒。",
        "有「{title}」在后面，当前这件事最好早点收口。",
    ),
    "reminder": (
        "提醒里有「{title}」。先确认时间和下一步要做什么。",
        "我看到提醒「{title}」。如果已经过了，就先决定保留还是清掉。",
        "「{title}」这条提醒还在。要么顺手做掉，要么改到更合适的时间。",
        "提醒「{title}」不用一直挂着。先判断它是不是现在要处理。",
        "「{title}」可以先放进一个明确时间点，免得脑子一直记着。",
    ),
    "notification": (
        "你有一条通知「{title}」。先判断它是不是现在必须处理。",
        "通知里有「{title}」。先看优先级，再决定要不要打断当前节奏。",
        "「{title}」这条通知先别急着回。先看它会不会影响今天安排。",
        "如果「{title}」不紧急，可以先放一边，别打断当前节奏。",
        "通知「{title}」已经出现了。现在只处理会拖住后续的部分。",
    ),
    "summary": (
        "现在的整体情况是「{title}」。可以先按这个调整下一步节奏。",
        "我看了一下当前概览：「{title}」。先处理最影响节奏的那一项。",
        "当前概览是「{title}」。先不用全盘重排，抓最明显的一项就好。",
        "从现在的状态看，「{title}」值得先看一眼，避免后面被动。",
        "整体上是「{title}」。先做一个能降低压力的小动作。",
    ),
    "fallback": (
        "{detail}",
        "先这样来：{detail}",
        "给你一个生活化的小提醒：{detail}",
        "不用想太复杂，{detail}",
    ),
}

_CONTEXT_TEMPLATES_EN: dict[str, tuple[str, ...]] = {
    "conversation": (
        'You mentioned "{title}" earlier. Let\'s turn it into one small next action.',
        'I remember we talked about "{title}". Keep it narrow and move that point forward.',
        'I caught "{title}". Do not expand it too much; pick the easiest entry point.',
        'If we stay with "{title}", the useful move now is to fill one small gap.',
        'Do not drop "{title}" yet. First make the next step clear.',
    ),
    "current_task": (
        'Your current focus is still "{title}". Finish one part of it before switching.',
        'Let\'s come back to "{title}". Fill in the most important missing step first.',
        'The main thread is "{title}". Work on the stuck part, not the whole thing.',
        'Do not change lanes too fast. Bring "{title}" to a clean stopping point first.',
        '"{title}" is still the main track. Do one visible small step now.',
    ),
    "pending_action": (
        'There is still a pending action: "{title}". Decide whether it should continue first.',
        '"{title}" is still waiting for confirmation. If it matters, handle that first.',
        'I see "{title}" is still hanging. Confirm or cancel it so it stops taking attention.',
        '"{title}" needs your call. Decide that before moving on.',
        'The action "{title}" is still waiting. Clearing it now will make the flow cleaner.',
    ),
    "task": (
        'You still have "{title}" on your task list. Start with the smallest useful step.',
        'Maybe start with "{title}" now. Just handle the opening move.',
        'Break "{title}" smaller. The first step is enough for now.',
        'Touch "{title}" briefly, even if that only means gathering the material.',
        'If "{title}" needs progress today, give it one quiet block.',
    ),
    "event": (
        'You have "{title}" coming up. Check the time and leave yourself some buffer.',
        'Don\'t forget "{title}". Confirm the preparation before it gets close.',
        'If "{title}" is coming up soon, leave time for travel or context switching.',
        'For "{title}", the practical check is place, materials, and reminder.',
        'With "{title}" ahead, it is better to wrap the current thing early.',
    ),
    "reminder": (
        'There is a reminder for "{title}". Confirm the timing and the next action.',
        'I see the reminder "{title}". If it is stale, decide whether to keep or clear it.',
        'The reminder "{title}" is still there. Do it now or move it to a better time.',
        'Do not let "{title}" keep floating in your head. Decide whether it is for now.',
        'Put "{title}" at a clear time so your mind does not have to keep holding it.',
    ),
    "notification": (
        'You have a notification: "{title}". Decide whether it needs attention now.',
        'There is a notification for "{title}". Check priority before breaking your flow.',
        'Do not rush to answer "{title}". First check whether it affects today\'s plan.',
        'If "{title}" is not urgent, let it wait and keep your current rhythm.',
        'The notification "{title}" is visible. Only handle the part that blocks what comes next.',
    ),
    "summary": (
        'Here is the current situation: "{title}". Use it to tune your next step.',
        'From the current overview: "{title}". Handle what affects your flow most.',
        'The current overview is "{title}". No need to re-plan everything; pick the obvious item.',
        'From the current state, "{title}" is worth a quick look before it becomes reactive.',
        'Overall, it is "{title}". Do one small action that lowers pressure.',
    ),
    "fallback": (
        "{detail}",
        "Try this: {detail}",
        "Small everyday reminder: {detail}",
        "Keep it simple: {detail}",
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
        _ = physical_state
        _ = daily_shake_state
        _ = clean_optional_string(requested_mode)
        return "random"

    def route_shake(
        self,
        *,
        session_id: str | None,
        scene_mode: str,
        physical_state: dict[str, Any],
        daily_shake_state: dict[str, Any] | None = None,
        requested_mode: str | None = None,
        reply_language: str | None = None,
        context: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        prefer_english = _prefers_english_reply(reply_language)
        blocked_reason = str(
            (physical_state.get("blocked_reasons") or {}).get("shake")
            or physical_state.get("shake_blocked_reason")
            or ""
        ).strip()
        if not physical_state.get("shake_available"):
            return build_physical_interaction_result(
                interaction_kind="shake",
                mode="blocked",
                title="Shake" if prefer_english else "摇一摇",
                short_result="blocked",
                display_text=(
                    "Shake is not available right now."
                    if prefer_english
                    else "当前不适合摇一摇。"
                ),
                voice_text=(
                    "Shake is not available right now."
                    if prefer_english
                    else "当前不适合摇一摇。"
                ),
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
        content = self._pick_contextual_shake_content(
            context=context,
            action_title=str(physical_state.get("pending_action_title") or "").strip() or None,
            action_kind=str(physical_state.get("pending_action_kind") or "").strip() or None,
            prefer_english=prefer_english,
        )
        metadata = {
            "context_source": content.get("context_source"),
            "context_kind": content.get("context_kind"),
            "context_title": content.get("context_title"),
            "context_candidate_count": content.get("context_candidate_count"),
        }
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
                "context_source": content.get("context_source"),
                "context_kind": content.get("context_kind"),
                "context_title": content.get("context_title"),
            },
            metadata={key: value for key, value in metadata.items() if value is not None},
        )

    def _pick_contextual_shake_content(
        self,
        *,
        context: dict[str, Any] | None,
        action_title: str | None = None,
        action_kind: str | None = None,
        prefer_english: bool = False,
    ) -> dict[str, Any]:
        candidates = self._context_candidates(
            context,
            action_title=action_title,
            action_kind=action_kind,
            prefer_english=prefer_english,
        )
        candidate = random.choice(candidates)
        kind = str(candidate.get("kind") or "fallback").strip() or "fallback"
        templates = _CONTEXT_TEMPLATES_EN if prefer_english else _CONTEXT_TEMPLATES_ZH
        template_pool = templates.get(kind) or templates["fallback"]
        text = random.choice(template_pool).format(
            title=str(candidate.get("title") or "").strip(),
            detail=str(candidate.get("detail") or "").strip(),
        )
        return {
            "title": "Context Shake" if prefer_english else "摇一摇随机回复",
            "short_result": "context_random_ready",
            "display_text": text,
            "voice_text": text,
            "animation_hint": "celebrate",
            "led_hint": "purple",
            "context_source": str(candidate.get("source") or kind),
            "context_kind": kind,
            "context_title": str(candidate.get("title") or "").strip() or None,
            "context_candidate_count": len(candidates),
        }

    def _context_candidates(
        self,
        context: dict[str, Any] | None,
        *,
        action_title: str | None,
        action_kind: str | None,
        prefer_english: bool,
    ) -> list[dict[str, str]]:
        candidates: list[dict[str, str]] = []
        subject = self._decision_subject(
            action_title=action_title,
            action_kind=action_kind,
        )
        if subject is not None:
            candidates.append({
                "kind": "pending_action",
                "source": "computer_control",
                "title": subject,
            })
        payload = dict(context or {})
        for item in payload.get("candidates") or []:
            if not isinstance(item, dict):
                continue
            title = clean_optional_string(item.get("title"))
            if title is None:
                continue
            kind = clean_optional_string(item.get("kind")) or "summary"
            source = clean_optional_string(item.get("source")) or kind
            detail = clean_optional_string(item.get("detail")) or title
            candidates.append({
                "kind": kind,
                "source": source,
                "title": title,
                "detail": detail,
            })
        if candidates:
            return candidates[:20]
        fallback = _FALLBACK_CONTEXT_ITEMS_EN if prefer_english else _FALLBACK_CONTEXT_ITEMS_ZH
        return [dict(item) for item in fallback]

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
