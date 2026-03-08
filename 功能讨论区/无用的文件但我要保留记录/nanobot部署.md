# Nanobot 部署、移植与轻量化修改指南

> 创建日期: 2026-03-04
> 目标: 将 Nanobot 下载到本地，部署运行，并裁剪为适合 AI-Bot 项目的轻量版本

---

## 一、快速部署（先跑起来）

### 1.1 环境要求

- Python >= 3.11（推荐 3.12）
- pip 或 uv（包管理）
- 一个 LLM API Key（推荐 Anthropic Claude）

### 1.2 pip 安装（最快上手）

```bash
# 安装
pip install nanobot-ai

# 初始化配置
nanobot onboard

# 编辑配置文件，填入 API Key
# 配置文件位置: ~/.nanobot/config.json
```

配置文件最小示例：

```json
{
  "apiKey": "sk-ant-api03-你的Claude-API-Key",
  "model": "claude-sonnet-4-20250514",
  "provider": "anthropic"
}
```

### 1.3 测试运行

```bash
# 单次对话
nanobot agent -m "你好，介绍一下你自己"

# 交互模式（推荐）
nanobot agent

# 查看状态
nanobot status
```

看到 AI 回复就说明部署成功。先玩一玩，熟悉能力边界再往下走。

---

## 二、源码安装（为修改做准备）

### 2.1 克隆到本地

```bash
cd /Users/mandy/Documents/GitHub/AI-bot

# 克隆 Nanobot 源码
git clone https://github.com/HKUDS/nanobot.git nanobot-src

cd nanobot-src
```

### 2.2 创建虚拟环境

```bash
# 创建虚拟环境
python3 -m venv venv

# 激活
source venv/bin/activate    # macOS/Linux
# venv\Scripts\activate     # Windows

# 以开发模式安装（-e 表示可编辑，改代码立即生效）
pip install -e .
```

### 2.3 验证源码安装

```bash
# 确认是从本地源码加载的
which nanobot
# 应该显示: .../nanobot-src/venv/bin/nanobot

# 测试运行
nanobot agent -m "hello"
```

### 2.4 源码结构一览

```
nanobot-src/
├── nanobot/                    # 主代码（我们要修改的部分）
│   ├── agent/                  # 核心 Agent
│   │   ├── loop.py             #   Agent 循环 (509行) ★ 核心中的核心
│   │   ├── context.py          #   Prompt 构建 (173行) ★
│   │   ├── memory.py           #   持久记忆 (150行) ★
│   │   ├── skills.py           #   技能加载 (228行) ★
│   │   ├── subagent.py         #   子Agent (246行) — 可裁剪
│   │   └── tools/              #   内置工具
│   │       ├── base.py         #     工具基类 (104行) ★
│   │       ├── registry.py     #     工具注册表 (66行) ★
│   │       ├── filesystem.py   #     文件读写 (227行) ★
│   │       ├── shell.py        #     Shell执行 (158行) ★
│   │       ├── web.py          #     网页搜索/抓取 (181行) ★
│   │       ├── spawn.py        #     子Agent派生 (63行) ✂️
│   │       ├── cron.py         #     定时任务工具 (155行) ✂️
│   │       ├── message.py      #     消息发送 (109行) ✂️
│   │       └── mcp.py          #     MCP协议 (99行) ✂️
│   ├── providers/              # LLM 提供商
│   │   ├── base.py             #   Provider 基类 (118行) ★
│   │   ├── registry.py         #   Provider 注册表 (462行) ★
│   │   ├── litellm_provider.py #   LiteLLM 实现 (295行) ★
│   │   ├── custom_provider.py  #   自定义 Provider (55行)
│   │   ├── openai_codex_provider.py # Codex (313行) ✂️
│   │   └── transcription.py    #   语音转写 (64行)
│   ├── channels/               # 聊天渠道 ✂️ 全部可裁剪
│   │   ├── base.py             #   渠道基类 (119行)
│   │   ├── manager.py          #   渠道管理 (255行)
│   │   ├── telegram.py         #   (504行) ✂️
│   │   ├── discord.py          #   (300行) ✂️
│   │   ├── slack.py            #   (280行) ✂️
│   │   ├── email.py            #   (408行) ✂️
│   │   ├── feishu.py           #   (764行) ✂️
│   │   ├── dingtalk.py         #   (438行) ✂️
│   │   ├── matrix.py           #   (699行) ✂️
│   │   ├── whatsapp.py         #   (157行) ✂️
│   │   ├── qq.py               #   (135行) ✂️
│   │   └── mochat.py           #   (895行) ✂️
│   ├── bus/                    # 消息总线
│   │   ├── events.py           #   消息事件 (38行) ★
│   │   └── queue.py            #   异步队列 (44行) ★
│   ├── session/                # 会话管理
│   │   └── manager.py          #   (212行) ★
│   ├── config/                 # 配置系统
│   │   ├── schema.py           #   配置Schema (412行，可精简)
│   │   └── loader.py           #   配置加载 (69行) ★
│   ├── cli/                    # 命令行
│   │   └── commands.py         #   CLI命令 (911行，可精简)
│   ├── cron/                   # 定时任务 ✂️
│   ├── heartbeat/              # 心跳监控 ✂️
│   ├── skills/                 # 内置技能（保留 weather、memory）
│   ├── templates/              # 提示词模板
│   └── utils/                  # 工具函数
├── bridge/                     # WhatsApp桥接 (Node.js) ✂️
├── pyproject.toml              # 项目配置
├── Dockerfile
└── docker-compose.yml
```

