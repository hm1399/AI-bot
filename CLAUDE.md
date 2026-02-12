# AI-Bot 桌面AI助手 - 项目指南

## 项目概述

这是一个软硬件结合的桌面AI助手项目。硬件设备通过ESP32-S3连接麦克风、扬声器、显示屏等，通过WiFi与电脑服务端通信，服务端运行AI对话引擎和电脑控制模块。

## MVP目标

ESP32-S3 + INMP441麦克风 + MAX98357A功放 + 3W喇叭 + 1.69寸ST7789屏幕 + 电源管理(TP4056+AMS1117)

用户对设备说话 → 语音识别 → AI回复 → 语音播放，同时能通过语音控制电脑。

## 硬件元件清单

| 元件 | 型号 | 接口 | 用途 |
|------|------|------|------|
| 主控 | ESP32-S3-WROOM-1-N16R8 | - | WiFi/蓝牙双核主控 (16MB Flash + 8MB PSRAM) |
| 麦克风 | INMP441 | I2S | 24bit数字语音采集 |
| 功放 | MAX98357A | I2S | D类音频功放 |
| 扬声器 | 3W 4Ω | - | 语音播放 |
| 显示屏 | 1.69" IPS TFT ST7789 | SPI | 时间/天气/状态显示 |
| 六轴传感器 | MPU6050 / QMI8658 | I2C | 摇一摇检测 |
| 触摸 | ESP32-S3内置电容触摸 + PCB铜皮焊盘 | Touch | 拍一拍交互（替代TTP223） |
| RGB灯珠 | WS2812B-MINI-V3/W × 6 (C527089) | GPIO(IO38) | 触摸子板环形氛围灯/呼吸灯 |
| 稳压 | AMS1117-3.3 | - | 5V→3.3V LDO |
| 充电 | TP4056 | - | 锂电池充电管理（红色LED充电中、绿色LED充满） |
| 电池 | 3.7V 1000-2000mAh | - | 锂电池供电 |
| USB | Type-C 16P母座 | - | 充电与调试 |

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

### RGB灯环 (WS2812B)

- LED数据线: IO38 (LED_DATA) — 触摸子板6颗WS2812B串联

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
                          ↓
                    AMS1117-3.3 → 3.3V供电所有芯片
```

## 软件技术栈

- 固件: Arduino/MicroPython (ESP32-S3)
- 服务端: Python + FastAPI
- 语音识别: Whisper
- 语音合成: Edge-TTS
- AI对话: GPT-4 / Claude API
- 电脑控制: OpenClaw (700+ Skills)
- 手机App: Flutter (远期)

## 目录结构

```
AI-bot/
├── README.md              # 项目简介与功能说明
├── CLAUDE.md              # 本文件 - Claude Code项目指南
├── CHANGELOG.md           # 工作日志（每次项目更新必须记录）
├── 元件资料区/             # 元件PDF数据手册
│   └── 元件.md            # 元件清单
├── 元件TXT/               # 元件数据手册文本版
├── 功能讨论区/             # 功能设计文档
│   ├── 功能实现讨论.md     # 各功能详细实现方案
│   ├── task.md            # MVP任务清单
│   ├── openClaw.md        # OpenClaw调研
│   ├── NeoAI.md           # NeoAI调研
│   └── output.md          # 其他输出
└── 原理图设计/             # 嘉立创EDA原理图设计教程
    ├── 01_ESP32-S3最小系统.md
    ├── 02_INMP441麦克风.md
    ├── 03_MAX98357A功放.md
    ├── 04_ST7789显示屏.md
    ├── 05_电源管理.md
    ├── 06_MPU6050陀螺仪.md
    ├── 07_触摸与交互.md
    └── 09_触摸子板PCB.md
```

## 当前阶段

项目处于**硬件设计阶段**，正在使用嘉立创EDA设计原理图和PCB。

## 注意事项

- 所有文档使用中文
- 用户是硬件设计新手，解释需通俗易懂
- 原理图设计使用嘉立创EDA专业版（免费在线工具）
- 元件优先选择嘉立创商城有货的型号，方便一站式采购和贴片
- 查看相关文件时优先用 grep/搜索定位关键内容，不要整个文件全部读取
- **每次项目有设计变更、新增模块、重要决策时，必须更新 `CHANGELOG.md` 工作日志**
