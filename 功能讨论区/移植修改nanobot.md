# Nanobot 移植到后端计划

> **这份计划要干什么：**
> task.md 七（电脑服务端开发）原计划从零搭建 FastAPI 后端，自己写 LLM 引擎、会话管理、工具系统。
> 本计划改为：**以 nanobot 作为 AI 核心引擎**，在其基础上增加两个自定义 Channel 接入硬件和 App，
> 同时保留 task.md 中的 ASR（语音识别）和 TTS（语音合成）服务。
>
> **nanobot 替代 task.md 的哪些部分：**
> - 7.2 WebSocket 端点 → DeviceChannel + AppChannel（自定义 nanobot Channel）
> - 7.3 SessionManager → nanobot 内置 SessionManager（共享 session_key 实现硬件/App 上下文共享）
> - 7.6 LLM + Tool Use → nanobot AgentLoop（保留自定义 task_queue / events 工具）
> - 7.7 Nanobot subprocess 调用 → nanobot 内置 exec 工具 + 电脑控制 Skill（无需再 subprocess 调用）
> - 7.8 对话历史/摘要 → nanobot 内置 MEMORY.md + HISTORY.md（SQLite 仅保留 tasks / events 结构化数据）
>
> **保留 task.md 的哪些部分（仍需自己实现）：**
> - 7.4 ASR（Whisper 本地部署）→ `server/services/asr.py`，被 DeviceChannel 调用
> - 7.5 TTS（Edge-TTS）→ `server/services/tts.py`，被 DeviceChannel.send() 调用
> - 7.8 SQLite（仅 tasks / events 两张表）→ `server/db/`

---

## 新后端架构图

```
ESP32 硬件
  │  WebSocket (ws://服务端IP:8765/ws/device)
  │  发送：二进制音频帧 + JSON控制消息
  │  接收：TTS音频流 + 屏幕/LED控制
  ▼
DeviceChannel (server/channels/device_channel.py)
  │  音频帧 → asr.py (Whisper) → 文字
  │  文字 → InboundMessage → MessageBus
  │  OutboundMessage → tts.py (Edge-TTS) → 音频 → ESP32
  ▼
nanobot MessageBus
  ▼
nanobot AgentLoop (Claude claude-sonnet-4-6)
  │  内置工具：exec, read_file, write_file, web_search, web_fetch
  │  自定义工具：task_queue, events
  │  Skills: computer-control, task-manager
  ▼
nanobot MessageBus
  ▼
AppChannel (server/channels/app_channel.py)
  │  WebSocket (ws://服务端IP:8765/ws/app)
  │  发送：chat_reply JSON → Flutter App
  ▼
Flutter App

调试期（WhatsApp）：
  手机 WhatsApp → WhatsApp Bridge (Node.js 3001) → nanobot WhatsAppChannel → MessageBus
```

---

## server/ 目录结构

```
server/
├── main.py                       # 入口：构建 nanobot 核心 + 自定义 Channel + REST API
├── config.py                     # 读取 ~/.nanobot/config.json（复用 nanobot 配置）
├── channels/
│   ├── device_channel.py         # ESP32 WebSocket Channel（含 ASR 调用 + TTS 调用）
│   └── app_channel.py            # Flutter App WebSocket Channel
├── services/
│   ├── asr.py                    # Whisper ASR（本地部署，线程池运行）
│   └── tts.py                    # Edge-TTS（异步，生成 PCM 音频）
├── tools/
│   ├── task_queue_tool.py        # 自定义 nanobot 工具：任务队列
│   └── events_tool.py            # 自定义 nanobot 工具：日程日历
├── api/
│   └── rest.py                   # FastAPI 辅助 REST（health / device状态 / 对话历史）
├── db/
│   ├── database.py               # SQLite 连接管理（WAL 模式）
│   └── schema.sql                # 只建 tasks + events 两张表
└── skills/                       # nanobot Skill .md 文件（放到 workspace/skills/ 加载）
    ├── computer-control/
    │   └── SKILL.md
    └── task-manager/
        └── SKILL.md
```

---

## 阶段零：安装配置，WhatsApp 调试通道跑通

**目标：** nanobot 跑起来，WhatsApp 能收发消息，验证 Claude AI 对话正常。

### 任务 0.1：安装 nanobot

```bash
cd /Users/mandy/Documents/GitHub/AI-bot/nanobot-src
pip install -e .
nanobot --help
# 看到帮助说明则安装成功
```

### 任务 0.2：初始化工作空间

```bash
nanobot onboard
# 按提示填入 Anthropic API Key
# 会在 ~/.nanobot/ 创建 config.json 和 workspace/
```

### 任务 0.3：配置 config.json

打开 `~/.nanobot/config.json`，修改为：

