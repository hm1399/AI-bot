# Nanobot 调研

> 项目地址：https://github.com/HKUDS/nanobot
> 官网：https://www.nanobot.pro/
> 调研日期：2026-02-11

## 一、项目概述

Nanobot 是香港大学数据科学实验室（HKUDS）开源的超轻量级个人 AI 助手，灵感来自 OpenClaw/Clawdbot。

核心卖点：仅约 **3,510 行核心代码**（OpenClaw 有 43 万+ 行），体积缩小 99%，但保留了 Agent 的核心能力闭环。

- GitHub Stars：16.5k
- Forks：2.4k
- 语言：Python 94.7%，TypeScript 2.4%，Shell 2.1%
- 许可证：MIT
- 首次发布：2026-02-02
- 最新版本：v0.1.3.post6（2026-02-10）
- 贡献者：32 人

## 二、核心特性

| 特性 | 说明 |
|------|------|
| 超轻量 | ~4,000 行核心 Agent 代码，启动快、资源占用低 |
| 研究友好 | 代码干净可读，适合学习 AI Agent 架构和二次开发 |
| 一键部署 | `pip install nanobot-ai` 即可使用 |
| 多 LLM 支持 | OpenRouter、Anthropic、OpenAI、DeepSeek、Groq、Gemini、MiniMax、Moonshot/Kimi、智谱、通义千问、vLLM 本地模型 |
| 多聊天平台 | Telegram、Discord、WhatsApp、飞书、Mochat、钉钉、Slack、Email、QQ |
| 定时任务 | 支持 cron 表达式和固定间隔的定时任务调度 |
| Docker 部署 | 提供 Dockerfile，支持容器化运行 |
| 工具系统 | 内置 shell 执行、文件读写编辑、子 Agent 派生等工具 |
| 持久记忆 | 支持长期记忆，不丢失重要上下文 |
| Skills 系统 | 内置 GitHub、天气、tmux 等技能，可扩展 |

## 三、架构设计

```
nanobot/
├── agent/          # 核心 Agent 逻辑
│   ├── loop.py     #   Agent 循环（LLM ↔ 工具执行）
│   ├── context.py  #   Prompt 构建器
│   ├── memory.py   #   持久记忆
│   ├── skills.py   #   Skills 加载器
│   ├── subagent.py #   后台任务执行
│   └── tools/      #   内置工具（含 spawn）
├── skills/         # 内置技能（github, weather, tmux...）
├── channels/       # 聊天渠道集成
├── bus/            # 消息路由
├── cron/           # 定时任务
├── heartbeat/      # 主动唤醒
├── providers/      # LLM 提供商（OpenRouter 等）
├── session/        # 会话管理
├── config/         # 配置管理
└── cli/            # 命令行接口
```

核心工作流：**用户输入 → Agent Loop（LLM 推理 → 工具调用 → 结果反馈）→ 输出回复**

Agent Loop 是核心，在 `loop.py` 中实现 LLM 与工具执行的循环交互。支持子 Agent（subagent）用于后台并行任务。

## 四、支持的 LLM 提供商

| 提供商 | 用途 | 备注 |
|--------|------|------|
| OpenRouter | LLM（推荐，可访问所有模型） | 全球用户推荐 |
| Anthropic | Claude 直连 | |
| OpenAI | GPT 直连 | |
| DeepSeek | DeepSeek 直连 | |
| Groq | LLM + 语音转写（Whisper） | 免费语音转写 |
| Gemini | Gemini 直连 | |
| MiniMax | MiniMax 直连 | 支持国内 API |
| AiHubMix | API 网关 | |
| 通义千问 | Qwen | 阿里云 |
| Moonshot/Kimi | Kimi 直连 | |
| 智谱 | GLM 直连 | 支持 coding plan |
| vLLM | 本地模型 | 支持任何 OpenAI 兼容服务器 |

添加新 Provider 只需 2 步：在 `registry.py` 添加 ProviderSpec + 在 `schema.py` 添加配置字段。

## 五、安装与使用

### 安装方式

