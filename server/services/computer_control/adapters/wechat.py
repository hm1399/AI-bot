from __future__ import annotations

from typing import Any

from ..models import ComputerControlError


class WeChatAdapter:
    def __init__(self, macos_adapter: Any) -> None:
        self.macos_adapter = macos_adapter

    async def prepare_message(
        self,
        *,
        contact_alias: str,
        message: str,
        experimental_ui: bool = False,
    ) -> dict[str, Any]:
        await self.macos_adapter.open_app(app="WeChat")
        await self.macos_adapter.clipboard_set(text=message)

        manual_steps = [
            f"Switch to the WeChat conversation for {contact_alias}.",
            "Paste the copied draft into the compose box.",
            "Review the draft before sending it manually.",
        ]
        if experimental_ui:
            manual_steps.insert(
                1,
                "Experimental UI automation is enabled, but this build still keeps send as a manual confirmation step.",
            )

        return {
            "delivery_mode": "manual_step_required",
            "send_available": False,
            "contact_alias": contact_alias,
            "draft_copied_to_clipboard": True,
            "manual_steps": manual_steps,
        }

    async def send_prepared_message(
        self,
        *,
        prepared_action_id: str,
    ) -> dict[str, Any]:
        raise ComputerControlError(
            code="adapter_unavailable",
            message=(
                "wechat send automation is not available in this build; "
                "use the prepared draft and confirm manually"
            ),
            status=409,
            details={"prepared_action_id": prepared_action_id},
        )
