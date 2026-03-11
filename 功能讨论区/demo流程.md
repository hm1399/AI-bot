# AI-Bot 桌面AI助手 — Demo

一个基于 ESP32-S3 的桌面 AI 助手，用户对设备说话，经语音识别和 AI 处理后，回复显示在设备屏幕和 WhatsApp 上，并可通过语音控制电脑执行操作。硬件采用自主设计的 PCB（嘉立创EDA），集成麦克风、屏幕、触摸、电源管理等模块；软件采用三端架构——ESP32 固件负责采集与显示，Python 服务端负责 ASR/LLM/TTS 处理，Node.js Bridge 负责 WhatsApp 消息转发。

## 项目历程

| 日期 | 阶段 | 内容 |
| ---- | ---- | ---- |
| 2/4 | 项目启动 | 功能规划、技术调研（OpenClaw、NeoAI） |
| 2/5 | 元件选型 | ESP32-S3 N16R8 + INMP441 + MAX98357A + ST7789 + TP4056 + MPU6050 |
| 2/5~8 | 原理图设计 | 嘉立创EDA，7个模块（最小系统、麦克风、功放、屏幕、电源、陀螺仪、触摸） |
| 2/9 | PCB设计 | 布局布线，ERC/DRC通过 |
| 2/10~11 | 触摸子板 | 独立触摸感应板设计，取消TTP223改用ESP32-S3内置触摸 |
| 2/12 | 下单采购 | 嘉立创PCB打样 + 全部元件采购 |
| 2/25 | 架构设计 | 三端架构，Nanobot替代自建LLM引擎 |
| 3/4 | Nanobot部署 | 源码移植、Provider配置、CLI测试通过 |
| 3/7~8 | PCB焊接与测试 | 焊接完成，7/10项测试通过 |
| 3/8~9 | 后端搭建 | Phase 1-4：nanobot移植 + ASR + TTS + WebSocket + 语音全链路 |
| 3/10 | 屏幕与功放调试 | ST7789通过，发现IO8不可用（PSRAM占用） |
| 3/11 | Demo整合 | WhatsApp Channel集成 + ESP32 demo固件 + 联调 |

## 系统架构

```text
┌──────────────────┐
│  ESP32-S3 硬件    │
│  INMP441 麦克风   │──── WiFi/WebSocket ────┐
│  ST7789 屏幕     │                         │
│  触摸 IO7        │                         ▼
└──────────────────┘                ┌─────────────────┐
                                   │  Python 服务端    │
                                   │  ASR (Whisper)   │
                                   │  AgentLoop (LLM) │
                                   │  TTS (Edge-TTS)  │
                                   └────────┬────────┘
                                            │
                                   ┌────────▼────────┐
                                   │  WhatsApp Bridge │
                                   │  (Node.js)       │
                                   └────────┬────────┘
                                            │
                                   ┌────────▼────────┐
                                   │  WhatsApp 手机   │
                                   └─────────────────┘
```

## Demo 演示流程

### 开场（连接展示）

1. 打开 ESP32 电源
2. 屏幕显示：`Starting...` → `WiFi: Connected` → `Server: Connected`
3. WhatsApp 自动收到："你好！我是小博，你的桌面AI助手..."

### 语音交互演示

| 步骤 | 操作 | 预期效果 |
| ---- | ---- | ---- |
| 1 | 按住触摸板，说"帮我打开微信" | 屏幕显示 `Recording...` |
| 2 | 松开触摸板 | 屏幕显示 `Processing...` |
| 3 | 等待 AI 回复 | 屏幕显示回复 + WhatsApp 收到回复 + 微信被打开 |
| 4 | 按住说"打开 GitHub" | GitHub 网页被打开 |
| 5 | 按住说"今天天气怎么样" | 屏幕 + WhatsApp 显示天气信息 |

### 消息流

```text
用户说话 → ESP32 麦克风采集
    → WiFi 发送到电脑服务端
    → Whisper 语音识别
    → AI 处理（GLM-4）
    → WhatsApp 显示回复
    → ESP32 屏幕显示回复
    → 电脑执行命令（如有）
```

## 硬件清单

| 元件 | 型号 | 用途 |
| ---- | ---- | ---- |
| 主控 | ESP32-S3-WROOM-1-N16R8 | WiFi/蓝牙双核，16MB Flash + 8MB PSRAM |
| 麦克风 | INMP441 | I2S 24bit 数字语音采集 |
| 屏幕 | 1.69" ST7789 IPS | 状态/回复文字显示 |
| 功放 | MAX98357A | I2S D类功放（IO8不可用，demo未启用） |
| 充电IC | TP4056 | 锂电池1A充电管理 |
| 稳压 | AMS1117-3.3 | 3.3V LDO供电 |
| 陀螺仪 | MPU6050 | 摇一摇检测 |
| 触摸 | ESP32-S3内置 IO7 | 按住录音交互 |

## 软件技术栈

| 层 | 技术 |
| ---- | ---- |
| 固件 | Arduino (ESP32-S3) + TFT_eSPI + WebSockets + ArduinoJson |
| 服务端 | Python + aiohttp + Nanobot AgentLoop |
| 语音识别 | faster-whisper (medium模型) |
| 语音合成 | Edge-TTS |
| AI模型 | GLM-4 via OpenRouter |
| 消息渠道 | WhatsApp (Baileys bridge) |
| 电脑控制 | Nanobot exec 工具 |
