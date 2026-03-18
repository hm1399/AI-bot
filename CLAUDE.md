# AI-Bot 桌面AI助手 - 项目指南

## 项目概述

这是一个软硬件结合的桌面AI助手项目。硬件设备通过ESP32-S3连接麦克风、扬声器、显示屏等，通过WiFi与电脑服务端通信，服务端运行AI对话引擎和电脑控制模块。

## MVP目标

ESP32-S3 + INMP441麦克风 + MAX98357A功放 + 3W喇叭 + 1.69寸ST7789屏幕 + 电源管理(TP4056+AP2114H-3.3)

用户对设备说话 → 语音识别 → AI回复 → 语音播放，同时能通过语音控制电脑。

**已验证的核心链路：** 触摸录音 → ASR(faster-whisper) → AI(Claude API via Nanobot) → TTS(Edge-TTS) → 屏幕显示 + WhatsApp转发

## 硬件元件清单（原理图 v2.0）

### 主要IC与模块

| 编号 | 元件 | 型号 | 封装 | 接口 | 用途 |
|------|------|------|------|------|------|
| U1 | 主控 | ESP32-S3-WROOM-1-N16R8 | 模组 | - | WiFi/蓝牙双核主控 (16MB Flash + 8MB PSRAM) |
| U2 | 麦克风 | EV_INMP441 | 模组 | I2S | 24bit数字语音采集 |
| U3 | 功放 | MAX98357AETE+T | QFN-16 | I2S | D类音频功放，驱动扬声器 |
| U4 | 充电IC | TP4056 | SOP-8 | - | 锂电池充电管理（1A） |
| U5 | 稳压 | AP2114H-3.3（原AMS1117-3.3，待更换） | SOT-223 | - | 3.3V低压差LDO（电池→3.3V供电所有芯片） |
| U7 | 六轴传感器 | ZY-MPU-6050 | 邮票孔(2×4, 2.54mm) | I2C | 加速度计+陀螺仪，摇一摇检测 |

### 连接器

| 编号 | 元件 | 型号 | 用途 |
|------|------|------|------|
| J1 | 电池座 | B2B-PH-K-S(LF)(SN) (JST PH 2P) | 锂电池连接 |
| J2 | USB | KH-TYPE-C-16P-N (Type-C 16P母座) | 充电与USB调试 |
| J3 | 屏幕FPC座 | AFC01-S12FCA-00 (12P FPC) | 1.69寸ST7789 IPS LCD连接 |
| P1 | 喇叭座 | PZ254V-11-02P (2P) | 3W 4Ω扬声器连接 |
| H1 | 扩展排母 | 2.54mm 1×5P母 | 引出IO1, IO2, TXD0, RXD0, IO39 |
| H2 | 扩展排母 | 2.54mm 1×5P母 | 引出IO13, IO45, IO48, IO47, IO21 |
| H4 | 扩展排母 | 2.54mm 1×5P母 | 引出IO3, 3V3, 3V3, GND（触摸子板连接） |

### 无源元件

| 编号 | 元件 | 值 | 用途 |
|------|------|------|------|
| C1, C2 | 电容 | 10µF (0805) | ESP32-S3电源去耦 |
| C3 | 电容 | 100nF (0603) | ESP32-S3电源去耦 |
| C5 | 电容 | 100nF (0603) | INMP441 VDD去耦 |
| C7 | 电容 | 100nF (0603) | MAX98357A VBAT去耦 |
| C8 | 电容 | 100nF (0603) | ST7789背光/电源去耦 |
| C9, C10, C11 | 电容 | 各值 (0603/0805) | TP4056与AMS1117输入输出滤波 |
| C13 | 电容 | 100nF (0603) | MPU6050 VCC去耦 |
| R1, R2 | 电阻 | 5.1kΩ (0603) | USB Type-C CC1/CC2下拉（UFP识别） |
| R3, R4 | 电阻 | 限流 (0603) | 充电状态LED限流 |
| R6 | 电阻 | 4.7Ω (0603) | ST7789背光LED限流 |
| R12 | 电阻 | 100kΩ (0603) | INMP441 L/R声道选择下拉 |
| R_PROG | 电阻 | 1.2kΩ (0603) | TP4056充电电流设定（1A） |
| D1 | LED | 红色 (0603) | TP4056充电中指示 (CHRG) |
| D2 | LED | 绿色 (0603) | TP4056充满指示 (STDBY) |

### 开关