> ★ = 核心必须保留 | ✂️ = 轻量化时裁剪

---

## 三、轻量化裁剪

### 3.1 裁剪目标

| | 原版 | 轻量版 |
|---|---|---|
| 代码行数 | ~11,165 行 (57个.py文件) | ~3,000 行 |
| 依赖包 | 25+ 个 | ~13 个 |
| 功能 | CLI + 10个聊天平台 + 定时任务 + 心跳 | 纯 Agent 对话引擎 |

我们只需要 Nanobot 的核心能力：**Agent Loop + LLM调用 + 工具执行 + 记忆**。不需要聊天平台、定时任务、心跳监控。

### 3.2 第一步：删除不需要的文件

**逐步删除，每删一批就测试一次。不要一次全删再调试。**

```bash
cd nanobot-src

# ────── 第1批：删除聊天渠道实现（影响最小） ──────
rm nanobot/channels/telegram.py
rm nanobot/channels/discord.py
rm nanobot/channels/slack.py
rm nanobot/channels/email.py
rm nanobot/channels/feishu.py
rm nanobot/channels/dingtalk.py
rm nanobot/channels/matrix.py
rm nanobot/channels/whatsapp.py
rm nanobot/channels/qq.py
rm nanobot/channels/mochat.py

# 测试: nanobot agent -m "test"

# ────── 第2批：删除定时任务和心跳 ──────
rm -rf nanobot/cron/
rm -rf nanobot/heartbeat/

# 测试: nanobot agent -m "test"

# ────── 第3批：删除 WhatsApp Node.js 桥接 ──────
rm -rf bridge/

# ────── 第4批：删除不需要的工具和子Agent ──────
rm nanobot/agent/tools/cron.py
rm nanobot/agent/tools/message.py
rm nanobot/agent/tools/spawn.py
rm nanobot/agent/tools/mcp.py
rm nanobot/agent/subagent.py

# 测试: nanobot agent -m "test"

# ────── 第5批：删除不需要的 Provider ──────
rm nanobot/providers/openai_codex_provider.py
```

### 3.3 第二步：修复 import 错误

每删一批文件后运行 `nanobot agent -m "test"`，根据报错逐个修复。主要改这几个文件：

#### `nanobot/agent/loop.py` — 删除裁剪模块的引用

搜索并删除/注释掉：

```python
# 删除这些 import:
from nanobot.agent.subagent import SubagentManager     # 删
from nanobot.agent.tools.cron import CronTool           # 删
from nanobot.agent.tools.message import MessageTool     # 删
from nanobot.agent.tools.spawn import SpawnTool         # 删
from nanobot.agent.tools.mcp import ...                 # 删

# 删除注册这些工具的代码（搜索关键词定位）:
# registry.register(CronTool(...))
# registry.register(MessageTool(...))
# registry.register(SpawnTool(...))

# 删除 subagent 相关逻辑（搜索 "subagent" 或 "SubagentManager"）
# 删除 MCP 相关逻辑（搜索 "mcp"）
```

#### `nanobot/channels/manager.py` — 清空渠道初始化

```python
# _init_channels() 方法中，删除所有具体渠道的 import 和初始化
# 只保留空方法体:
def _init_channels(self):
    pass
```

#### `nanobot/cli/commands.py` — 删除多余命令