```json
{
  "agents": {
    "defaults": {
      "model": "claude-sonnet-4-6",
      "provider": "anthropic",
      "maxTokens": 8192,
      "temperature": 0.1,
      "maxToolIterations": 20,
      "memoryWindow": 50
    }
  },
  "providers": {
    "anthropic": { "apiKey": "sk-ant-你的KEY" },
    "groq": { "apiKey": "gsk_你的KEY（用于Whisper备用，可选）" }
  },
  "channels": {
    "sendProgress": true,
    "sendToolHints": false,
    "whatsapp": {
      "enabled": true,
      "bridgeUrl": "ws://localhost:3001",
      "allowFrom": ["+8613912345678（改成你的手机号）"]
    }
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 18790,
    "heartbeat": { "enabled": false }
  }
}
```

### 任务 0.4：测试 AI 连通性

```bash
nanobot agent -m "你好"
# 应看到 Claude 回复
```

### 任务 0.5：安装并启动 WhatsApp Bridge

```bash
# 终端 1：启动 Bridge
cd /Users/mandy/Documents/GitHub/AI-bot/nanobot-src/bridge
npm install && npm run build && npm start

# 终端 2：扫码绑定
nanobot channels login
# 选 whatsapp，用手机扫码

# 终端 2：启动 Gateway
nanobot gateway
```

用手机 WhatsApp 发一条消息，确认 AI 能回复。

**提交：**
```bash
cd /Users/mandy/Documents/GitHub/AI-bot
git add -A
git commit -m "feat: 阶段零完成 - WhatsApp调试通道跑通"
```

---

## 阶段一：安装 Python 服务端依赖

**目标：** 为 server/ 建立环境，安装后续阶段所需依赖。

### 任务 1.1：创建 server/ 目录骨架

```bash
cd /Users/mandy/Documents/GitHub/AI-bot
mkdir -p server/channels server/services server/tools server/api server/db server/skills/computer-control server/skills/task-manager
touch server/__init__.py server/channels/__init__.py server/services/__init__.py server/tools/__init__.py
```

### 任务 1.2：安装依赖

```bash
pip install aiohttp websockets edge-tts faster-whisper
# aiohttp：HTTP/WebSocket 服务器
# edge-tts：微软 Edge TTS（免费，无需 API Key）
# faster-whisper：本地 Whisper 语音识别（比 openai-whisper 快 4x）
```

验证安装：
```bash
python3 -c "import aiohttp, edge_tts, faster_whisper; print('OK')"
```

### 任务 1.3：创建 SQLite 数据库

**新建文件：** `server/db/schema.sql`

```sql
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending / done
    priority INTEGER DEFAULT 0,
    due_at TEXT,          -- ISO 8601，可为空
    event_id INTEGER,     -- 关联 events 表，可为空
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL DEFAULT 'event',  -- event / reminder / alarm
    title TEXT NOT NULL,
    description TEXT,
    start_time TEXT NOT NULL,  -- ISO 8601
    end_time TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status, due_at);
CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time, type);
```

**新建文件：** `server/db/database.py`

```python
"""SQLite connection manager."""

import sqlite3
from pathlib import Path

DB_PATH = Path.home() / ".nanobot" / "workspace" / "aibot.db"


def get_connection() -> sqlite3.Connection:
    """Get SQLite connection with WAL mode enabled."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create tables if not exist."""
    schema = (Path(__file__).parent / "schema.sql").read_text()
    with get_connection() as conn:
        conn.executescript(schema)
```

---

## 阶段二：ASR 和 TTS 服务

**目标：** 实现语音识别和语音合成服务，供 DeviceChannel 调用。

### 任务 2.1：实现 ASR 服务（本地 Whisper）

**新建文件：** `server/services/asr.py`

```python
"""ASR service using faster-whisper (local, runs in thread pool)."""

import asyncio
import tempfile
from pathlib import Path

from faster_whisper import WhisperModel
from loguru import logger

_model: WhisperModel | None = None


def _get_model() -> WhisperModel:
    """Lazy-load Whisper model (first call takes ~30s to download)."""
    global _model
    if _model is None:
        logger.info("Loading Whisper base model...")
        _model = WhisperModel("base", device="cpu", compute_type="int8")
        logger.info("Whisper model loaded")
    return _model


def _transcribe_sync(wav_bytes: bytes) -> str:
    """Synchronous transcription, runs in thread pool."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    try:
        model = _get_model()
        segments, _ = model.transcribe(tmp_path, language="zh", beam_size=1)
        text = "".join(s.text for s in segments).strip()
        logger.info("ASR result: {}", text)
        return text
    except Exception as e:
        logger.error("ASR error: {}", e)
        return ""
    finally:
        Path(tmp_path).unlink(missing_ok=True)


async def transcribe(wav_bytes: bytes) -> str:
    """Transcribe audio bytes to text (async, runs in thread pool)."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _transcribe_sync, wav_bytes)
```

**测试 ASR：**
```bash
# 先录一段音（macOS）
python3 -c "
import asyncio
from server.services.asr import transcribe

with open('test.wav', 'rb') as f:
    wav = f.read()
result = asyncio.run(transcribe(wav))
print('识别结果:', result)
"
```

