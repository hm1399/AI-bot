"""
WebSocket 消息协议定义

设备 ↔ 服务端之间的 JSON 消息格式：
{"type": "xxx", "data": {...}, "timestamp": 1234567890}
"""
from __future__ import annotations

import time
from enum import Enum
from typing import Any


class DeviceMessageType(str, Enum):
    """设备 → 服务端 消息类型。"""
    AUDIO_END = "audio_end"
    TOUCH_EVENT = "touch_event"
    SHAKE_EVENT = "shake_event"
    DEVICE_STATUS = "device_status"
    TEXT_INPUT = "text_input"  # 调试用


class ServerMessageType(str, Enum):
    """服务端 → 设备 消息类型。"""
    STATE_CHANGE = "state_change"
    DISPLAY_UPDATE = "display_update"
    STATUS_BAR_UPDATE = "status_bar_update"
    FACE_UPDATE = "face_update"
    LED_CONTROL = "led_control"
    AUDIO_PLAY = "audio_play"
    AUDIO_PLAY_END = "audio_play_end"
    TEXT_REPLY = "text_reply"


def make_server_message(msg_type: ServerMessageType, data: dict[str, Any] | None = None) -> dict:
    """构造服务端 → 设备的 JSON 消息。"""
    return {
        "type": msg_type.value,
        "data": data or {},
        "timestamp": int(time.time()),
    }