```python
# 删除 gateway 命令（启动聊天网关）
# 删除 cron 命令（定时任务管理）
# 删除 channels 命令
# 只保留: agent、onboard、status、memory、skills
```

#### `nanobot/config/schema.py` — 精简配置类

```python
# 删除所有渠道配置类:
# WhatsAppConfig, TelegramConfig, FeishuConfig, DingTalkConfig,
# DiscordConfig, MatrixConfig, EmailConfig, SlackConfig, QQConfig, MochatConfig

# 对应的主配置类字段也要删
```

### 3.4 第三步：精简依赖

编辑 `pyproject.toml`，把 dependencies 替换为：

```toml
dependencies = [
    "typer>=0.20.0,<1.0.0",           # CLI框架
    "litellm>=1.81.5,<2.0.0",         # 多LLM统一调用（核心）
    "pydantic>=2.12.0,<3.0.0",        # 数据校验
    "pydantic-settings>=2.12.0,<3.0.0",
    "httpx>=0.28.0,<1.0.0",           # HTTP请求（网页工具）
    "loguru>=0.7.3,<1.0.0",           # 日志
    "readability-lxml>=0.8.4,<1.0.0", # 网页正文提取
    "rich>=14.0.0,<15.0.0",           # 终端美化
    "prompt-toolkit>=3.0.50,<4.0.0",  # 交互式输入
    "json-repair>=0.57.0,<1.0.0",     # 修复LLM返回的坏JSON
    "websockets>=16.0,<17.0",         # WebSocket
    "msgpack>=1.1.0,<2.0.0",          # 序列化
    "openai>=2.8.0",                   # OpenAI SDK
]
# 删掉的: dingtalk-stream, python-telegram-bot, lark-oapi,
# slack-sdk, slackify-markdown, qq-botpy, python-socketio,
# croniter, oauth-cli-kit, mcp, socksio, python-socks, websocket-client
```

然后重新安装：

```bash
# 清除旧安装
pip install -e .

# 测试
nanobot agent -m "你好"
```

### 3.5 第四步：验证裁剪效果

```bash
# 统计行数
find nanobot -name "*.py" | xargs wc -l | tail -1
# 目标: ~3,000 行（原 11,165 行，缩减 ~73%）
```

### 3.6 裁剪后保留的文件

```
nanobot/
├── agent/
│   ├── loop.py             # Agent 循环
│   ├── context.py          # Prompt 构建
│   ├── memory.py           # 持久记忆
│   ├── skills.py           # 技能加载
│   └── tools/
│       ├── base.py         # 工具基类
│       ├── registry.py     # 工具注册
│       ├── filesystem.py   # 文件操作
│       ├── shell.py        # Shell执行（电脑控制的核心）
│       └── web.py          # 网页搜索/抓取
├── providers/
│   ├── base.py             # Provider 基类
│   ├── registry.py         # Provider 注册表
│   ├── litellm_provider.py # LiteLLM 实现
│   └── custom_provider.py  # 自定义 Provider
├── bus/
│   ├── events.py           # 消息事件
│   └── queue.py            # 异步队列
├── session/
│   └── manager.py          # 会话持久化
├── config/
│   ├── schema.py           # 配置（精简版）
│   └── loader.py           # 配置加载
├── cli/
│   └── commands.py         # CLI（精简版）
├── skills/                 # 保留 weather、memory
├── templates/
└── utils/
```

---

## 四、集成到 AI-Bot 服务端

### 4.1 整体架构

```
AI-Bot 服务端 (FastAPI)
├── main.py
├── api/
│   └── ws_device.py              # ESP32 WebSocket 端点
├── services/
│   ├── asr.py                    # Whisper 语音识别
│   ├── tts.py                    # Edge-TTS 语音合成
│   └── nanobot_engine.py         # ★ 封装 Nanobot Agent
└── nanobot-src/                  # ★ 裁剪后的 Nanobot
```

### 4.2 封装调用接口

Nanobot 的 `AgentLoop` 提供了 `process_direct()` 方法，可以直接传入文本返回回复，不用走 CLI 或聊天渠道：