### 任务 2.2：实现 TTS 服务（Edge-TTS）

**新建文件：** `server/services/tts.py`

```python
"""TTS service using Edge-TTS (Microsoft, free, no API key needed)."""

import asyncio
import io
import tempfile
from pathlib import Path

import edge_tts
from loguru import logger

# 可选语音：zh-CN-XiaoxiaoNeural（女）/ zh-CN-YunxiNeural（男）
VOICE = "zh-CN-XiaoxiaoNeural"


async def synthesize(text: str) -> bytes:
    """
    Convert text to PCM audio bytes (16kHz, 16-bit, mono).
    Returns WAV bytes suitable for ESP32 playback.
    """
    if not text.strip():
        return b""

    try:
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
            tmp_path = f.name

        communicate = edge_tts.Communicate(text, VOICE)
        await communicate.save(tmp_path)

        # Convert MP3 → WAV 16kHz 16-bit mono using ffmpeg
        import subprocess
        wav_path = tmp_path.replace(".mp3", ".wav")
        subprocess.run([
            "ffmpeg", "-y", "-i", tmp_path,
            "-ar", "16000", "-ac", "1", "-f", "wav", wav_path
        ], capture_output=True, check=True)

        wav_bytes = Path(wav_path).read_bytes()
        logger.info("TTS generated {} bytes for: {}...", len(wav_bytes), text[:30])
        return wav_bytes

    except Exception as e:
        logger.error("TTS error: {}", e)
        return b""
    finally:
        for p in [tmp_path, wav_path]:
            Path(p).unlink(missing_ok=True)
```

**检查 ffmpeg 是否安装：**
```bash
ffmpeg -version
# 如果没安装：brew install ffmpeg
```

**测试 TTS：**
```bash
python3 -c "
import asyncio
from server.services.tts import synthesize

wav = asyncio.run(synthesize('你好，我是AI助手'))
with open('output.wav', 'wb') as f:
    f.write(wav)
print('生成音频', len(wav), '字节')
"
# macOS 播放测试：afplay output.wav
```

---

## 阶段三：DeviceChannel（ESP32 WebSocket 通道）

**目标：** 实现 DeviceChannel，接受 ESP32 WebSocket 连接，处理音频输入和 AI 输出。

这个 Channel 是整个项目的核心，替代 task.md 7.2 `/ws/device`、7.4 ASR、7.5 TTS。

**新建文件：** `server/channels/device_channel.py`

