from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

import aiohttp


DEFAULT_URL = "ws://127.0.0.1:8765/ws/desktop-voice"
PCM_SAMPLE_RATE = 16000
PCM_CHANNELS = 1
PCM_SAMPLE_WIDTH_BYTES = 2
PCM_BLOCKSIZE = 1024


class MicrophoneStreamer:
    def __init__(self, ws: aiohttp.ClientWebSocketResponse, *, app_session_id: str) -> None:
        self.ws = ws
        self.app_session_id = app_session_id
        self.recording = False
        self.interaction_surface = "desktop_manual"
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._sender_task: asyncio.Task | None = None
        self._stream: Any | None = None
        self._loop: asyncio.AbstractEventLoop | None = None

    async def start_capture(self, *, interaction_surface: str) -> None:
        if self.recording:
            print("录音已在进行中")
            return
        try:
            import sounddevice as sd
        except ImportError as exc:
            raise RuntimeError(
                "缺少 sounddevice 依赖，请先安装: pip install sounddevice"
            ) from exc

        self.interaction_surface = interaction_surface
        self._loop = asyncio.get_running_loop()
        self._sender_task = asyncio.create_task(self._send_audio_loop())

        def _callback(indata, frames, time_info, status) -> None:
            if status:
                print(f"\n[mic warning] {status}", file=sys.stderr)
            if self._loop is None:
                return
            self._loop.call_soon_threadsafe(self._queue.put_nowait, bytes(indata))

        self._stream = sd.RawInputStream(
            samplerate=PCM_SAMPLE_RATE,
            channels=PCM_CHANNELS,
            dtype="int16",
            blocksize=PCM_BLOCKSIZE,
            callback=_callback,
        )
        self._stream.start()
        self.recording = True
        await self.ws.send_json(
            {
                "type": "start",
                "data": {
                    "interaction_surface": interaction_surface,
                    "capture_source": "desktop_mic",
                    "app_session_id": self.app_session_id,
                    "sample_rate_hz": PCM_SAMPLE_RATE,
                    "channels": PCM_CHANNELS,
                    "sample_width_bytes": PCM_SAMPLE_WIDTH_BYTES,
                    "bits_per_sample": PCM_SAMPLE_WIDTH_BYTES * 8,
                },
            }
        )
        print(f"开始录音: {interaction_surface}")

    async def stop_capture(self) -> None:
        if not self.recording:
            print("当前没有录音")
            return
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        self.recording = False
        await self._queue.put(None)
        if self._sender_task is not None:
            await self._sender_task
            self._sender_task = None
        await self.ws.send_json({"type": "stop", "data": {}})
        print("录音已停止，等待转写与回复...")

    async def cancel_capture(self, reason: str = "cancelled") -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        self.recording = False
        await self._queue.put(None)
        if self._sender_task is not None:
            await self._sender_task
            self._sender_task = None
        await self.ws.send_json({"type": "cancel", "data": {"reason": reason}})
        print(f"录音已取消: {reason}")

    async def close(self) -> None:
        if self.recording:
            await self.cancel_capture("client_shutdown")

    async def _send_audio_loop(self) -> None:
        while True:
            chunk = await self._queue.get()
            if chunk is None:
                return
            await self.ws.send_bytes(chunk)


async def receive_loop(
    ws: aiohttp.ClientWebSocketResponse,
    recorder: MicrophoneStreamer,
) -> None:
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            payload = json.loads(msg.data)
            msg_type = payload.get("type", "")
            data = payload.get("data", {})
            if msg_type == "hello":
                print(f"[server] 已连接: {json.dumps(data, ensure_ascii=False)}")
            elif msg_type == "state":
                print(f"[state] {json.dumps(data, ensure_ascii=False)}")
            elif msg_type == "capture.start":
                await recorder.start_capture(
                    interaction_surface=str(data.get("interaction_surface") or "device_press"),
                )
            elif msg_type == "capture.stop":
                await recorder.stop_capture()
            elif msg_type == "capture.cancel":
                await recorder.cancel_capture(str(data.get("reason") or "server_cancelled"))
            elif msg_type == "capture.started":
                print(f"[capture.started] {json.dumps(data, ensure_ascii=False)}")
            elif msg_type == "capture.stopped":
                print(f"[capture.stopped] {json.dumps(data, ensure_ascii=False)}")
            elif msg_type == "transcript":
                print(f"[transcript] {data.get('text', '')}")
            elif msg_type == "response":
                print(f"[response] {data.get('text', '')}")
            elif msg_type == "error":
                print(f"[error] {data.get('code')}: {data.get('message')}")
            elif msg_type == "pong":
                print(f"[pong] {json.dumps(data, ensure_ascii=False)}")
            else:
                print(f"[{msg_type}] {json.dumps(data, ensure_ascii=False)}")
        elif msg.type in {aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR}:
            print("连接已关闭")
            return


async def input_loop(
    ws: aiohttp.ClientWebSocketResponse,
    recorder: MicrophoneStreamer,
) -> None:
    loop = asyncio.get_running_loop()
    while True:
        print("> ", end="", flush=True)
        line = await loop.run_in_executor(None, sys.stdin.readline)
        command = line.strip()
        if not command:
            continue
        if command == "quit":
            return
        if command == "start":
            await recorder.start_capture(interaction_surface="desktop_manual")
            continue
        if command == "stop":
            await recorder.stop_capture()
            continue
        if command == "cancel":
            await recorder.cancel_capture("manual_cancel")
            continue
        if command == "status":
            await ws.send_json({"type": "status", "data": {}})
            continue
        print("命令: start / stop / cancel / status / quit")


async def main(url: str, token: str, app_session_id: str) -> None:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    print(f"连接到 {url}")
    print("命令: start / stop / cancel / status / quit")
    print("设备长按触发时，本工具会自动开始/结束录音。")

    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(url, headers=headers) as ws:
            recorder = MicrophoneStreamer(ws, app_session_id=app_session_id)
            recv_task = asyncio.create_task(receive_loop(ws, recorder))
            try:
                await input_loop(ws, recorder)
            finally:
                await recorder.close()
                recv_task.cancel()
                try:
                    await recv_task
                except asyncio.CancelledError:
                    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Desktop microphone bridge client")
    parser.add_argument("--url", default=DEFAULT_URL, help="desktop voice websocket url")
    parser.add_argument("--token", default="", help="desktop voice auth token")
    parser.add_argument("--app-session-id", default="app:main", help="target app session id")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(main(args.url, args.token, args.app_session_id))
    except KeyboardInterrupt:
        pass
