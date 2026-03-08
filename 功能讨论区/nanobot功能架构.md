# Nanobot 功能架构文档

> 基于源码分析生成，供参考删改。
> 源码路径：`nanobot-src/`，约 4000 行 Python 代码。

---

## 一、整体架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                         Chat Channels（消息通道）                 │
│  Telegram / Discord / WhatsApp / Feishu / Slack / QQ / DingTalk │
│            Matrix / Email / Mochat / CLI                        │
└─────────────┬───────────────────────────────────┬───────────────┘
              │ InboundMessage                    │ OutboundMessage
              ▼                                   ▲
┌─────────────────────────────────────────────────────────────────┐
│                    MessageBus（消息总线）                          │
│          channels/manager.py  +  bus/queue.py                   │
└─────────────┬───────────────────────────────────┬───────────────┘
              │                                   │
              ▼                                   │
┌─────────────────────────────────────────────────────────────────┐
│                    AgentLoop（核心循环）                           │
│                       agent/loop.py                             │
│                                                                 │
│  ContextBuilder ──► LLM Provider ──► Tool Execution ──► 回复     │
│  (context.py)        (providers/)     (tools/)                  │
└──────────┬────────────────┬────────────────────────────────────┘
           │                │
     ┌─────▼─────┐   ┌──────▼──────┐
     │MemoryStore│   │SubagentMgr  │
     │(memory.py)│   │(subagent.py)│
     └───────────┘   └─────────────┘