```python
"""
DeviceChannel: ESP32 hardware WebSocket channel.

WebSocket 消息格式（JSON）：
  设备 → 服务端：
    {"type": "audio_end"}              — 音频录制完成，触发识别
    {"type": "touch_event", "data": {"gesture": "single/double/long"}}
    {"type": "shake_event"}
    {"type": "device_status", "data": {"battery": 80, "rssi": -60}}

  服务端 → 设备：
    {"type": "state_change", "data": {"state": "PROCESSING/SPEAKING/IDLE"}}
    {"type": "display_update", "data": {"text": "AI回复内容"}}
    {"type": "led_control", "data": {"mode": "speaking/idle/thinking"}}
    {"type": "audio_play"}             — 后续跟随二进制音频帧
    {"type": "audio_play_end"}         — 音频播放完毕标志

  设备 → 服务端（二进制）：音频帧（16kHz 16bit 单声道 PCM）
"""

import asyncio
import json
from typing import Any

import aiohttp
from aiohttp import web
from loguru import logger

from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel

from server.services import asr, tts

# 共享 session_key：硬件与 App 使用同一个对话上下文
SHARED_SESSION_KEY = "main_user"
DEVICE_CHAT_ID = "esp32_main"


class DeviceChannel(BaseChannel):
    """ESP32 hardware WebSocket channel with ASR and TTS."""

    name = "device"

    def __init__(self, config: Any, bus: MessageBus):
        super().__init__(config, bus)
        self._app = web.Application()
        self._runner: web.AppRunner | None = None
        self._ws_clients: dict[str, web.WebSocketResponse] = {}  # chat_id → ws
        self._audio_buffers: dict[str, bytes] = {}               # chat_id → audio bytes
        self._app.router.add_get("/ws/device", self._handle_ws)

    async def _handle_ws(self, request: web.Request) -> web.WebSocketResponse:
        """Handle incoming WebSocket connection from ESP32."""
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        chat_id = DEVICE_CHAT_ID
        self._ws_clients[chat_id] = ws
        self._audio_buffers[chat_id] = b""
        logger.info("ESP32 device connected")

        # Notify device: idle state
        await self._send_json(ws, {"type": "state_change", "data": {"state": "IDLE"}})

        try:
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.BINARY:
                    # Accumulate audio frames
                    self._audio_buffers[chat_id] += msg.data

                elif msg.type == aiohttp.WSMsgType.TEXT:
                    data = json.loads(msg.data)
                    await self._handle_control(ws, chat_id, data)

                elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                    break
        finally:
            self._ws_clients.pop(chat_id, None)
            self._audio_buffers.pop(chat_id, None)
            logger.info("ESP32 device disconnected")

        return ws

    async def _handle_control(
        self, ws: web.WebSocketResponse, chat_id: str, data: dict
    ) -> None:
        """Handle JSON control messages from device."""
        msg_type = data.get("type")

        if msg_type == "audio_end":
            # Audio recording finished → transcribe → send to AI
            wav_bytes = self._audio_buffers.pop(chat_id, b"")
            self._audio_buffers[chat_id] = b""

            if not wav_bytes:
                logger.warning("audio_end received but buffer is empty")
                return

            await self._send_json(ws, {"type": "state_change", "data": {"state": "PROCESSING"}})

            text = await asr.transcribe(wav_bytes)
            if not text:
                await self._send_json(ws, {"type": "state_change", "data": {"state": "IDLE"}})
                return

            logger.info("Device voice → text: {}", text)
            await self._handle_message(
                sender_id="esp32",
                chat_id=chat_id,
                content=text,
                session_key=SHARED_SESSION_KEY,
            )

        elif msg_type == "touch_event":
            gesture = data.get("data", {}).get("gesture", "single")
            if gesture == "single":
                # Single tap = start/stop voice recording (firmware handles it)
                pass
            elif gesture == "long":
                # Long press = cancel current AI task
                await self._handle_message(
                    sender_id="esp32",
                    chat_id=chat_id,
                    content="/stop",
                    session_key=SHARED_SESSION_KEY,
                )

        elif msg_type == "shake_event":
            await self._handle_message(
                sender_id="esp32",
                chat_id=chat_id,
                content="用户摇了摇设备，请有趣地回应",
                session_key=SHARED_SESSION_KEY,
            )

        elif msg_type == "device_status":
            # Store device status (battery, RSSI) for REST API
            status = data.get("data", {})
            logger.debug("Device status: {}", status)

    async def send(self, msg: OutboundMessage) -> None:
        """Send AI text reply to device: convert to TTS audio and stream."""
        ws = self._ws_clients.get(msg.chat_id)
        if not ws or ws.closed:
            logger.warning("DeviceChannel: no active WS for chat_id {}", msg.chat_id)
            return

        # Update screen display
        await self._send_json(ws, {
            "type": "display_update",
            "data": {"text": msg.content[:100]}  # truncate for small display
        })

        # LED: speaking mode
        await self._send_json(ws, {"type": "state_change", "data": {"state": "SPEAKING"}})
        await self._send_json(ws, {"type": "led_control", "data": {"mode": "speaking"}})

        # Generate TTS audio and stream to device
        audio_bytes = await tts.synthesize(msg.content)
        if audio_bytes:
            await self._send_json(ws, {"type": "audio_play"})
            # Send in 1KB chunks
            chunk_size = 1024
            for i in range(0, len(audio_bytes), chunk_size):
                await ws.send_bytes(audio_bytes[i:i + chunk_size])
            await self._send_json(ws, {"type": "audio_play_end"})

        # Back to idle
        await self._send_json(ws, {"type": "state_change", "data": {"state": "IDLE"}})
        await self._send_json(ws, {"type": "led_control", "data": {"mode": "idle"}})

    async def _send_json(self, ws: web.WebSocketResponse, data: dict) -> None:
        if not ws.closed:
            await ws.send_str(json.dumps(data, ensure_ascii=False))

    async def start(self) -> None:
        self._running = True
        self._runner = web.AppRunner(self._app)
        await self._runner.setup()
        host = getattr(self.config, "host", "0.0.0.0")
        port = getattr(self.config, "device_port", 8765)
        site = web.TCPSite(self._runner, host, port)
        await site.start()
        logger.info("DeviceChannel WebSocket server started on {}:{}", host, port)
        while self._running:
            await asyncio.sleep(1)

    async def stop(self) -> None:
        self._running = False
        if self._runner:
            await self._runner.cleanup()
```

---

## 阶段四：AppChannel（Flutter App WebSocket 通道）

**目标：** 实现 AppChannel，接受 Flutter App WebSocket 连接，收发文字消息。

**新建文件：** `server/channels/app_channel.py`