| 编号 | 元件 | 型号 | 用途 |
|------|------|------|------|
| SW1 | 拨动开关 | SK12D07VG4 | 电源总开关（电池→LDO） |
| - | 复位按键 | 轻触开关 | ESP32-S3 EN复位（带RC延时） |

### 其他外部器件

| 元件 | 型号/规格 | 用途 |
|------|-----------|------|
| 扬声器 | 3W 4Ω | 语音播放（接P1） |
| 显示屏 | 1.69" IPS TFT ST7789 | 时间/天气/状态显示（FPC接J3） |
| 锂电池 | 3.7V 1000-2000mAh | 便携供电（接J1） |
| LED灯带 | WS2812B | 氛围灯/状态指示（数据线IO38） |

### 触摸子板

| 编号 | 元件 | 值/型号 | 用途 |
|------|------|---------|------|
| R5 | 电阻 | 4.7kΩ | 触摸焊盘ESD保护 |
| TP1~TP4 | 测试点 | - | 信号引出：TOUCH_MAIN, GND, 3V3, LED_DIN |
| TP5~TP6 | 测试点 | - | 触摸铜皮焊盘连接 |
| - | 触摸铜皮 | PCB铜皮 (8~12mm) | 电容触摸感应区域 |

## 引脚分配 (ESP32-S3-WROOM-1-N16R8)

**重要：N16R8模组的GPIO22~32、GPIO33~37均不可用（被内部Octal SPI Flash/PSRAM占用）。**

### 音频 I2S

- INMP441 麦克风: SCK=IO14, WS=IO15, SD=IO16
- MAX98357A 功放: BCLK=IO17, LRC=IO18, DIN=IO8

### 显示 SPI

- ST7789 屏幕: SCK=IO12, MOSI=IO11, DC=IO10, CS=IO9, RST=IO46

### 触摸 (ESP32-S3内置电容触摸)

- 主触摸板: IO7 (TOUCH_MAIN) — 单击/双击/长按
- 备用触摸: IO1, IO2, IO3, IO13

### RGB灯带 (WS2812B)

- LED数据线: IO38 (LED_DIN) — WS2812B灯带（安装于外壳底部，氛围灯/状态指示）

### 特殊引脚

- USB: D-=IO19, D+=IO20 (硬件固定，不可更改)
- 启动模式: IO0 (保留，不做他用)
- 串口调试: TXD0, RXD0 (可选用于UART调试)

### 可用GPIO总表

IO0(启动), IO1, IO2, IO3, IO4, IO5, IO6, IO7, IO8,
IO9, IO10, IO11, IO12, IO13, IO14, IO15, IO16, IO17, IO18,
IO19(USB), IO20(USB), IO21,
IO38, IO39, IO40, IO41, IO42, IO45, IO46, IO47, IO48,
TXD0, RXD0

## 电源架构

```
USB Type-C 5V → TP4056 → 3.7V锂电池
                  (D1红LED充电中, D2绿LED充满)
                          ↓
                    SW1拨动开关(SK12D07VG4)
                          ↓
                    AP2114H-3.3 → 3.3V供电所有芯片
```

> **已知问题：** 原设计使用 AMS1117-3.3（dropout 1.1V），锂电池 4.2V 输入不足以稳定输出 3.3V（实测仅 2.9V），导致大功率场景（I2S 功放播放）触发 Brownout 重启。需更换为 AP2114H-3.3（dropout 0.25V，SOT-223 直接替换）。

## 软件技术栈

- 固件: Arduino (ESP32-S3)，使用 TFT_eSPI、arduinoWebSockets、ArduinoJson、ESP_I2S 等库
- 服务端: Python + aiohttp（基于 Nanobot 精简移植）
- AI引擎: Nanobot AgentLoop（LiteLLM Provider → Claude API）
- 语音识别(ASR): faster-whisper（本地部署，medium 模型）— 正在评估 SenseVoice 替代方案
- 语音合成(TTS): Edge-TTS（zh-CN-XiaoxiaoNeural），MP3→PCM 转换使用 miniaudio
- 电脑控制: Nanobot exec 工具（替代原 OpenClaw 方案）
- 消息通道: WhatsApp（通过 Node.js Bridge，支持 self-chat 模式）
- 手机App: Flutter（框架已搭建，Provider/Service 已实现）

## 目录结构

