# AI-Bot - 桌面AI助手

一款软硬件结合的桌面AI助手，通过语音与用户交互，支持AI对话、电脑控制、智能待办等功能。

## 项目简介

硬件设备（ESP32-S3）通过WiFi连接电脑服务端，服务端运行AI对话引擎（基于Nanobot + Claude API）、语音识别（faster-whisper）和语音合成（Edge-TTS）。用户对设备说话，AI理解后回复语音并显示在屏幕上，同时支持通过WhatsApp和手机App交互。

## 系统架构

```
┌─────────────────┐     WiFi/WebSocket     ┌──────────────────────────┐
│   ESP32-S3 设备  │◄─────────────────────►│     Python 服务端         │
│                 │                        │                          │
│  INMP441 麦克风  │   PCM音频 / JSON消息   │  Nanobot AgentLoop (AI)  │
│  MAX98357A 功放  │                        │  faster-whisper (ASR)    │
│  ST7789 屏幕    │                        │  Edge-TTS (TTS)          │
│  触摸感应 IO7   │                        │  设备状态机               │
│  MPU6050 陀螺仪  │                        │  WhatsApp Bridge         │
│  WS2812B 灯带   │                        │                          │
└─────────────────┘                        └──────────────────────────┘
                                                      │
                                           ┌──────────┴──────────┐
                                           │   WhatsApp (self-chat)│
                                           │   Flutter App (开发中) │
                                           └─────────────────────┘
```

## 交互流程

```
用户说话 → INMP441采集 → PCM音频通过WebSocket发送
    → faster-whisper语音识别 → Nanobot AI处理（Claude API）
    → Edge-TTS语音合成 → PCM音频回传设备播放
    → 同时更新屏幕显示 + WhatsApp转发
```

## 硬件规格

| 模块 | 型号 | 用途 |
|------|------|------|
| 主控 | ESP32-S3-WROOM-1-N16R8 | WiFi/蓝牙双核主控 (16MB Flash + 8MB PSRAM) |
| 麦克风 | INMP441 (I2S) | 24bit数字语音采集 |
| 功放 | MAX98357A (I2S) | D类音频功放 |
| 喇叭 | 3W 4Ω | 语音播放 |
| 屏幕 | 1.69" IPS ST7789 (SPI) | 状态/文字显示 |
| 传感器 | MPU6050 (I2C) | 摇一摇检测 |
| 触摸 | ESP32-S3内置电容触摸 | 单击/双击/长按交互 |
| 灯带 | WS2812B | 氛围灯/状态指示 |
| 充电 | TP4056 | 锂电池充电管理 |
| 稳压 | AP2114H-3.3 | 3.3V LDO（低压差） |
| 电池 | 3.7V 锂电池 | 便携供电 |

## 软件技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| 固件 | Arduino (C++) | ESP32-S3固件，使用TFT_eSPI、arduinoWebSockets等 |
| AI引擎 | Nanobot AgentLoop | 精简移植，LiteLLM → Claude API |
| 语音识别 | faster-whisper (medium) | 本地部署，支持中英文 |
| 语音合成 | Edge-TTS | 微软在线TTS，zh-CN-XiaoxiaoNeural |
| 消息通道 | WhatsApp Bridge (Node.js) | self-chat模式，防止他人触发 |
| 手机App | Flutter | 开发中 |

## 核心功能

### 已实现
- 语音对话：对设备说话 → AI回复 → 语音播放 + 屏幕显示
- 触摸交互：单击录音/停止、双击取消、长按录音
- 摇一摇：触发AI讲笑话/冷知识
- WhatsApp转发：AI回复同步到WhatsApp self-chat
- 设备状态机：IDLE → LISTENING → PROCESSING → SPEAKING 自动流转
- 电脑控制：通过AI语音指令操控电脑（Nanobot exec工具）

### 规划中
- 电脑文件管理与应用控制
- 手机App远程控制
- 桌面摆件模式（时间/天气/日历显示）
- AI智能待办与日程管理
- AI人格系统（多种预设人格）
- 智能场景模式（专注/下班/会议）
- WS2812B灯效联动

## 项目进度

- [x] 功能规划与元件选型
- [x] 原理图v2.0 + PCB设计（ERC/DRC通过）
- [x] 嘉立创PCB打样 + 全部元件采购
- [x] PCB焊接 + 硬件测试（8/10模块通过）
- [x] 服务端开发 Phase 1~6 完成
- [x] Demo联调完成（语音全链路 + 屏幕 + WhatsApp）
- [ ] AP2114H-3.3 LDO更换（解决电源压差问题）
- [ ] WS2812B灯带焊接与灯效控制
- [ ] Flutter手机App开发
- [ ] 3D打印外壳（Autodesk Fusion）
- [ ] ASR升级评估（SenseVoice替代faster-whisper）

## 目录结构

```
AI-bot/
├── server/                # Python 服务端
│   ├── main.py            # 入口
│   ├── config.yaml        # 配置
│   ├── nanobot/           # AI 引擎（Nanobot 精简移植）
│   ├── channels/          # 设备 WebSocket 通道
│   ├── services/          # ASR + TTS 服务
│   ├── models/            # 数据模型与协议
│   ├── bridge/            # WhatsApp Bridge (Node.js)
│   └── workspace/         # AI 人格 + 技能
├── firmware/arduino/      # ESP32-S3 固件
│   ├── demo/              # Demo 固件
│   └── test*/             # 各模块测试固件
├── software/              # Flutter 手机 App
├── DEMO/                  # Demo 启动指南
├── 功能讨论区/             # 设计文档与调研
├── 原理图设计/             # 嘉立创EDA设计教程
├── 元件资料区/             # 元件数据手册
├── 硬件设计文件/           # EDA 导出文件
└── images/                # 截图与照片
```

## 快速开始

详见 [`DEMO/启动指南.md`](DEMO/启动指南.md)

**环境要求：** Python 3.11+、Node.js 20+

```bash
# 1. 安装 Python 依赖
cd server && pip install -r requirements.txt

# 2. 安装 WhatsApp Bridge 依赖
cd bridge && npm install && npm run build

# 3. 启动 Bridge（终端1）
cd server/bridge && node dist/index.js

# 4. 启动服务端（终端2）
cd server && python main.py
```

## 许可证

本项目为 EE3070 课程项目。
