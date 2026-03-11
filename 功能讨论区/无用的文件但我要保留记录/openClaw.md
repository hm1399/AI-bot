# OpenClaw 项目调研

## 项目简介

OpenClaw 是一款开源的、本地部署的个人AI代理（AI Agent）框架。

**官网**: https://openclaw.ai/

**核心理念**: 将大语言模型的推理能力与本地操作系统的执行权限相结合，让AI能够像真人一样"动手做事"。

## 核心特点

1. **主动自动化** - 无需用户发出指令，可自主执行任务
2. **本地部署** - 数据完全可控，保护隐私
3. **700+ Skills** - 丰富的技能生态，可扩展
4. **多通道接入** - 支持WhatsApp、Telegram等即时通讯
5. **长期记忆** - 记住用户偏好和历史交互

## 系统架构

OpenClaw 包含五个核心模块：

| 模块 | 功能 |
| ---- | ---- |
| Gateway | 管理会话、路由请求、鉴权 |
| Agent Core | AI推理和决策引擎 |
| Skills | 可扩展的技能插件系统 |
| Memory | 长期记忆和上下文管理 |
| Channels | 多平台通讯接入 |

## Skills 技能分类

- **bundled** - 内置技能
- **managed** - 托管技能（700+可选）
- **workspace** - 工作区自定义技能

常用Skills包括：
- 文件管理（FileSystem Skills）
- 应用控制（Shell/Process Skills）
- 系统操作（System Skills）
- GitHub集成、邮件、日历等

## 安装方法

**系统要求**: 2GB RAM，支持Mac/Windows/Linux

```bash
# 方式1：一键安装脚本
curl -fsSL https://openclaw.ai/install.sh | bash

# 方式2：手动安装
git clone https://github.com/openclaw/openclaw.git
cd openclaw
pip install -r requirements.txt
openclaw start
```

**安装Skills**:
```bash
npx clawdhub@latest install <skill-name>
```

## 与我们项目的关系

根据功能讨论文档，我们计划**集成OpenClaw**来实现电脑控制功能：

| 功能 | OpenClaw Skill |
| ---- | -------------- |
| 文件操作 | FileSystem Skills |
| 打开/关闭应用 | Shell/Process Skills |
| 音量/亮度控制 | System Skills |
| 截图 | Screenshot Skills |

**集成方式**:
```python
from openclaw import ClawClient
claw = ClawClient(host="localhost", port=8080)
result = claw.execute("打开 Visual Studio Code")
```

---

调研日期: 2026-02-04

---

## NeoAI vs OpenClaw 对比

```
┌──────────┬────────────────────┬─────────────────────────┐
│ 对比维度 │       NeoAI        │        OpenClaw         │
├──────────┼────────────────────┼─────────────────────────┤
│ 定位     │ 轻量级电脑控制工具 │ 完整AI代理框架          │
├──────────┼────────────────────┼─────────────────────────┤
│ 技能数量 │ 内置基础功能       │ 700+ Skills可扩展       │
├──────────┼────────────────────┼─────────────────────────┤
│ 部署方式 │ 本地WebUI          │ 本地部署+多通道接入     │
├──────────┼────────────────────┼─────────────────────────┤
│ 交互方式 │ 网页界面           │ WhatsApp/Telegram/API等 │
├──────────┼────────────────────┼─────────────────────────┤
│ 主动性   │ 被动执行指令       │ 可主动自动化执行        │
├──────────┼────────────────────┼─────────────────────────┤
│ 生态     │ 单一项目           │ 丰富的插件生态          │
├──────────┼────────────────────┼─────────────────────────┤
│ 学习成本 │ 低，开箱即用       │ 中等，需配置Skills      │
└──────────┴────────────────────┴─────────────────────────┘
```

### 核心区别

**NeoAI**:
- 专注于"自然语言控制电脑"这一单一场景
- 简单直接，适合快速上手
- 功能相对固定，扩展性有限

**OpenClaw**:
- 是一个完整的AI Agent平台
- 模块化架构，Skills可按需安装
- 支持链式调用（Chain of Thought + Tool Use）
- 有长期记忆，能记住用户偏好
