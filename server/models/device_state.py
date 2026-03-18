"""
设备状态机

定义 ESP32 设备的运行状态及合法状态转换规则。
服务端维护设备当前状态，状态变化时自动通知设备。
"""
from __future__ import annotations

from enum import Enum


class DeviceState(str, Enum):
    """设备运行状态。"""
    IDLE = "IDLE"              # 空闲，等待用户输入
    LISTENING = "LISTENING"    # 正在录音（接收音频帧）
    PROCESSING = "PROCESSING"  # 正在处理（ASR + LLM）
    SPEAKING = "SPEAKING"      # 正在播放语音回复
    ERROR = "ERROR"            # 异常状态


# 合法的状态转换表: {当前状态: {允许转换到的状态集合}}
VALID_TRANSITIONS: dict[DeviceState, set[DeviceState]] = {
    DeviceState.IDLE: {
        DeviceState.LISTENING,   # 用户开始说话
        DeviceState.PROCESSING,  # 收到文字输入，直接处理
        DeviceState.SPEAKING,    # 主动播报（如摇一摇触发）
        DeviceState.ERROR,
    },
    DeviceState.LISTENING: {
        DeviceState.PROCESSING,  # 录音结束，开始识别
        DeviceState.IDLE,        # 录音取消/太短
        DeviceState.ERROR,
    },
    DeviceState.PROCESSING: {
        DeviceState.SPEAKING,    # LLM 回复完成，开始播放
        DeviceState.IDLE,        # 处理失败/空结果
        DeviceState.ERROR,
    },
    DeviceState.SPEAKING: {
        DeviceState.IDLE,        # 播放结束
        DeviceState.ERROR,
    },
    DeviceState.ERROR: {
        DeviceState.IDLE,        # 错误恢复
    },
}

# 各状态对应的屏幕显示提示文字（不使用 emoji，ST7789 默认字库不支持）
STATE_DISPLAY_HINTS: dict[DeviceState, str] = {
    DeviceState.IDLE: "",
    DeviceState.LISTENING: "",
    DeviceState.PROCESSING: "",
    DeviceState.SPEAKING: "",
    DeviceState.ERROR: "Error",
}