┌──────────────────┐   ┌──────────────────┐
│  CronService     │   │  HeartbeatService │
│  (cron/)         │   │  (heartbeat/)     │
└──────────────────┘   └──────────────────┘
```

---

## 二、核心模块详解

### 1. AgentLoop（核心 Agent 循环）
**文件：** `nanobot/agent/loop.py`

主循环：从 MessageBus 取消息 → 构建上下文 → 调用 LLM → 执行工具 → 返回响应。

**主要参数：**
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `model` | `anthropic/claude-opus-4-5` | 使用的 LLM 模型 |
| `max_iterations` | 40 | 单次请求最大工具调用轮数 |
| `temperature` | 0.1 | 生成温度 |
| `max_tokens` | 4096 | 最大 token 数 |
| `memory_window` | 100 | 会话历史窗口大小 |
| `reasoning_effort` | None | 思考模式（low/medium/high） |
| `restrict_to_workspace` | false | 是否限制工具只能访问 workspace 目录 |

**内置 Slash 命令：**
- `/new` — 开启新会话（归档当前记忆）
- `/stop` — 停止当前正在运行的任务
- `/help` — 显示帮助

---

### 2. ContextBuilder（上下文构建）
**文件：** `nanobot/agent/context.py`

构建发送给 LLM 的 messages 列表，包含：
- 系统 prompt（含运行时信息：当前时间、workspace、channel、chat_id）
- 长期记忆（来自 `MEMORY.md`）
- 技能摘要（Skills XML）
- 会话历史
- 当前用户消息（支持多模态：文字 + 图片）

---

### 3. MemoryStore（记忆系统）
**文件：** `nanobot/agent/memory.py`

两层记忆结构：
- **长期记忆：** `workspace/memory/MEMORY.md` — LLM 提炼的 Markdown 格式事实
- **历史日志：** `workspace/memory/HISTORY.md` — 可 grep 的时间戳日志

**触发机制：** 当会话 messages 数量达到 `memory_window` 时，自动调用 LLM（工具调用 `save_memory`）压缩旧消息，更新两个文件，并清理 session。
用户发送 `/new` 也会强制触发归档。

---

### 4. SubagentManager（子 Agent）
**文件：** `nanobot/agent/subagent.py`

主 Agent 可以通过 `spawn` 工具派生一个后台子 Agent 异步执行任务：
- 子 Agent 有独立的 ToolRegistry（无 message/spawn 工具，防止递归）
- 最大迭代次数 15 次（比主 Agent 少）
- 完成后通过 MessageBus `system` 频道将结果注入主 Agent，由主 Agent 整理后回复用户

---

### 5. CronService（定时任务）
**文件：** `nanobot/cron/service.py`

支持三种调度类型：
| 类型 | 格式 | 说明 |
|------|------|------|
| `at` | Unix 时间戳(ms) | 单次执行，执行后禁用或删除 |
| `every` | 毫秒间隔 | 周期性重复执行 |
| `cron` | cron 表达式 | 标准 cron 格式，支持时区 |

任务配置保存在 `workspace/cron/jobs.json`，支持文件外部修改后自动热加载。
每个任务 payload 含 `message`（发给 Agent 的指令），可配置 `deliver: true` 将结果推送到指定 channel。

---

### 6. HeartbeatService（心跳服务）
**文件：** `nanobot/heartbeat/service.py`

每 30 分钟（可配置）检查一次 `workspace/HEARTBEAT.md`：
- **Phase 1（决策）：** 调用 LLM 判断是否有需执行的任务（工具调用 `heartbeat`，返回 `skip` 或 `run`）
- **Phase 2（执行）：** 若有任务，通过完整 Agent 循环执行，并将结果推送到最近活跃的 channel

```markdown
# HEARTBEAT.md 示例
## Periodic Tasks
- [ ] 检查天气预报并发送摘要
- [ ] 扫描收件箱中的紧急邮件
```

---

### 7. MessageBus（消息总线）
**文件：** `nanobot/bus/queue.py` + `nanobot/bus/events.py`

异步队列，解耦 Channel（消息来源）和 AgentLoop（处理器）。

两种消息类型：
- `InboundMessage`: 从 Channel 接收，含 `channel`, `sender_id`, `chat_id`, `content`, `media[]`, `metadata`, `session_key`
- `OutboundMessage`: 发送给 Channel，含 `channel`, `chat_id`, `content`, `reply_to`, `media[]`, `metadata`

---

### 8. SessionManager（会话管理）
**文件：** `nanobot/session/manager.py`

按 `session_key`（默认为 `channel:chat_id`）隔离多用户/多平台会话。
Session 包含 messages 历史，持久化到 workspace 目录。

---

## 三、内置工具（Built-in Tools）

| 工具名 | 文件 | 功能 |
|--------|------|------|
| `read_file` | `tools/filesystem.py` | 读取文件内容 |
| `write_file` | `tools/filesystem.py` | 写入文件（自动创建父目录） |
| `edit_file` | `tools/filesystem.py` | 精确替换文件中的文本段 |
| `list_dir` | `tools/filesystem.py` | 列出目录内容 |
| `exec` | `tools/shell.py` | 执行 shell 命令（有安全过滤，超时 60s） |
| `web_search` | `tools/web.py` | Brave Search API 搜索（最多返回 10 条） |
| `web_fetch` | `tools/web.py` | 抓取 URL 并提取正文（HTML→Markdown/text） |
| `message` | `tools/message.py` | 主动向用户推送消息（中途通知） |
| `spawn` | `tools/spawn.py` | 派生后台子 Agent 执行长任务 |
| `cron` | `tools/cron.py` | 创建/管理/删除定时任务 |
| MCP 工具 | `tools/mcp.py` | 动态挂载外部 MCP Server 的工具 |

**exec 工具安全限制（deny_patterns）：**
- 禁止 `rm -rf`、`del /f`、`rmdir /s`
- 禁止 `format`、`mkfs`、`diskpart`、`dd if=`
- 禁止 `shutdown`、`reboot`、`poweroff`
- 禁止 fork bomb `: () { : | : & }; :`
- `restrict_to_workspace=true` 时禁止访问 workspace 外的绝对路径

---

## 四、内置技能（Built-in Skills）

技能是 `SKILL.md` Markdown 文件，指导 Agent 如何使用特定工具或完成特定任务。
Agent 在 context 中会收到所有技能的摘要（XML 格式），按需用 `read_file` 读取完整内容。

| 技能名 | 路径 | 说明 |
|--------|------|------|
| `memory` | `skills/memory/SKILL.md` | 记忆管理（MEMORY.md 写法规范） |
| `cron` | `skills/cron/SKILL.md` | 定时任务的创建与管理 |
| `weather` | `skills/weather/SKILL.md` | 天气查询（需要 CLI 工具） |
| `tmux` | `skills/tmux/SKILL.md` | tmux 会话控制（需要 tmux 命令） |
| `github` | `skills/github/SKILL.md` | GitHub 操作（需要 gh CLI） |
| `summarize` | `skills/summarize/SKILL.md` | 内容摘要 |
| `clawhub` | `skills/clawhub/SKILL.md` | ClawHub 公共技能市场的搜索与安装 |
| `skill-creator` | `skills/skill-creator/SKILL.md` | 创建新技能 |

**技能加载机制：**
1. 优先从 `workspace/skills/` 加载（用户自定义）
2. 其次从内置 `nanobot/skills/` 加载
3. 有 `always: true` 标记的技能每次都注入 context
4. 其余技能通过摘要进入 context，Agent 按需 `read_file` 获取详情
5. 技能可设置 `requires.bins` / `requires.env` 做可用性检测

---

## 五、LLM Provider（模型提供商）

**文件：** `nanobot/providers/`

| Provider 名 | 说明 |
|-------------|------|
| `custom` | 任意 OpenAI 兼容接口（直连，不经 LiteLLM） |
| `openrouter` | OpenRouter（推荐，全模型） |
| `anthropic` | Claude 直连 |
| `openai` | GPT 直连 |
| `deepseek` | DeepSeek 直连 |
| `groq` | Groq（LLM + Whisper 语音转录） |
| `gemini` | Google Gemini 直连 |
| `minimax` | MiniMax 直连 |
| `aihubmix` | AiHubMix API 网关 |
| `siliconflow` | 硅基流动 |
| `volcengine` | 火山引擎 |
| `dashscope` | 阿里云通义千问 |
| `moonshot` | Moonshot/Kimi |
| `zhipu` | 智谱 GLM |
| `vllm` | 本地 vLLM 或任意 OpenAI 兼容本地服务 |
| `openai_codex` | OpenAI Codex（OAuth 登录，需 ChatGPT Plus） |
| `github_copilot` | GitHub Copilot（OAuth 登录） |

**Provider 自动匹配逻辑（`provider: "auto"` 时）：**
1. 模型名前缀精确匹配（如 `anthropic/...`）
2. 关键词匹配（在 registry.py 的 `keywords` 字段中定义）
3. 兜底：有 API Key 的第一个 Provider

---

## 六、消息通道（Channels）

**文件：** `nanobot/channels/`

所有 Channel 继承 `BaseChannel`，实现 `start()`、`stop()`、`send()` 三个接口。

### 6.1 各 Channel 汇总

| Channel | 协议/方式 | 需要公网 IP | 主要配置项 |
|---------|----------|------------|-----------|
| **Telegram** | HTTP Polling | 否 | `token`, `allowFrom`, `proxy`, `reply_to_message` |
| **Discord** | WebSocket Gateway | 否 | `token`, `allowFrom`, `intents` |
| **WhatsApp** | WebSocket（bridge） | 否 | `bridge_url`, `allowFrom` |
| **Feishu (飞书)** | WebSocket 长连接 | 否 | `appId`, `appSecret`, `allowFrom`, `react_emoji` |
| **DingTalk (钉钉)** | Stream 模式 | 否 | `clientId`, `clientSecret`, `allowFrom` |
| **Slack** | Socket Mode | 否 | `botToken`, `appToken`, `allowFrom`, `groupPolicy` |
| **QQ** | botpy SDK WebSocket | 否 | `appId`, `secret`, `allowFrom` |
| **Matrix (Element)** | Matrix Sync API | 否 | `homeserver`, `accessToken`, `userId`, `e2eeEnabled` |
| **Email** | IMAP 轮询 + SMTP | 否 | `imapHost/Port`, `smtpHost/Port`, `allowFrom` |
| **Mochat** | Socket.IO WebSocket | 否 | `base_url`, `claw_token`, `agent_user_id` |
| **CLI** | 本地命令行 | — | 内置，无需配置 |

### 6.2 各 Channel 详细参数

#### Telegram
```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "BOT_TOKEN",
      "allowFrom": ["USER_ID"],
      "proxy": null,
      "replyToMessage": false
    }
  }
}
```
- `allowFrom` 为空 → 拒绝所有；`["*"]` → 允许所有
- Groq 配置后自动支持语音消息转录（Whisper）

#### Discord
```json
{
  "channels": {
    "discord": {
      "enabled": true,
      "token": "BOT_TOKEN",
      "allowFrom": ["USER_ID"],
      "gatewayUrl": "wss://gateway.discord.gg/?v=10&encoding=json",
      "intents": 37377
    }
  }
}
```
- `intents`: GUILDS + GUILD_MESSAGES + DIRECT_MESSAGES + MESSAGE_CONTENT

#### WhatsApp
```json
{
  "channels": {
    "whatsapp": {
      "enabled": true,
      "bridgeUrl": "ws://localhost:3001",
      "bridgeToken": "",
      "allowFrom": ["+1234567890"]
    }
  }
}
```
- 需要 Node.js ≥18，运行独立的 bridge 服务
- 首次使用：`nanobot channels login` 扫码绑定

#### Feishu (飞书)
```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "cli_xxx",
      "appSecret": "xxx",
      "encryptKey": "",
      "verificationToken": "",
      "allowFrom": ["ou_YOUR_OPEN_ID"],
      "reactEmoji": "THUMBSUP"
    }
  }
}
```
- 支持 `THUMBSUP`, `OK`, `DONE`, `SMILE` 等回应表情
- 不需要公网 IP，使用 WebSocket 长连接

#### DingTalk (钉钉)
```json
{
  "channels": {
    "dingtalk": {
      "enabled": true,
      "clientId": "APP_KEY",
      "clientSecret": "APP_SECRET",
      "allowFrom": ["STAFF_ID"]
    }
  }
}
```
- Stream Mode，无需公网 IP

#### Slack
```json
{
  "channels": {
    "slack": {
      "enabled": true,
      "botToken": "xoxb-...",
      "appToken": "xapp-...",
      "allowFrom": ["USER_ID"],
      "groupPolicy": "mention",
      "groupAllowFrom": [],
      "replyInThread": true,
      "reactEmoji": "eyes",
      "dm": {
        "enabled": true,
        "policy": "open"
      }
    }
  }
}
```
- `groupPolicy`: `mention`（仅 @ 触发）/ `open`（所有消息）/ `allowlist`（指定频道）
- Socket Mode，无需公网 IP

#### QQ
```json
{
  "channels": {
    "qq": {
      "enabled": true,
      "appId": "APP_ID",
      "secret": "APP_SECRET",
      "allowFrom": ["OPENID"]
    }
  }
}
```
- 目前仅支持私聊（单聊），不支持群聊

#### Matrix (Element)
```json
{
  "channels": {
    "matrix": {
      "enabled": true,
      "homeserver": "https://matrix.org",
      "userId": "@bot:matrix.org",
      "accessToken": "syt_xxx",
      "deviceId": "NANOBOT01",
      "e2eeEnabled": true,
      "allowFrom": ["@user:matrix.org"],
      "groupPolicy": "open",
      "groupAllowFrom": [],
      "allowRoomMentions": false,
      "maxMediaBytes": 20971520
    }
  }
}
```
- 支持端对端加密（E2EE）
- 需额外安装：`pip install nanobot-ai[matrix]`

#### Email
```json
{
  "channels": {
    "email": {
      "enabled": true,
      "consentGranted": true,
      "imapHost": "imap.gmail.com",
      "imapPort": 993,
      "imapUsername": "bot@gmail.com",
      "imapPassword": "app-password",
      "smtpHost": "smtp.gmail.com",
      "smtpPort": 587,
      "smtpUsername": "bot@gmail.com",
      "smtpPassword": "app-password",
      "fromAddress": "bot@gmail.com",
      "allowFrom": ["your@email.com"],
      "autoReplyEnabled": true,
      "pollIntervalSeconds": 30,
      "maxBodyChars": 12000
    }
  }
}
```
- IMAP 轮询收信，SMTP 发信
- `consentGranted: true` 是必须的安全门控

#### Mochat
```json
{
  "channels": {
    "mochat": {
      "enabled": true,
      "baseUrl": "https://mochat.io",
      "socketUrl": "",
      "clawToken": "claw_xxx",
      "agentUserId": "6982abcdef",
      "sessions": ["*"],
      "panels": ["*"],
      "allowFrom": ["*"],
      "replyDelayMode": "non-mention",
      "replyDelayMs": 120000
    }
  }
}
```

### 6.3 通用 Channel 配置
```json
{
  "channels": {
    "sendProgress": true,
    "sendToolHints": false
  }
}
```
- `sendProgress`: 是否在工具调用过程中实时推送进度文字
- `sendToolHints`: 是否推送工具调用提示（如 `web_search("query")`）

### 6.4 allowFrom 权限规则
- `[]`（空列表）→ **拒绝所有访问**（v0.1.4.post3+ 新版本行为）
- `["*"]` → 允许所有用户
- `["id1", "id2"]` → 仅允许指定用户

---

## 七、MCP（Model Context Protocol）支持

**文件：** `nanobot/agent/tools/mcp.py`

```json
{
  "tools": {
    "mcpServers": {
      "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
      },
      "my-remote-mcp": {
        "url": "https://example.com/mcp/",
        "headers": {"Authorization": "Bearer xxxxx"},
        "toolTimeout": 120
      }
    }
  }
}
```

| 传输模式 | 配置 |
|----------|------|
| Stdio | `command` + `args` + `env` |
| HTTP (Streamable HTTP) | `url` + `headers` |

MCP 工具在 gateway 启动时自动发现，与内置工具完全透明地一起提供给 LLM。

---

## 八、配置总览（`~/.nanobot/config.json`）

```json
{
  "agents": {
    "defaults": {
      "workspace": "~/.nanobot/workspace",
      "model": "anthropic/claude-opus-4-5",
      "provider": "auto",
      "maxTokens": 8192,
      "temperature": 0.1,
      "maxToolIterations": 40,
      "memoryWindow": 100,
      "reasoningEffort": null
    }
  },
  "providers": {
    "openrouter": {"apiKey": "sk-or-v1-xxx"},
    "anthropic": {"apiKey": "sk-ant-xxx"},
    "groq": {"apiKey": "gsk_xxx"}
  },
  "channels": { ... },
  "tools": {
    "restrictToWorkspace": false,
    "exec": {"timeout": 60, "pathAppend": ""},
    "web": {
      "proxy": null,
      "search": {"apiKey": "BRAVE_KEY", "maxResults": 5}
    },
    "mcpServers": {}
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 18790,
    "heartbeat": {"enabled": true, "intervalS": 1800}
  }
}
```

---

## 九、CLI 命令参考

| 命令 | 说明 |
|------|------|
| `nanobot onboard` | 初始化 config 和 workspace |
| `nanobot agent` | 交互式 CLI 对话模式 |
| `nanobot agent -m "..."` | 单次对话 |
| `nanobot agent --no-markdown` | 纯文本输出 |
| `nanobot agent --logs` | 显示运行日志 |
| `nanobot gateway` | 启动 Gateway（连接所有启用的 Channel） |
| `nanobot status` | 显示当前状态（模型、provider、channel） |
| `nanobot provider login openai-codex` | OAuth 登录 |
| `nanobot channels login` | WhatsApp 扫码绑定 |
| `nanobot channels status` | 显示 channel 状态 |

**交互模式退出：** `exit` / `quit` / `/exit` / `/quit` / `:q` / Ctrl+D

---

## 十、工作空间（Workspace）目录结构

```
~/.nanobot/workspace/
├── HEARTBEAT.md          # 心跳任务列表（手动编辑）
├── memory/
│   ├── MEMORY.md         # 长期记忆（LLM 自动维护）
│   └── HISTORY.md        # 历史日志（时间戳，可 grep）
├── cron/
│   └── jobs.json         # 定时任务存储
└── skills/               # 用户自定义技能（优先级高于内置）
    └── my-skill/
        └── SKILL.md
```

---

## 十一、安全机制

| 机制 | 说明 |
|------|------|
| `allowFrom` 白名单 | 每个 Channel 独立配置允许的用户 ID，空列表=拒绝所有 |
| `restrictToWorkspace` | 限制文件/Shell 工具只能操作 workspace 目录 |
| `exec` deny_patterns | 正则过滤危险 shell 命令（rm -rf 等） |
| `consentGranted` | Email channel 的明确授权门控 |
| `exec` 超时 | 默认 60 秒，防止命令挂起 |
| `web_fetch` URL 校验 | 仅允许 http/https，限制重定向次数（最多 5 次） |

---

*文档生成时间：2026-03-05*
