from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from loguru import logger

from channels.device_channel import DEVICE_CHANNEL, DeviceChannel
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.whatsapp import WhatsAppChannel
from services.desktop_voice_service import DESKTOP_VOICE_CHANNEL

if TYPE_CHECKING:
    from services.desktop_voice_service import DesktopVoiceService

WHATSAPP_CHANNEL = "whatsapp"
APP_CHANNEL = "app"


class UnifiedOutboundRouter:
    """统一消费 outbound 队列，并按策略分发到各通道。"""

    def __init__(
        self,
        bus: MessageBus,
        device_channel: DeviceChannel,
        desktop_voice_service: DesktopVoiceService | None = None,
        whatsapp_channel: WhatsAppChannel | None = None,
    ) -> None:
        self.bus = bus
        self.device_channel = device_channel
        self.desktop_voice_service = desktop_voice_service
        self.whatsapp_channel = whatsapp_channel

    async def run(self) -> None:
        """持续消费 outbound 队列并路由消息。"""
        logger.info("统一 outbound 路由器已启动")
        while True:
            try:
                out_msg = await self.bus.consume_outbound()
                await self.route(out_msg)
            except asyncio.CancelledError:
                logger.info("统一 outbound 路由器已停止")
                break
            except Exception:
                logger.exception("Outbound 路由异常")
                await asyncio.sleep(1)

    async def route(self, out_msg: OutboundMessage) -> None:
        """根据 channel 和当前策略派发回复。"""
        if out_msg.metadata.get("_progress"):
            return
        if not out_msg.content:
            return

        if out_msg.channel == DEVICE_CHANNEL:
            await self.device_channel.send_outbound(out_msg)
            await self._mirror_reply_to_whatsapp(out_msg)
            return

        if out_msg.channel == DESKTOP_VOICE_CHANNEL:
            if self.desktop_voice_service:
                await self.desktop_voice_service.send_outbound(out_msg)
            else:
                logger.warning("Desktop voice service 未启用，忽略消息")
            await self._mirror_reply_to_whatsapp(out_msg)
            return

        if out_msg.channel == WHATSAPP_CHANNEL:
            if self.whatsapp_channel:
                await self.whatsapp_channel.send(out_msg)
                logger.info("发送 WhatsApp 回复: '{}'", out_msg.content[:50])
            else:
                logger.warning("WhatsApp channel 未启用，忽略消息")
            return

        if out_msg.channel == APP_CHANNEL:
            logger.debug("App outbound 已由 AppRuntimeService 处理")
            return

        logger.debug("忽略未知 channel 消息: {}", out_msg.channel)

    async def _mirror_reply_to_whatsapp(self, out_msg: OutboundMessage) -> None:
        """Demo 模式：把设备相关回复镜像到最近活跃的 WhatsApp 会话。"""
        if not self.whatsapp_channel:
            return
        if out_msg.channel == DESKTOP_VOICE_CHANNEL:
            interaction_surface = str(out_msg.metadata.get("interaction_surface") or "").strip()
            if interaction_surface != "device_press":
                return

        chat_id = self.whatsapp_channel.last_inbound_chat_id
        if not chat_id:
            return

        wa_msg = OutboundMessage(
            channel=WHATSAPP_CHANNEL,
            chat_id=chat_id,
            content=out_msg.content,
        )
        await self.whatsapp_channel.send(wa_msg)
        logger.info("{} 回复已镜像转发到 WhatsApp", out_msg.channel)