```python
"""
AppChannel: Flutter App WebSocket channel.

WebSocket 消息格式（JSON）：
  App → 服务端：
    {"type": "chat_message", "data": {"message": "你好", "session_id": "app_user"}}

  服务端 → App：
    {"type": "chat_reply", "data": {"content": "AI回复", "source": "ai"}}
    {"type": "chat_user", "data": {"content": "用户说的话", "source": "device"}}
    {"type": "device_status", "data": {"battery": 80, "rssi": -60, "online": true}}
"""

import asyncio
import json
from typing import Any

import aiohttp
from aiohttp import web
from loguru import logger

from nanobot.bus.events import OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel

SHARED_SESSION_KEY = "main_user"
APP_CHAT_ID = "app_main"


class AppChannel(BaseChannel):
    """Flutter App WebSocket channel (text only)."""

    name = "app"

    def __init__(self, config: Any, bus: MessageBus):
        super().__init__(config, bus)
        self._app = web.Application()
        self._runner: web.AppRunner | None = None
        self._ws_clients: dict[str, web.WebSocketResponse] = {}
        self._app.router.add_get("/ws/app", self._handle_ws)
        # REST endpoint for health check
        self._app.router.add_get("/api/health", self._handle_health)

    async def _handle_ws(self, request: web.Request) -> web.WebSocketResponse:
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        chat_id = APP_CHAT_ID
        self._ws_clients[chat_id] = ws
        logger.info("Flutter App connected")

        try:
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    data = json.loads(msg.data)
                    if data.get("type") == "chat_message":
                        content = data.get("data", {}).get("message", "").strip()
                        if content:
                            await self._handle_message(
                                sender_id="app_user",
                                chat_id=chat_id,
                                content=content,
                                session_key=SHARED_SESSION_KEY,
                            )
                elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                    break
        finally:
            self._ws_clients.pop(chat_id, None)
            logger.info("Flutter App disconnected")

        return ws

    async def _handle_health(self, request: web.Request) -> web.Response:
        return web.json_response({"status": "ok", "service": "AI-Bot"})

    async def send(self, msg: OutboundMessage) -> None:
        """Send AI reply to App as JSON."""
        ws = self._ws_clients.get(msg.chat_id)
        if not ws or ws.closed:
            return
        payload = json.dumps({
            "type": "chat_reply",
            "data": {"content": msg.content, "source": "ai"}
        }, ensure_ascii=False)
        await ws.send_str(payload)

    async def start(self) -> None:
        self._running = True
        self._runner = web.AppRunner(self._app)
        await self._runner.setup()
        host = getattr(self.config, "host", "0.0.0.0")
        port = getattr(self.config, "app_port", 8766)
        site = web.TCPSite(self._runner, host, port)
        await site.start()
        logger.info("AppChannel WebSocket server started on {}:{}", host, port)
        while self._running:
            await asyncio.sleep(1)

    async def stop(self) -> None:
        self._running = False
        if self._runner:
            await self._runner.cleanup()
```

---

## 阶段五：main.py — 整合入口

**目标：** `server/main.py` 直接构建 nanobot 核心组件，注入自定义 Channel。

nanobot 的 `gateway` CLI 命令会硬编码创建 Channel，无法注入自定义 Channel。
因此 `main.py` 直接调用 nanobot 内部 API，手动组装。

**新建文件：** `server/main.py`

```python
"""
AI-Bot 服务端入口。

直接构建 nanobot 核心组件（MessageBus + AgentLoop）
并注入自定义 DeviceChannel（ESP32）和 AppChannel（Flutter App）。

运行方式：
  cd /Users/mandy/Documents/GitHub/AI-bot
  python -m server.main
"""

import asyncio
import signal
from types import SimpleNamespace

from loguru import logger

from nanobot.agent.loop import AgentLoop
from nanobot.bus.queue import MessageBus
from nanobot.config.loader import load_config
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from nanobot.utils.helpers import sync_workspace_templates

from server.channels.device_channel import DeviceChannel
from server.channels.app_channel import AppChannel
from server.db.database import init_db


def _make_provider(config):
    """Create LLM provider from config (same as nanobot gateway does)."""
    from nanobot.providers.registry import find_by_name
    provider_name = config.get_provider_name()
    provider_cfg = config.get_provider(config.agents.defaults.model)
    if provider_name and provider_cfg:
        spec = find_by_name(provider_name)
        if spec:
            return spec.factory(provider_cfg)
    return LiteLLMProvider(provider_cfg or config.providers.anthropic)


async def main():
    logger.info("Starting AI-Bot server...")

    # 初始化数据库
    init_db()

    # 加载 nanobot 配置（~/.nanobot/config.json）
    config = load_config()
    sync_workspace_templates(config.workspace_path)

    # nanobot 核心组件
    bus = MessageBus()
    provider = _make_provider(config)
    session_manager = SessionManager(config.workspace_path)

    agent = AgentLoop(
        bus=bus,
        provider=provider,
        workspace=config.workspace_path,
        model=config.agents.defaults.model,
        temperature=config.agents.defaults.temperature,
        max_tokens=config.agents.defaults.max_tokens,
        max_iterations=config.agents.defaults.max_tool_iterations,
        memory_window=config.agents.defaults.memory_window,
        exec_config=config.tools.exec,
        session_manager=session_manager,
        channels_config=config.channels,
    )

    # 自定义 Channel 配置（用 SimpleNamespace 模拟 Pydantic model）
    device_cfg = SimpleNamespace(
        host="0.0.0.0", device_port=8765, allow_from=["*"]
    )
    app_cfg = SimpleNamespace(
        host="0.0.0.0", app_port=8766, allow_from=["*"]
    )

    device_channel = DeviceChannel(device_cfg, bus)
    app_channel = AppChannel(app_cfg, bus)

    # 注册 Channel 到 bus 出站分发（手动路由）
    original_dispatch = bus.consume_outbound

    async def dispatch_loop():
        """Route outbound messages to the correct channel."""
        while True:
            try:
                msg = await asyncio.wait_for(bus.consume_outbound(), timeout=1.0)
                if msg.channel == "device":
                    await device_channel.send(msg)
                elif msg.channel == "app":
                    await app_channel.send(msg)
                else:
                    logger.warning("Unknown channel for outbound: {}", msg.channel)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                break

    # WhatsApp channel（如果 config 启用了，也一起启动）
    wa_tasks = []
    if config.channels.whatsapp.enabled:
        from nanobot.channels.whatsapp import WhatsAppChannel
        wa_channel = WhatsAppChannel(config.channels.whatsapp, bus)
        wa_tasks.append(asyncio.create_task(wa_channel.start()))
        logger.info("WhatsApp channel enabled")

    logger.info("Starting DeviceChannel on port 8765...")
    logger.info("Starting AppChannel on port 8766...")

    # Graceful shutdown
    loop = asyncio.get_running_loop()
    shutdown_event = asyncio.Event()

    def _on_signal():
        shutdown_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _on_signal)

    tasks = [
        asyncio.create_task(device_channel.start()),
        asyncio.create_task(app_channel.start()),
        asyncio.create_task(agent.run()),
        asyncio.create_task(dispatch_loop()),
        *wa_tasks,
    ]

    logger.info("AI-Bot server started. Press Ctrl+C to stop.")
    await shutdown_event.wait()

    logger.info("Shutting down...")
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(main())
```

