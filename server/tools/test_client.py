"""
WebSocket 测试客户端 — 模拟 ESP32 设备

用法:
    python tools/test_client.py [--url ws://localhost:8765/ws/device] [--token your-device-token]

功能:
    - 连接 WebSocket 服务端
    - 交互式输入文字消息，打印 AI 回复
    - 发送音频文件测试语音链路: 输入 'audio <文件路径>' 发送 PCM/WAV 文件
    - 模拟触摸事件: touch single / touch double / touch long_press / touch long_release
    - 模拟摇一摇事件: shake
    - 模拟设备状态上报: status <battery> <wifi_rssi>
    - 查看设备当前状态: state

音频测试:
    > audio test.pcm        # 发送 PCM 文件
    > audio test.wav         # 发送 WAV 文件 (自动跳过 WAV 头)
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import struct
import sys
import time
import wave

import aiohttp


DEFAULT_URL = "ws://localhost:8765/ws/device"

# 音频发送的 chunk 大小 (模拟 ESP32 分帧发送)
AUDIO_CHUNK_SIZE = 4096


def load_audio_file(path: str) -> bytes:
    """加载音频文件，返回 PCM 16kHz 16bit 单声道数据。"""
    if not os.path.exists(path):
        raise FileNotFoundError(f"文件不存在: {path}")

    with open(path, "rb") as f:
        data = f.read()

    # 如果是 WAV 文件，提取 PCM 数据
    if data[:4] == b"RIFF":
        try:
            with wave.open(path, "rb") as wf:
                print(f"  WAV: {wf.getnchannels()}ch, {wf.getframerate()}Hz, {wf.getsampwidth()*8}bit")
                pcm_data = wf.readframes(wf.getnframes())
                return pcm_data
        except wave.Error as e:
            print(f"  WAV 解析失败 ({e}), 当作原始数据发送")

    return data


async def send_audio(ws: aiohttp.ClientWebSocketResponse, path: str) -> None:
    """发送音频文件: 分帧发送 PCM + audio_end 信号。"""
    try:
        pcm_data = load_audio_file(path)
    except FileNotFoundError as e:
        print(f"错误: {e}")
        return

    total = len(pcm_data)
    duration_s = total / (16000 * 2)
    print(f"发送音频: {total} bytes ({duration_s:.1f}s), 分 {(total + AUDIO_CHUNK_SIZE - 1) // AUDIO_CHUNK_SIZE} 帧")

    # 分帧发送 PCM 二进制数据
    offset = 0
    frame_count = 0
    while offset < total:
        chunk = pcm_data[offset:offset + AUDIO_CHUNK_SIZE]
        await ws.send_bytes(chunk)
        offset += len(chunk)
        frame_count += 1

    # 发送 audio_end 信号
    message = {
        "type": "audio_end",
        "data": {},
        "timestamp": int(time.time()),
    }
    await ws.send_json(message)
    print(f"音频发送完毕 ({frame_count} 帧), 等待 ASR + AI 回复...")


async def send_touch(ws: aiohttp.ClientWebSocketResponse, action: str) -> None:
    """发送触摸事件。"""
    message = {
        "type": "touch_event",
        "data": {"action": action},
        "timestamp": int(time.time()),
    }
    await ws.send_json(message)
    print(f"已发送触摸事件: {action}")


async def send_shake(ws: aiohttp.ClientWebSocketResponse) -> None:
    """发送摇一摇事件。"""
    message = {
        "type": "shake_event",
        "data": {},
        "timestamp": int(time.time()),
    }
    await ws.send_json(message)
    print("已发送摇一摇事件")


async def send_device_status(
    ws: aiohttp.ClientWebSocketResponse, battery: int, wifi_rssi: int
) -> None:
    """发送设备状态上报。"""
    message = {
        "type": "device_status",
        "data": {
            "battery": battery,
            "wifi_rssi": wifi_rssi,
            "charging": False,
        },
        "timestamp": int(time.time()),
    }
    await ws.send_json(message)
    print(f"已发送设备状态: 电量={battery}%, WiFi={wifi_rssi}dBm")


# 记录当前设备状态 (从服务端 state_change 消息更新)
current_state = "UNKNOWN"


async def receive_loop(ws: aiohttp.ClientWebSocketResponse) -> None:
    """后台接收并打印服务端消息。"""
    global current_state
    audio_bytes_received = 0

    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            try:
                payload = json.loads(msg.data)
                msg_type = payload.get("type", "unknown")
                data = payload.get("data", {})

                if msg_type == "text_reply":
                    print(f"\n< [text_reply] {data.get('text', '')}")
                elif msg_type == "state_change":
                    current_state = data.get("state", "?")
                    print(f"\n< [state_change] → {current_state}")
                elif msg_type == "display_update":
                    print(f"\n< [display_update] {data.get('text', '')}")
                elif msg_type == "audio_play":
                    audio_bytes_received = 0
                    print(f"\n< [audio_play] 开始接收语音...")
                elif msg_type == "audio_play_end":
                    duration_s = audio_bytes_received / (16000 * 2)
                    print(f"\n< [audio_play_end] 语音接收完毕: {audio_bytes_received} bytes ({duration_s:.1f}s)")
                elif msg_type == "led_control":
                    print(f"\n< [led_control] {json.dumps(data, ensure_ascii=False)}")
                else:
                    print(f"\n< [{msg_type}] {json.dumps(data, ensure_ascii=False)}")
            except json.JSONDecodeError:
                print(f"\n< (raw) {msg.data}")
            # 重新显示输入提示
            print("> ", end="", flush=True)
        elif msg.type == aiohttp.WSMsgType.BINARY:
            audio_bytes_received += len(msg.data)
            # 不每帧都打印，太多了
        elif msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
            print("\n连接已关闭")
            break


async def main(url: str, token: str = "") -> None:
    print(f"连接到 {url} ...")
    print("命令:")
    print("  输入文字         → 发送文字消息给 AI")
    print("  audio <路径>     → 发送音频文件测试语音链路")
    print("  touch <动作>     → 模拟触摸 (single/double/long_press/long_release)")
    print("  shake            → 模拟摇一摇")
    print("  status <电量> <WiFi> → 上报设备状态 (如: status 85 -55)")
    print("  state            → 查看当前设备状态")
    print("  quit             → 退出\n")

    async with aiohttp.ClientSession() as session:
        try:
            headers = {}
            if token:
                headers["Authorization"] = f"Bearer {token}"
            async with session.ws_connect(url, headers=headers) as ws:
                print("已连接!\n")

                # 启动接收任务
                recv_task = asyncio.create_task(receive_loop(ws))

                # 输入循环
                loop = asyncio.get_event_loop()
                while True:
                    print("> ", end="", flush=True)
                    try:
                        text = await loop.run_in_executor(None, sys.stdin.readline)
                        text = text.strip()
                    except (EOFError, KeyboardInterrupt):
                        break

                    if not text:
                        continue
                    if text.lower() == "quit":
                        break

                    # 音频发送命令
                    if text.lower().startswith("audio "):
                        audio_path = text[6:].strip()
                        await send_audio(ws, audio_path)
                        continue

                    # 触摸事件
                    if text.lower().startswith("touch"):
                        parts = text.split(maxsplit=1)
                        action = parts[1].strip() if len(parts) > 1 else "single"
                        if action not in ("single", "double", "long_press", "long_release"):
                            print("触摸动作: single, double, long_press, long_release")
                            continue
                        await send_touch(ws, action)
                        continue

                    # 摇一摇
                    if text.lower() == "shake":
                        await send_shake(ws)
                        continue

                    # 设备状态上报
                    if text.lower().startswith("status"):
                        parts = text.split()
                        if len(parts) >= 3:
                            try:
                                bat = int(parts[1])
                                rssi = int(parts[2])
                                await send_device_status(ws, bat, rssi)
                            except ValueError:
                                print("用法: status <电量%> <WiFi dBm>  例: status 85 -55")
                        else:
                            print("用法: status <电量%> <WiFi dBm>  例: status 85 -55")
                        continue

                    # 查看状态
                    if text.lower() == "state":
                        print(f"当前设备状态: {current_state}")
                        continue

                    # 构造 ESP32 消息格式
                    message = {
                        "type": "text_input",
                        "data": {"text": text},
                        "timestamp": int(time.time()),
                    }
                    await ws.send_json(message)

                recv_task.cancel()
                try:
                    await recv_task
                except asyncio.CancelledError:
                    pass

        except aiohttp.ClientError as e:
            print(f"连接失败: {e}")
            print("请确认服务端已启动 (python main.py)")
            sys.exit(1)

    print("已断开")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="WebSocket 测试客户端")
    parser.add_argument("--url", default=DEFAULT_URL, help=f"WebSocket URL (默认: {DEFAULT_URL})")
    parser.add_argument("--token", default="", help="设备认证 token（若服务端启用认证）")
    args = parser.parse_args()
    asyncio.run(main(args.url, args.token))