```python
# services/nanobot_engine.py

from nanobot.agent.loop import AgentLoop
from nanobot.config.loader import load_config
from nanobot.providers.litellm_provider import LiteLLMProvider
from nanobot.session.manager import SessionManager
from nanobot.bus.queue import MessageBus

class NanobotEngine:
    """封装 Nanobot Agent，供 AI-Bot 服务端调用"""

    def __init__(self):
        self.config = load_config()
        self.bus = MessageBus()
        self.sessions = SessionManager()
        self.provider = LiteLLMProvider(self.config)
        self.agent = AgentLoop(
            config=self.config,
            provider=self.provider,
            bus=self.bus,
            sessions=self.sessions,
        )

    async def chat(self, user_text: str, session_id: str = "device") -> str:
        """输入用户文本，返回 AI 回复"""
        response = await self.agent.process_direct(
            text=user_text,
            session_key=session_id,
        )
        return response
```

### 4.3 一次完整对话的数据流

```
ESP32 麦克风录音
      │
      │  ① WebSocket 发送二进制音频帧
      ▼
FastAPI ws_device.py 接收
      │
      │  ② 音频交给 Whisper
      ▼
Whisper (ASR) → "帮我打开微信"
      │
      │  ③ 文本交给 Nanobot
      ▼
NanobotEngine.chat("帮我打开微信")
      │
      ├──► Agent Loop 开始
      │      │
      │      ▼  发给 Claude API
      │    Claude 返回: tool_use → shell("open -a WeChat")
      │      │
      │      ▼  shell.py 执行命令
      │    微信被打开 ✓
      │      │
      │      ▼  执行结果反馈给 Claude
      │    Claude 生成回复: "好的，微信已经打开了"
      │
      ▼
Edge-TTS 文字→语音
      │
      │  ④ WebSocket 发送 PCM 音频帧
      ▼
ESP32 喇叭播放: "好的，微信已经打开了"
```

### 4.4 添加自定义工具示例

比如加一个"屏幕控制"工具，让 AI 能更新 ESP32 显示：

```python
# nanobot-src/nanobot/agent/tools/display.py

from nanobot.agent.tools.base import Tool

class DisplayUpdate(Tool):
    name = "display_update"
    description = "更新硬件设备的屏幕显示内容"
    parameters = {
        "type": "object",
        "properties": {
            "screen": {
                "type": "string",
                "enum": ["clock", "weather", "message", "status"],
            },
            "content": {"type": "string"},
        },
        "required": ["screen"]
    }

    def __init__(self, callback):
        self.callback = callback  # 回调函数，通知 FastAPI 发 WebSocket 给 ESP32

    async def execute(self, **kwargs):
        await self.callback(kwargs)
        return f"屏幕已更新: {kwargs['screen']}"
```

在 `loop.py` 中注册：

```python
from nanobot.agent.tools.display import DisplayUpdate
registry.register(DisplayUpdate(callback=display_callback))
```

---

## 五、操作顺序总结

```
第一阶段：先跑通原版 ──────────────────────
  ① pip install nanobot-ai
  ② 配置 ~/.nanobot/config.json（填 API Key）
  ③ nanobot agent 交互测试
  ④ 熟悉它能做什么、不能做什么

第二阶段：源码部署 ────────────────────────
  ⑤ git clone 到本地 nanobot-src/
  ⑥ python3 -m venv venv && pip install -e .
  ⑦ 确认源码模式运行正常

第三阶段：轻量化裁剪 ──────────────────────
  ⑧ 逐批删除文件（每删一批就测试）
     channels → cron/heartbeat → tools → provider
  ⑨ 修复 import 错误（loop.py、manager.py、commands.py、schema.py）
  ⑩ 精简 pyproject.toml 依赖
  ⑪ 重新 pip install -e . 并测试
  ⑫ 验证行数 ~3,000 行

第四阶段：集成到 AI-Bot 服务端 ────────────
  ⑬ 编写 NanobotEngine 封装类
  ⑭ FastAPI 中调用 engine.chat()
  ⑮ 添加自定义工具（屏幕控制、LED控制等）
  ⑯ 端到端测试: ESP32 → 服务端 → Nanobot → TTS → ESP32
```

---

## 六、注意事项

1. **API Key 安全**：`~/.nanobot/config.json` 含 API Key，加入 .gitignore
2. **逐步裁剪**：每删一个模块就测试一次，别一口气全删
3. **litellm 是核心**：它统一了 15+ 家 LLM 的 API 调用，别删
4. **shell 工具 = 电脑控制**：Nanobot 的 `shell.py` 能执行任意终端命令，本身就具备电脑控制能力，不一定需要额外封装
5. **process_direct() 是关键接口**：服务端通过这个方法调用 Nanobot，要熟悉它的参数和返回值
6. **MIT 许可证**：可自由修改和商用