```bash
# PyPI 安装（稳定版）
pip install nanobot-ai

# uv 安装（快速）
uv tool install nanobot-ai

# 源码安装（推荐开发用）
git clone https://github.com/HKUDS/nanobot.git
cd nanobot
pip install -e .
```

### 快速开始

```bash
# 1. 初始化
nanobot onboard

# 2. 编辑配置 ~/.nanobot/config.json，填入 API Key

# 3. 开始对话
nanobot agent -m "What is 2+2?"

# 交互模式
nanobot agent
```

### CLI 命令

| 命令 | 说明 |
|------|------|
| `nanobot onboard` | 初始化配置和工作区 |
| `nanobot agent -m "..."` | 单次对话 |
| `nanobot agent` | 交互式对话 |
| `nanobot gateway` | 启动网关（连接聊天平台） |
| `nanobot status` | 查看状态 |
| `nanobot cron add` | 添加定时任务 |
| `nanobot channels login` | 连接 WhatsApp |

## 六、应用场景示例

1. **24/7 实时市场分析** — 自动搜索、分析市场趋势
2. **全栈软件工程师** — 编写代码、部署、调试
3. **智能日程管理** — 定时提醒、自动化任务
4. **个人知识助手** — 记忆管理、信息检索

## 七、与 OpenClaw 对比

| 维度 | Nanobot | OpenClaw |
|------|---------|----------|
| 代码量 | ~4,000 行 | 430,000+ 行 |
| 安装复杂度 | pip install 一行搞定 | 较复杂 |
| 功能完整度 | 核心 Agent 能力 | 完整生态（700+ Skills） |
| 适合人群 | 学习研究、轻量使用、二次开发 | 生产级使用、需要丰富功能 |
| 可读性 | 极高，适合学习 Agent 架构 | 代码量大，学习门槛高 |
| 扩展性 | 添加 Provider/Channel 简单 | 生态更成熟 |
| 本地模型 | 支持 vLLM | 支持 |
| 聊天平台 | 9 个平台 | 更多 |

## 八、与本项目（AI-Bot）的关联分析

### 可借鉴之处

1. **Agent 架构设计** — Nanobot 的 Agent Loop（LLM ↔ 工具执行循环）是经典的 ReAct 模式，我们的服务端可以参考这个架构
2. **多 LLM 支持** — 通过 Provider Registry 统一管理不同 LLM，方便切换
3. **Skills 系统** — 可扩展的技能系统，类似 OpenClaw 的 Skills 但更轻量
4. **定时任务** — cron 模块可用于定时提醒等场景

### 差异点

- Nanobot 是纯软件方案（CLI + 聊天平台），我们的 AI-Bot 是硬件+软件结合
- Nanobot 没有语音交互（麦克风/扬声器），我们需要 ESP32-S3 + INMP441 + MAX98357A
- Nanobot 没有显示屏交互，我们有 ST7789 屏幕
- 我们的服务端可以考虑集成 Nanobot 作为 AI 对话引擎的轻量替代方案

### 潜在集成方案

我们的 AI-Bot 服务端架构可以参考 Nanobot 的设计：

```
ESP32-S3 (硬件端)
    ↓ WiFi
Python 服务端
    ├── 语音识别 (Whisper)
    ├── AI 对话引擎 ← 可用 Nanobot 的 Agent 模块
    ├── 语音合成 (Edge-TTS)
    └── 电脑控制 (OpenClaw Skills)
```

Nanobot 的 `agent/loop.py` 核心循环可以直接作为我们服务端的对话引擎，省去自己从零搭建 Agent 框架的工作。

## 九、总结

Nanobot 是一个设计精良的轻量级 AI Agent 框架，代码量小但五脏俱全。对于我们的 AI-Bot 项目：

- **学习价值高** — 适合理解 AI Agent 的核心架构（Agent Loop、工具调用、记忆、技能系统）
- **可作为服务端对话引擎** — 直接 `pip install nanobot-ai`，省去自建 Agent 框架
- **不能替代我们的硬件方案** — 语音采集/播放/显示屏等仍需 ESP32-S3 固件实现