**测试启动：**
```bash
cd /Users/mandy/Documents/GitHub/AI-bot
python -m server.main
# 应看到：
# Starting AI-Bot server...
# DeviceChannel WebSocket server started on 0.0.0.0:8765
# AppChannel WebSocket server started on 0.0.0.0:8766
```

**用 wscat 测试 App Channel（安装：`npm install -g wscat`）：**
```bash
wscat -c ws://localhost:8766/ws/app
# 输入：{"type":"chat_message","data":{"message":"你好"}}
# 应收到：{"type":"chat_reply","data":{"content":"你好！...",...}}
```

**提交：**
```bash
git add server/
git commit -m "feat: 阶段五完成 - main.py整合，DeviceChannel+AppChannel+nanobot跑通"
```

---

## 阶段六：自定义 nanobot 工具（任务队列 + 日程）

**目标：** 替代 task.md 7.6 中的 task_queue 和 events 工具。

nanobot 的自定义工具需要继承 `BaseTool` 并注册到 `ToolRegistry`，
然后在 `AgentLoop` 初始化后通过 `agent.tools.register()` 注入。

### 任务 6.1：实现 task_queue 工具

**新建文件：** `server/tools/task_queue_tool.py`

```python
"""Task queue tool for nanobot AgentLoop."""

from nanobot.agent.tools.base import BaseTool
from server.db.database import get_connection


class TaskQueueTool(BaseTool):
    name = "task_queue"
    description = (
        "管理任务队列。操作：list（列出任务）、create（创建）、done（完成）、delete（删除）。"
    )
    parameters = {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["list", "create", "done", "delete"],
                "description": "操作类型"
            },
            "title": {"type": "string", "description": "任务标题（create 时必填）"},
            "task_id": {"type": "integer", "description": "任务ID（done/delete 时必填）"},
            "priority": {"type": "integer", "description": "优先级 0-3（可选，默认0）"},
            "due_at": {"type": "string", "description": "截止时间 ISO 8601（可选）"},
        },
        "required": ["action"],
    }

    async def execute(self, action: str, title: str = "", task_id: int = 0,
                      priority: int = 0, due_at: str = "") -> str:
        with get_connection() as conn:
            if action == "list":
                rows = conn.execute(
                    "SELECT id, title, status, priority, due_at FROM tasks "
                    "WHERE status='pending' ORDER BY priority DESC, due_at ASC"
                ).fetchall()
                if not rows:
                    return "任务列表为空"
                return "\n".join(
                    f"[{r['id']}] {r['title']} (优先级:{r['priority']}, 截止:{r['due_at'] or '无'})"
                    for r in rows
                )

            elif action == "create":
                if not title:
                    return "错误：create 操作需要 title 参数"
                conn.execute(
                    "INSERT INTO tasks (title, priority, due_at) VALUES (?, ?, ?)",
                    (title, priority, due_at or None)
                )
                return f"任务已创建：{title}"

            elif action == "done":
                conn.execute("UPDATE tasks SET status='done' WHERE id=?", (task_id,))
                return f"任务 #{task_id} 已标记完成"

            elif action == "delete":
                conn.execute("DELETE FROM tasks WHERE id=?", (task_id,))
                return f"任务 #{task_id} 已删除"

            return "未知操作"
```

### 任务 6.2：实现 events 工具

**新建文件：** `server/tools/events_tool.py`

