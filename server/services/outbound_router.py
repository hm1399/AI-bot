from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING, Any

from loguru import logger

from channels.device_channel import DEVICE_CHANNEL, DeviceChannel
from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.whatsapp import WhatsAppChannel
from services.desktop_voice_service import DESKTOP_VOICE_CHANNEL
from services.outbound_lanes import (
    LaneFullError,
    SerialDispatchLane,
    lane_snapshot_map,
    outbound_message_is_droppable,
)

if TYPE_CHECKING:
    from services.desktop_voice_service import DesktopVoiceService

WHATSAPP_CHANNEL = "whatsapp"
APP_CHANNEL = "app"

DEVICE_VOICE_LANE = "device_voice_lane"
DESKTOP_VOICE_LANE = "desktop_voice_lane"
EXTERNAL_CHANNELS_LANE = "external_channels_lane"
APP_REALTIME_LANE = "app_realtime_lane"

_DEFAULT_LANE_MAXSIZES = {
    DEVICE_VOICE_LANE: 32,
    DESKTOP_VOICE_LANE: 32,
    EXTERNAL_CHANNELS_LANE: 64,
    APP_REALTIME_LANE: 64,
}


class UnifiedOutboundRouter:
    """统一消费 outbound 队列，并按 lane 策略分发到各通道。"""

    def __init__(
        self,
        bus: MessageBus,
        device_channel: DeviceChannel,
        desktop_voice_service: DesktopVoiceService | None = None,
        whatsapp_channel: WhatsAppChannel | None = None,
        *,
        lane_maxsizes: dict[str, int] | None = None,
    ) -> None:
        self.bus = bus
        self.device_channel = device_channel
        self.desktop_voice_service = desktop_voice_service
        self.whatsapp_channel = whatsapp_channel
        self._lane_maxsizes = {
            **_DEFAULT_LANE_MAXSIZES,
            **(lane_maxsizes or {}),
        }
        self._lanes: dict[str, SerialDispatchLane[OutboundMessage]] = {
            DEVICE_VOICE_LANE: SerialDispatchLane(
                DEVICE_VOICE_LANE,
                self._dispatch_device_lane,
                maxsize=self._lane_maxsizes[DEVICE_VOICE_LANE],
                drop_predicate=outbound_message_is_droppable,
            ),
            DESKTOP_VOICE_LANE: SerialDispatchLane(
                DESKTOP_VOICE_LANE,
                self._dispatch_desktop_voice_lane,
                maxsize=self._lane_maxsizes[DESKTOP_VOICE_LANE],
                drop_predicate=outbound_message_is_droppable,
            ),
            EXTERNAL_CHANNELS_LANE: SerialDispatchLane(
                EXTERNAL_CHANNELS_LANE,
                self._dispatch_external_lane,
                maxsize=self._lane_maxsizes[EXTERNAL_CHANNELS_LANE],
                drop_predicate=outbound_message_is_droppable,
            ),
            APP_REALTIME_LANE: SerialDispatchLane(
                APP_REALTIME_LANE,
                self._dispatch_app_lane,
                maxsize=self._lane_maxsizes[APP_REALTIME_LANE],
                drop_predicate=outbound_message_is_droppable,
            ),
        }

    async def run(self) -> None:
        """持续消费 outbound 队列并把消息投递到对应 lane。"""
        self._start_lanes()
        logger.info("统一 outbound 路由器已启动")
        try:
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
        finally:
            await self.stop()

    async def stop(self, *, drain: bool = False) -> None:
        for lane in self._lanes.values():
            await lane.close(drain=drain)

    async def route(self, out_msg: OutboundMessage) -> None:
        """根据 channel 把消息投递到对应 lane。"""
        lane_name = self._lane_name_for(out_msg)
        lane = self._lanes[lane_name]
        try:
            accepted = await lane.submit(out_msg)
        except LaneFullError:
            logger.warning(
                "Outbound lane {} 已满，丢弃 channel={} chat_id={}",
                lane_name,
                out_msg.channel,
                out_msg.chat_id,
            )
            return

        if not accepted:
            logger.debug(
                "Outbound lane {} 丢弃可合并消息 channel={}",
                lane_name,
                out_msg.channel,
            )

    def lane_snapshot(self) -> dict[str, dict[str, Any]]:
        return lane_snapshot_map(self._lanes)

    def _start_lanes(self) -> None:
        for lane in self._lanes.values():
            lane.start()

    @staticmethod
    def _lane_name_for(out_msg: OutboundMessage) -> str:
        if out_msg.channel == DEVICE_CHANNEL:
            return DEVICE_VOICE_LANE
        if out_msg.channel == DESKTOP_VOICE_CHANNEL:
            return DESKTOP_VOICE_LANE
        if out_msg.channel == APP_CHANNEL:
            return APP_REALTIME_LANE
        return EXTERNAL_CHANNELS_LANE

    @staticmethod
    def _should_skip_message(out_msg: OutboundMessage) -> bool:
        if out_msg.metadata.get("_progress"):
            return True
        if not out_msg.content:
            return True
        return False

    async def _dispatch_device_lane(self, out_msg: OutboundMessage) -> None:
        if self._should_skip_message(out_msg):
            return
        if out_msg.channel != DEVICE_CHANNEL:
            logger.debug("设备 lane 收到非设备消息: {}", out_msg.channel)
            return

        await self.device_channel.send_outbound(out_msg)
        await self._enqueue_whatsapp_mirror(out_msg)

    async def _dispatch_desktop_voice_lane(self, out_msg: OutboundMessage) -> None:
        if self._should_skip_message(out_msg):
            return
        if out_msg.channel != DESKTOP_VOICE_CHANNEL:
            logger.debug("桌面语音 lane 收到非桌面语音消息: {}", out_msg.channel)
            return

        if self.desktop_voice_service:
            await self.desktop_voice_service.send_outbound(out_msg)
        else:
            logger.warning("Desktop voice service 未启用，忽略消息")
        await self._enqueue_whatsapp_mirror(out_msg)

    async def _dispatch_external_lane(self, out_msg: OutboundMessage) -> None:
        if self._should_skip_message(out_msg):
            return

        if out_msg.channel == WHATSAPP_CHANNEL:
            if self.whatsapp_channel:
                await self.whatsapp_channel.send(out_msg)
                logger.info("发送 WhatsApp 回复: '{}'", out_msg.content[:50])
            else:
                logger.warning("WhatsApp channel 未启用，忽略消息")
            return

        logger.debug("忽略未知 external channel 消息: {}", out_msg.channel)

    async def _dispatch_app_lane(self, out_msg: OutboundMessage) -> None:
        if self._should_skip_message(out_msg):
            return
        logger.debug("App outbound 已由 AppRuntimeService 处理")

    async def _enqueue_whatsapp_mirror(self, out_msg: OutboundMessage) -> None:
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
        external_lane = self._lanes[EXTERNAL_CHANNELS_LANE]
        try:
            accepted = await external_lane.submit(wa_msg)
        except LaneFullError:
            logger.warning(
                "external lane 已满，放弃镜像 {} -> WhatsApp",
                out_msg.channel,
            )
            return

        if accepted:
            logger.info("{} 回复已投递到 WhatsApp lane", out_msg.channel)
