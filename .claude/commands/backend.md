你是 AI-Bot 桌面助手项目的后端开发助手，专门负责 `server/` 目录下的 Python 服务端代码。

## 项目架构概览

后端是一个 **异步事件驱动架构**，核心组件通过 MessageBus 解耦通信：

```
ESP32 设备 (WebSocket) ──┐
WhatsApp (Bridge WS)  ───┤
                         ▼
                    MessageBus (asyncio.Queue)
                    ┌─────┴─────┐
                    ▼           ▼
              AgentLoop     DeviceChannel
           (Nanobot移植)    (音频+状态机)
              │                │
         LiteLLM Provider   ASR / TTS
         (多模型支持)       (SenseVoice / Edge-TTS)
```

## 关键文件速查

| 功能 | 文件路径 | 说明 |
|------|----------|------|
| 入口 & 编排 | `server/main.py` | 服务启动、路由注册、统一出站消费者、优雅关闭 |
| 配置管理 | `server/config.py` + `config.yaml` | YAML 加载、环境变量覆盖、nanobot config 生成 |
| 设备通道 | `server/channels/device_channel.py` | WebSocket `/ws/device`、音频收发、状态机、心跳 |
| 语音识别 | `server/services/asr.py` | SenseVoice-Small (FunASR)，支持 VAD + 情感识别 |
| 语音合成 | `server/services/tts.py` | Edge-TTS (zh-CN-XiaoxiaoNeural)，MP3→PCM 流式传输 |
| 消息协议 | `server/models/protocol.py` | DeviceMessageType / ServerMessageType 枚举 |
| 设备状态机 | `server/models/device_state.py` | IDLE → LISTENING → PROCESSING → SPEAKING → IDLE |
| Agent 核心 | `server/nanobot/agent/loop.py` | 消息处理、工具调用循环、会话管理 |
| 上下文构建 | `server/nanobot/agent/context.py` | 系统提示词组装（SOUL + 记忆 + 技能 + 运行时） |
| 会话管理 | `server/nanobot/session/manager.py` | JSONL 持久化、历史裁剪、合并指针 |
| 记忆系统 | `server/nanobot/agent/memory.py` | MEMORY.md (长期事实) + HISTORY.md (可搜索日志) |
| 工具基类 | `server/nanobot/agent/tools/base.py` | Tool ABC + JSON Schema 验证 |
| 工具注册 | `server/nanobot/agent/tools/registry.py` | 动态注册、执行、错误处理 |
| LLM 抽象 | `server/nanobot/providers/litellm_provider.py` | LiteLLM 封装、多提供商、缓存控制 |
| WhatsApp | `server/nanobot/channels/whatsapp.py` | Node.js Bridge WebSocket 连接 |

## 核心设计模式

### 1. 消息总线 (MessageBus)
- `asyncio.Queue` 双队列：inbound（设备→Agent）、outbound（Agent→设备）
- 所有通道和 Agent 通过总线解耦，互不感知

### 2. 会话隔离
- Session Key 格式：`{channel}:{chat_id}`（如 `device:esp32`、`whatsapp:xxx`）
- 每个会话独立的对话历史、记忆、合并状态
- JSONL 文件存储，追加写入（利于 LLM 缓存）

### 3. 设备状态机
```
IDLE ──[触摸开始]──> LISTENING ──[音频结束]──> PROCESSING ──[AI回复]──> SPEAKING ──[播放完]──> IDLE
```
- 服务端维护状态，防止竞态条件
- 状态变更通过 JSON 消息同步到设备

### 4. 音频协议
- 格式：PCM 16kHz 16bit 单声道 (raw bytes, little-endian)
- 分块大小：4KB（≈128ms）
- 缓冲限制：最小 16KB (0.5s)，最大 960KB (30s)

### 5. 工具系统
- 所有工具继承 `Tool` ABC，提供 `name`、`description`、`parameters`（JSON Schema）、`execute()`
- `ToolRegistry` 动态注册和调用
- 内置工具：文件操作、Shell执行、Web搜索/获取、消息发送、子Agent、定时任务、MCP

### 6. 记忆合并
- 当未合并消息数 ≥ `memory_window` 时自动触发
- LLM 总结旧消息 → 更新 MEMORY.md + HISTORY.md
- `session.last_consolidated` 指针前移

## 编码规范

修改后端代码时必须遵守以下约定：

1. **全异步**：所有 I/O 用 `async/await`，CPU 密集操作用 `asyncio.to_thread()`
2. **类型注解**：所有函数签名必须有完整类型注解（Python 3.10+ 语法）
3. **数据类**：数据结构使用 `@dataclass`，协议常量使用 `str Enum`
4. **日志**：使用 `loguru`（`from loguru import logger`），不用 `print` 或 `logging`
5. **错误处理**：
   - `asyncio.CancelledError` 必须 re-raise
   - 工具错误返回 `f"Error: {msg}"`
   - LLM 错误不持久化（防止错误循环）
   - 降级策略：TTS 失败 → 文本回复
6. **配置**：密钥通过环境变量，不硬编码；YAML 支持 `${ENV_VAR}` 语法
7. **资源管理**：使用 `AsyncExitStack` / async context manager 确保清理
8. **弱引用**：循环依赖场景使用 `weakref.WeakValueDictionary`

## 开发工作流

### 修改现有功能
1. 先读取相关文件理解上下文（用 Grep 定位，不要全文读取）
2. 检查 `models/protocol.py` 和 `models/device_state.py` 确认协议定义
3. 修改代码后确保与现有异步模式一致
4. 如果改动涉及设备通信，同步检查 `channels/device_channel.py` 的状态机逻辑

### 添加新工具
1. 在 `server/nanobot/agent/tools/` 下创建新文件
2. 继承 `Tool` ABC，实现 `name`、`description`、`parameters`、`execute()`
3. 在 `loop.py` 的 `_register_default_tools()` 中注册

### 添加新通道
1. 继承 `server/nanobot/channels/base.py` 的 `BaseChannel`
2. 实现 `start()`、`stop()`、`send()` 方法
3. 在 `main.py` 中初始化并注册到出站消费者

### 添加新服务
1. 在 `server/services/` 下创建新文件
2. 遵循懒加载模式（模型在首次调用时加载）
3. 在 `main.py` 中初始化并注入到需要的组件

## 启动 & 测试

```bash
# 启动服务端
cd server && python main.py

# 测试客户端
python server/tools/test_client.py

# 健康检查
curl http://localhost:8765/api/health

# 设备信息
curl http://localhost:8765/api/device
```

## $ARGUMENTS 处理

用户会传入要执行的后端开发任务，例如：
- `添加新工具` → 按工具系统规范创建新的 Agent 工具
- `优化ASR` → 修改 `services/asr.py` 中的语音识别逻辑
- `新增通道` → 按通道模式添加新的消息通道
- `修改协议` → 更新 `models/protocol.py` 并同步所有引用
- `调试WebSocket` → 排查 `channels/device_channel.py` 中的连接问题
- `配置问题` → 检查 `config.py` 和 `config.yaml` 的配置逻辑

如果用户没有指定具体任务或描述不清楚，用 AskUserQuestion 工具询问具体需求。

**重要：每次完成后端改动后，必须提醒用户更新 `CHANGELOG.md` 工作日志。**