```python
"""Events/calendar tool for nanobot AgentLoop."""

from nanobot.agent.tools.base import BaseTool
from server.db.database import get_connection


class EventsTool(BaseTool):
    name = "events"
    description = (
        "管理日程和日历事件。操作：list（查询）、create（创建）、delete（删除）。"
        "type 字段区分：event（日历事件）/ reminder（提醒）/ alarm（闹钟）。"
    )
    parameters = {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["list", "create", "delete"],
                "description": "操作类型"
            },
            "event_type": {
                "type": "string",
                "enum": ["event", "reminder", "alarm"],
                "description": "事件类型（create 时必填）"
            },
            "title": {"type": "string", "description": "事件标题"},
            "start_time": {"type": "string", "description": "开始时间 ISO 8601"},
            "end_time": {"type": "string", "description": "结束时间（可选）"},
            "description": {"type": "string", "description": "描述（可选）"},
            "event_id": {"type": "integer", "description": "事件ID（delete 时必填）"},
            "date": {"type": "string", "description": "查询日期 YYYY-MM-DD（list 时可选）"},
        },
        "required": ["action"],
    }

    async def execute(self, action: str, event_type: str = "event", title: str = "",
                      start_time: str = "", end_time: str = "", description: str = "",
                      event_id: int = 0, date: str = "") -> str:
        with get_connection() as conn:
            if action == "list":
                if date:
                    rows = conn.execute(
                        "SELECT id, type, title, start_time FROM events "
                        "WHERE date(start_time)=? ORDER BY start_time",
                        (date,)
                    ).fetchall()
                else:
                    rows = conn.execute(
                        "SELECT id, type, title, start_time FROM events "
                        "WHERE start_time >= datetime('now') ORDER BY start_time LIMIT 10"
                    ).fetchall()
                if not rows:
                    return "没有即将到来的日程"
                return "\n".join(
                    f"[{r['id']}][{r['type']}] {r['title']} @ {r['start_time']}"
                    for r in rows
                )

            elif action == "create":
                if not title or not start_time:
                    return "错误：create 需要 title 和 start_time"
                conn.execute(
                    "INSERT INTO events (type, title, description, start_time, end_time) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (event_type, title, description or None, start_time, end_time or None)
                )
                return f"已创建{event_type}：{title}（{start_time}）"

            elif action == "delete":
                conn.execute("DELETE FROM events WHERE id=?", (event_id,))
                return f"事件 #{event_id} 已删除"

            return "未知操作"
```

### 任务 6.3：在 main.py 注册自定义工具

在 `server/main.py` 的 `AgentLoop` 初始化后，添加工具注册：

```python
from server.tools.task_queue_tool import TaskQueueTool
from server.tools.events_tool import EventsTool

# ... AgentLoop 创建后 ...
agent.tools.register(TaskQueueTool())
agent.tools.register(EventsTool())
```

**测试工具（通过 WhatsApp 或 wscat）：**
```
用户：帮我创建一个任务：明天下午3点开会
AI：好的，我来为你创建任务...（调用 task_queue create）
用户：今天有什么日程
AI：（调用 events list）
```

---

## 阶段七：AI 人格与电脑控制技能

**目标：** 定制 AI 人格，配置电脑控制能力（直接用 nanobot 内置 exec 工具）。

### 任务 7.1：设置 AI 人格（SOUL.md）

nanobot 的 ContextBuilder 会读取 `workspace/SOUL.md` 注入系统 prompt。

**新建文件：** `~/.nanobot/workspace/SOUL.md`

```markdown
# AI-Bot 桌面助手

你是一个桌面 AI 助手，名字叫小博，运行在用户电脑上。
用户通过语音（ESP32硬件设备）或手机 App 与你交流。

## 你的特点
- 回复精简：语音场景下每次回复 1-2 句话，不超过 50 字
- 语言：默认中文，用户用英文则用英文回复
- 性格：主动、友好、实用，不废话

## 你的能力
- 控制电脑：打开关闭应用、文件操作、系统命令（通过 exec 工具）
- 管理任务：创建/查询/完成任务（通过 task_queue 工具）
- 管理日程：创建/查询日历事件和提醒（通过 events 工具）
- 搜索网页（通过 web_search 工具）
- 读写文件（通过 read_file / write_file 工具）

## 注意
- 执行 exec 命令前，如果有破坏性（删除文件等），先向用户确认
- 不执行 rm -rf、shutdown 等危险命令
```

### 任务 7.2：创建电脑控制技能

**新建文件：** `server/skills/computer-control/SKILL.md`

```markdown
---
name: computer-control
description: 控制 macOS 电脑，打开应用、查询系统信息、文件操作
---

# 电脑控制技能（macOS）

用 exec 工具执行 shell 命令。

## 打开应用
exec: open -a "Safari"
exec: open -a "Terminal"
exec: open -a "System Preferences"
exec: open -a "Calculator"

## 查询系统
exec: date                       # 当前时间
exec: df -h                      # 磁盘空间
exec: top -l 1 | head -20        # CPU/内存
exec: ifconfig | grep "inet "    # 网络IP

## 文件操作（用 read_file / write_file 工具，不用 exec）
例：read_file("/Users/mandy/Desktop/notes.txt")

## 调整系统设置（macOS）
exec: osascript -e "set volume output volume 50"   # 音量50%
exec: osascript -e "set volume output muted true"  # 静音
```