```
AI-bot/
├── README.md              # 项目简介与功能说明
├── CLAUDE.md              # 本文件 - Claude Code项目指南
├── CHANGELOG.md           # 工作日志（每次项目更新必须记录）
├── DEMO/                  # Demo 启动指南与文档
│   └── 启动指南.md
├── server/                # Python 服务端（核心）
│   ├── main.py            # 入口，启动 aiohttp + AgentLoop
│   ├── config.py          # 配置加载 + nanobot config 生成
│   ├── config.yaml        # 服务端配置文件
│   ├── requirements.txt   # Python 依赖
│   ├── nanobot/           # Nanobot 精简移植（AI 引擎核心）
│   │   ├── agent/         # AgentLoop、ContextBuilder、Memory、Skills、工具系统
│   │   ├── bus/           # 消息总线
│   │   ├── channels/      # 消息通道（WhatsApp 等）
│   │   ├── config/        # 配置加载
│   │   ├── cron/          # 定时任务
│   │   ├── providers/     # LiteLLM Provider
│   │   ├── session/       # 会话管理
│   │   └── utils/
│   ├── channels/          # 自定义通道
│   │   └── device_channel.py  # ESP32 WebSocket + 设备状态机
│   ├── services/          # ASR + TTS 服务
│   ├── models/            # 数据模型（protocol.py, device_state.py）
│   ├── tools/             # 测试客户端
│   ├── bridge/            # WhatsApp Bridge (Node.js)
│   │   └── src/           # TypeScript 源码
│   └── workspace/         # AI 工作空间
│       ├── SOUL.md        # AI 人格设定
│       └── skills/        # AI 技能定义
├── firmware/              # ESP32-S3 固件
│   └── arduino/           # Arduino 项目
│       ├── demo/          # Demo 固件（WiFi+WebSocket+麦克风+触摸+屏幕）
│       ├── test*/         # 各模块测试固件
│       └── test4_tts/     # TTS 语音播放测试
├── software/              # 手机 App
│   └── flutter_application_1/  # Flutter 项目
├── Project_proposal/      # EE3070课程项目提案
├── 元件资料区/             # 元件PDF数据手册
├── 元件TXT/               # 元件数据手册文本版
├── 功能讨论区/             # 功能设计与调研文档
│   ├── 架构.md            # 三端系统架构设计
│   ├── task.md            # MVP任务清单
│   ├── nanobot功能架构.md  # Nanobot 核心架构分析
│   ├── 后端搭建计划.md     # 后端 6 阶段计划
│   ├── 工作流程.md        # Demo 搭建步骤
│   ├── 待做.md            # 待优化项
│   ├── SenseVoice调研.md  # SenseVoice ASR 调研报告
│   └── ...
├── images/                # 原理图/PCB/焊接截图
├── 硬件设计文件/           # 嘉立创EDA导出文件
├── 原理图设计/             # 嘉立创EDA原理图设计教程（01~09）
└── nanobot-src/           # Nanobot 原始源码（仅供参考）
```

## 当前阶段

项目处于**软件开发与硬件完善阶段**。

**已完成：**
- 原理图v2.0 + PCB设计（ERC/DRC通过）+ 嘉立创打样 + 全部元件采购
- PCB焊接 + 硬件逐模块测试（8/10通过：串口、麦克风、屏幕、触摸、MPU6050、WiFi、电源、充电）
- 服务端 Phase 1~6 全部完成（Nanobot移植、ASR、TTS、WebSocket、语音全链路、状态机、连接管理、日志系统）
- Demo联调完成：触摸录音 → ASR → AI回复 → 屏幕显示 + WhatsApp转发
- WhatsApp self-chat 安全过滤 + Bridge 移植到 server/
- SenseVoice ASR 调研（推荐替换 faster-whisper，速度快5倍，中文更准）

**进行中：**
- Flutter 手机 App 开发（框架已搭建）
- Autodesk Fusion 3D外壳设计

**待完成：**
- AP2114H-3.3 LDO 焊接更换（解决 AMS1117 压差不足问题）→ 重新测试大音量播放
- WS2812B 灯带焊接 + LED灯效控制
- ESP32 固件完善（完整状态机、OTA更新等）
- ASR 升级（faster-whisper → SenseVoice）

## 注意事项

- 所有文档使用中文
- 用户是硬件设计新手，解释需通俗易懂
- 原理图设计使用嘉立创EDA专业版（免费在线工具）
- 元件优先选择嘉立创商城有货的型号，方便一站式采购和贴片
- 查看相关文件时优先用 grep/搜索定位关键内容，不要整个文件全部读取
- **每次项目有设计变更、新增模块、重要决策时，必须更新 `CHANGELOG.md` 工作日志**