**把 Skills 复制到 nanobot workspace：**
```bash
cp -r /Users/mandy/Documents/GitHub/AI-bot/server/skills/computer-control \
      ~/.nanobot/workspace/skills/
```

---

## 阶段八：集成测试

### 任务 8.1：全链路测试清单

**步骤 1：启动完整服务**
```bash
# 终端 1：WhatsApp Bridge（可选）
cd nanobot-src/bridge && npm start

# 终端 2：AI-Bot 服务端
cd /Users/mandy/Documents/GitHub/AI-bot
python -m server.main
```

**步骤 2：用 wscat 模拟 Flutter App 测试**
```bash
wscat -c ws://localhost:8766/ws/app

# 测试文字对话
> {"type":"chat_message","data":{"message":"你好"}}
< {"type":"chat_reply","data":{"content":"你好！..."}}

# 测试工具调用
> {"type":"chat_message","data":{"message":"创建任务：买牛奶"}}
> {"type":"chat_message","data":{"message":"列出我的任务"}}
> {"type":"chat_message","data":{"message":"打开Safari"}}
```

**步骤 3：用 Python 脚本模拟 ESP32 发送音频**
```python
# simulate_esp32.py
import asyncio, websockets, json, wave

async def test():
    uri = "ws://localhost:8765/ws/device"
    async with websockets.connect(uri) as ws:
        # 发送音频帧
        with open("test.wav", "rb") as f:
            chunk = f.read(1024)
            while chunk:
                await ws.send(chunk)
                chunk = f.read(1024)

        # 发送 audio_end
        await ws.send(json.dumps({"type": "audio_end"}))

        # 等待回复
        while True:
            msg = await ws.recv()
            if isinstance(msg, str):
                data = json.loads(msg)
                print("收到控制消息:", data)
                if data.get("type") == "audio_play_end":
                    break
            else:
                print(f"收到音频数据 {len(msg)} 字节")

asyncio.run(test())
```

```bash
python simulate_esp32.py
# 应看到：
# 收到控制消息: {"type": "state_change", "data": {"state": "PROCESSING"}}
# 收到控制消息: {"type": "display_update", ...}
# 收到音频数据 1024 字节 ...
# 收到控制消息: {"type": "audio_play_end"}
```

**最终提交：**
```bash
git add -A
git commit -m "feat: nanobot完整移植后端，全链路测试通过"
```

---

## 附录：task.md 章节对照表

| task.md 原章节 | 本计划对应实现 | 状态 |
|---|---|---|
| 7.1 项目初始化 | `server/` 目录 + `server/main.py` | 阶段五 |
| 7.2 `/ws/device` | `server/channels/device_channel.py` | 阶段三 |
| 7.2 `/ws/app` | `server/channels/app_channel.py` | 阶段四 |
| 7.2 REST API | `app_channel.py` 内 `/api/health`（其余后续补充） | 阶段四 |
| 7.3 SessionManager | nanobot 内置（共享 session_key） | nanobot 内置 |
| 7.4 ASR Whisper | `server/services/asr.py` (faster-whisper 本地) | 阶段二 |
| 7.5 TTS Edge-TTS | `server/services/tts.py` | 阶段二 |
| 7.6 LLM + Tool Use | nanobot AgentLoop（Claude API）| nanobot 内置 |
| 7.6 task_queue 工具 | `server/tools/task_queue_tool.py` | 阶段六 |
| 7.6 events 工具 | `server/tools/events_tool.py` | 阶段六 |
| 7.6 computer 工具 | nanobot 内置 exec 工具 + Skill | 阶段七 |
| 7.7 Nanobot 集成 | nanobot 就是核心，不再 subprocess 调用 | nanobot 内置 |
| 7.8 SQLite 对话历史 | nanobot MEMORY.md + HISTORY.md | nanobot 内置 |
| 7.8 SQLite tasks/events | `server/db/schema.sql` + `database.py` | 阶段一 |

---

## 附录：常见问题

| 问题 | 解决方法 |
|---|---|
| `faster_whisper` 第一次运行慢 | 首次自动下载 base 模型（~150MB），后续秒速 |
| `ffmpeg` 找不到 | `brew install ffmpeg` |
| `edge_tts` 需要网络 | Edge-TTS 依赖微软云，确保能访问外网 |
| 自定义工具未生效 | 确认 `main.py` 里 `agent.tools.register()` 已调用 |
| 两端消息不共享 | 检查 `session_key=SHARED_SESSION_KEY` 在两个 Channel 里一致 |
| nanobot 工具注册 API | 查看 `nanobot/agent/tools/registry.py` 的 `register()` 方法 |
