# AI-Bot 桌面AI助手 - 工作日志

---

## 2026-02-04（Day 1）- 项目启动与功能规划

### 项目初始化

- 创建GitHub仓库，建立项目基础目录结构
- 编写README.md项目简介

### 功能讨论

- 确定产品定位：桌面AI助手，硬件设备通过WiFi与电脑服务端通信
- 讨论核心功能：语音对话、电脑控制、时间天气显示
- 编写`功能讨论区/功能实现讨论.md`，详细分析各功能实现方案

### 技术调研

- 调研OpenClaw（700+ Skills电脑控制框架），记录于`功能讨论区/openClaw.md`
- 调研NeoAI项目，记录于`功能讨论区/NeoAI.md`
- 确定软件技术栈：Python + FastAPI + Whisper + Edge-TTS + GPT-4/Claude API

---

## 2026-02-05（Day 2）- 元件选型与任务规划

### 元件选择

- 确定主控方案：ESP32-S3-WROOM-1-N16R8（16MB Flash + 8MB PSRAM）
- 确定音频方案：INMP441（I2S数字麦克风）+ MAX98357A（I2S D类功放）+ 3W 4Ω喇叭
- 确定显示方案：1.69寸 IPS TFT ST7789（SPI接口）
- 确定传感器：MPU6050六轴陀螺仪（I2C），用于摇一摇检测
- 确定电源方案：TP4056（锂电池充电）+ AMS1117-3.3（LDO稳压）
- 确定交互方案：TTP223触摸 + 轻触开关（后续被替换，见2月9日）

### 引脚分配

- 完成ESP32-S3全部引脚分配规划
- 明确N16R8模组限制：GPIO22~37被内部Octal SPI Flash/PSRAM占用，不可使用

### 任务规划

- 编写`功能讨论区/task.md` MVP任务清单
- 划分八大阶段：硬件采购 → 环境搭建 → 模块调试 → 硬件整合 → 原理图PCB → 固件开发 → 服务端开发 → 联调测试

### 元件资料收集

- 收集关键元件的PDF数据手册（TP4056、ST7789等）
- 建立`元件资料区/`和`元件TXT/`目录，归档数据手册

---

## 2026-02-05~08（Day 2~5）- 原理图设计（逐步完成）

### 原理图模块设计

在嘉立创EDA中逐步完成全部7个硬件模块的原理图，同步编写设计教程文档存放于`原理图设计/`目录：

**01_ESP32-S3最小系统**

- 设计ESP32-S3-WROOM-1-N16R8最小启动电路
- 包含：3V3供电去耦、EN复位按键（RC延时）、IO0下载模式按键、USB Type-C接口

**02_INMP441麦克风**

- I2S接口连接：SCK=IO14, WS=IO15, SD=IO16
- L/R引脚接GND选择左声道

**03_MAX98357A功放**

- I2S接口连接：BCLK=IO17, LRC=IO18, DIN=IO8
- GAIN引脚配置增益，SD引脚上拉使能

**04_ST7789显示屏**

- SPI接口连接：SCK=IO12, MOSI=IO11, DC=IO10, CS=IO9, RST=IO46
- 背光LED驱动电路

**05_电源管理**

- TP4056锂电池充电管理：PROG电阻1.2KΩ设定1A充电电流，TEMP接GND禁用温度检测
- AMS1117-3.3 LDO稳压：VBAT → 开关 → AMS1117 → 3V3
- USB Type-C 5V输入，锂电池3.7V中间储能

**06_MPU6050陀螺仪**

- I2C接口连接：SDA=IO5, SCL=IO6
- AD0接GND设定I2C地址0x68
- INT中断输出接IO4
- 采用邮票孔模块方案

**07_触摸与交互**

- 设计变更：取消TTP223外部触摸芯片 + 轻触开关方案
- 改用ESP32-S3内置14通道电容触摸传感器
- 主触摸板IO7（TOUCH_MAIN），备用IO1/IO2/IO3/IO13
- 每通道仅需1个4.7KΩ串联电阻做ESD保护
- 净减少5~7个元件

### 关键设计决策

- ESP32-S3内置触摸替代TTP223+按键，大幅简化BOM和PCB面积
- 触摸焊盘设计要点：8~12mm铜皮、走线<50mm、焊盘下方不铺地
- 支持Deep Sleep触摸唤醒，适合低功耗场景

---

## 2026-02-09（Day 6）- PCB布局布线

### PCB设计

- 完成PCB布局布线
- 所有模块原理图转PCB，元件摆放与走线完成

---

## 2026-02-10（Day 7）- 设计回退与确认

### 电源模块回退

- 恢复TP4056原始充电LED指示方案（红色LED充电中 + 绿色LED充满）
- 撤销GPIO充电检测方案（IO38/IO39不再用于充电状态读取）
- 删除变更文档 `原理图设计/08_电源LED改GPIO充电检测.md`
- IO38、IO39恢复为空闲可用引脚

### 触摸设计确认

- 确认单个大铜皮触摸焊盘方案：焊盘悬浮不接地，仅通过4.7K电阻连ESP32-S3
- GND保护环为可选项，单触摸板场景不需要

### 触摸子板设计

- 新增独立触摸子板PCB，放置在设备顶面
- 子板上有触摸铜皮焊盘 + 6颗WS2812B-MINI-V3/W RGB灯珠（C527089，环形排列）+ 6颗100nF去耦电容
- 通过杜邦线连接到主板：SIG（触摸信号）、DIN（LED数据IO38）、VCC（3.3V）、GND
- 主板侧新增排母连接器：H4（IO3/IO13/TOUCH_MAIN/3V3/GND）、H2（LED_DIN/IO45/IO48/IO47/IO21）、H1（IO1/IO2/TXD0/RXD0/IO39）
- 子板侧新增排母H3（SUB_SIG/SUB_DIN/SUB_3V3/SUB_GND/SUB_3V3），通过杜邦线与主板H4、H2对应引脚连接
- 4.7KΩ ESD电阻（R5）放置在子板侧（H3与触摸铜皮之间）
- 触摸铜皮网络从No Net改为SUB_SIG，与R5、H3.1同网络
- 子板使用独立网络命名（SUB_SIG/SUB_DIN/SUB_3V3/SUB_GND），避免自动布线跨板连接
- 子板与主板拼板打样（V-Cut或邮票孔分离），节省打样费用
- LED数据线分配IO38（支持RMT外设驱动WS2812B）
- 编写设计教程 `原理图设计/09_触摸子板PCB.md`

### 设计审查

- 原理图ERC检查通过
- PCB DRC检查通过

---

## 2026-02-11（Day 8）- 触摸子板原理图与布线完成

### 触摸子板（顶板）设计

- 完成触摸子板（顶板）原理图设计与PCB布局布线
- 顶板用于放置电容触摸感应板，实现"拍一拍"交互
- DRC检查通过

### 设计变更：灯珠方案调整

- 删除顶板上的6颗WS2812B-MINI可编程灯珠及去耦电容
- 改用LED灯带，连接在主板上，计划安装在成品外壳底部作为氛围灯
- 同时删除顶板排母连接器，触摸信号线直接焊接引出
- 顶板简化为纯触摸感应板（触摸铜皮 + ESD电阻）

---

## 2026-02-12（Day 9）- 下单采购与3D外壳设计启动

### PCB打样下单

- 在嘉立创完成主板与触摸子板的PCB下单

### 元件采购

- 完成全部元件采购

### 3D外壳设计

- 开始使用Autodesk Fusion设计3D打印外壳

---

## 2026-02-25 - 系统架构设计 + 任务清单更新

### 系统架构设计

- 新增 `功能讨论区/架构.md`，完整记录三端系统架构设计
- 架构决策：单体FastAPI后端、Flutter手机App、纯本地部署、局域网通信
- 电脑控制方案从 OpenClaw 改为 Nanobot（轻量~4000行代码）
- 设计 LLM + Tool Use 架构：提示词文件(.md) + 工具实现(.py)，4个工具（任务队列、日程安排、日历、电脑控制）
- 会话模型：硬件与App共享对话上下文
- 数据存储：本地SQLite（任务、日程、日历、对话历史）
- 定义 WebSocket 通信协议（设备端+App端消息类型）
- 定义 REST API 接口（配置、状态、历史）

### task.md 全面更新

- 七（服务端）从7小节扩展为8小节（7.1~7.8），对齐架构.md全部设计
- OpenClaw 改为 Nanobot（7.7节）
- 新增：两条WebSocket端点 + REST API（7.2）、SessionManager会话管理（7.3）、LLM + Tool Use 3工具系统（7.6）、SQLite数据库+WAL+对话压缩（7.8）、配置热加载（7.1）
- 新增八（App开发）完整章节：Flutter项目初始化、网络层、数据模型、Riverpod状态管理、5个页面、可复用组件
- 联调测试从5节扩展为7节（九），新增：LLM工具功能测试（9.3）、App功能测试（9.4）
- MVP验收标准从5条扩展为8条，新增：LLM工具系统、手机App、多端协同
- 元件采购清单：对齐CLAUDE.md原理图v2.0，补充具体型号（ESP32-S3-WROOM-1-N16R8、EV_INMP441、MAX98357AETE+T等）
- 补充遗漏模块：MPU6050六轴传感器、WS2812B灯带、触摸子板、电源开关SK12D07VG4、连接器型号
- 修正引脚分配表：旧版使用了N16R8不可用的GPIO22~32，已全部更正为原理图v2.0实际引脚
- 标记已完成阶段：硬件采购（一）、原理图与PCB设计（五）标记为✅
- 新增焊接质量检查章节（3.0）：上电前必做的短路检测步骤
- 新增硬件测试项：MPU6050（3.6）、触摸（3.7）、WS2812B（3.8）、触摸子板（3.9）
- 固件开发（六）大幅扩充：从4小节扩展为10小节，新增触摸交互、传感器、LED灯带、状态机、系统功能等
- 服务端开发（七）扩充：新增通信协议定义、流式处理、数据服务等
- 联调测试（八）扩充：新增端到端延迟指标、稳定性测试、外壳装配测试
- 修正章节编号错误（旧版六章内部标号为5.x，七章为6.x）

---

## 2026-03-04 - Nanobot 安装部署与测试

### Nanobot 安装与部署

- 将 nanobot 源码克隆到本地（`nanobot-src/`目录）
- 安装 nanobot 并完成初始化配置（`nanobot onboard`）
- 配置 LLM Provider 和 API Key
- 成功启动 nanobot 并通过 CLI 模式（`nanobot agent`）完成对话测试

### 技术调研与文档整理

- 阅读 nanobot 源码（`nanobot-src/nanobot/`），梳理核心架构
- 生成 `功能讨论区/nanobot功能架构.md`，详细记录：
  - 整体数据流架构（Channel → MessageBus → AgentLoop → Tools）
  - 8 个核心模块（AgentLoop、MemoryStore、CronService、HeartbeatService 等）
  - 11 个内置工具（文件读写、Shell、Web 搜索、子 Agent、定时任务等）
  - 8 个内置技能（memory、cron、weather、tmux、github 等）
  - 11 个消息通道（Telegram、Discord、WhatsApp、飞书、钉钉、Slack 等）的配置方式
  - 17 个 LLM Provider 对照表

---

## 2026-03-05 - Nanobot 移植后端计划（更新版）

### 架构决策：nanobot 作为 AI 核心引擎，task.md 服务端大幅简化

- nanobot AgentLoop 替代自建 LLM + Tool Use 引擎
- nanobot 内置 exec 工具替代 subprocess 调用 nanobot 的原计划
- nanobot MEMORY.md 替代自建 SQLite 对话历史/摘要系统
- task.md 7.2/7.3/7.6/7.7/7.8（对话部分）全部由 nanobot 承担

### task.md 保留部分

- 7.4 ASR：`server/services/asr.py`（faster-whisper 本地部署）
- 7.5 TTS：`server/services/tts.py`（Edge-TTS）
- 7.8 SQLite：仅保留 tasks + events 两张表（自定义 nanobot 工具读写）

### 新 server/ 结构

- `channels/device_channel.py`：ESP32 WebSocket + ASR + TTS（替代 /ws/device）
- `channels/app_channel.py`：Flutter WebSocket（替代 /ws/app）
- `main.py`：直接构建 nanobot 核心，注入自定义 Channel
- `tools/task_queue_tool.py` + `tools/events_tool.py`：自定义 nanobot 工具
- 八个阶段完整计划保存在 `功能讨论区/移植修改nanobot.md`

---

## 2026-03-07~08 - PCB焊接与硬件测试

### 3月7日：PCB焊接

- 完成主板大部分元件焊接
- 发现两个采购错误：
  - **ST7789 屏幕 FPC 接口**：买成上下接反的型号，无法插入排线，需重新采购
  - **INMP441 麦克风封装**：买错封装，与PCB焊盘不匹配，重新采购正确封装后焊接成功

### 3月8日：硬件逐模块测试

- 编写硬件测试计划（`功能讨论区/硬件测试.md`），共10项测试
- 测试代码存放于 `firmware/arduino/` 目录

**已通过（7/10）：**

- ✅ 测试1：串口通信 — USB CDC 正常，回显和心跳包正常
- ✅ 测试3：INMP441 麦克风 — I2S 采集正常，音量条显示正确
- ✅ 测试6：触摸感应 — ESP32-S3 内置电容触摸，单击/双击/长按识别正常
- ✅ 测试7：MPU6050 六轴传感器 — I2C 通信正常，加速度/陀螺仪/温度数据正确，摇一摇/敲击/翻转/倾斜/旋转检测正常
- ✅ 测试9：WiFi 连接 — 热点扫描、WiFi连接、HTTP请求均正常
- ✅ 测试10：电源与充电 — TP4056 充电指示灯正常，AMS1117 3.3V 稳压正常，电池独立供电正常

**待测（3/10）：**

- 🔄 测试2：ST7789 屏幕 — FPC接口买错（上下接反），待重新采购 → **3月10日已通过**
- ⬜ 测试4/5：MAX98357A 功放与喇叭 — 喇叭未焊接 → **3月10日发现IO8不可用，待飞线IO21**
- ⬜ 测试8：WS2812B 灯带 — 灯带未焊接

### TFT_eSPI 库配置记录

- 驱动：ST7789_DRIVER
- 分辨率：240x240（1.54寸屏）
- 引脚：MOSI=IO11, SCK=IO12, CS=IO9, DC=IO10, RST=IO46
- SPI频率：40MHz，使用 HSPI 端口
- 启用 TFT_INVERSION_ON

---

## 2026-03-10 - ST7789屏幕调试 + MAX98357A功放测试 + TTS语音合成

### ST7789 屏幕调试

- FPC接口重新采购后焊接完成，屏幕背光点亮
- 编写测试程序 `firmware/arduino/test2/test2.ino`，使用 TFT_eSPI 库
- 串口输出正常、TFT_eSPI 配置验证正确（ST7789_DRIVER, 240x240, HSPI, 40MHz）
- 将屏幕 PDF 数据手册转换为文本版 `元件TXT/ST7789P3_屏幕.txt`
- 确认 ST7789P3 控制器与 ST7789V 命令兼容，TFT_eSPI 的 ST7789_DRIVER 可直接使用
- **最终发现屏幕无显示是焊接问题**，重新焊接后屏幕测试通过
- ✅ 测试2 通过

### MAX98357A 功放与喇叭测试

- 焊接喇叭（FUET2828 4Ω 2W 腔体喇叭）
- 编写测试程序 `firmware/arduino/test4/test4.ino`，使用 ESP_I2S 库
- 测试内容：440Hz正弦波、C4~C6音阶、音量渐变、小星星旋律
- 添加15ms淡入淡出包络消除爆音

### SAM TTS 语音合成测试

- 安装 ESP8266SAM_ES 库（西班牙语 SAM TTS）
- 编写测试程序 `firmware/arduino/test4_tts/test4_tts.ino`
- 解决 ESP8266SAM_ES 与 ESP8266Audio 库的 `AudioOutput` 类名冲突（同一头文件保护宏 `_AUDIOOUTPUT_H`）
- 方案：自定义 `I2SOutput` 类直接继承 SAM_ES 的 AudioOutput，绕过 ESP8266Audio
- 使用 IDF5 新版 I2S API（`driver/i2s_std.h`），添加音量变量控制
- 添加 `SET_LOOP_TASK_STACK_SIZE(16 * 1024)` 解决 SAM 栈溢出

### I2S 音频问题排查

- **问题1 - 声音乱码**：使用单声道格式 + 单样本写入导致 I2S 帧对齐错误。修复：改用立体声帧格式（`int16_t frame[2]`）写入
- **问题2 - USB CDC 串口断开**：I2S 初始化时 `i2s_channel_init_std_mode()` 导致系统崩溃/挂死
- 排查过程：尝试 Legacy API、IDF5 API、ESP_I2S 封装、不同 I2S 端口号、gpio_reset_pin — 均崩溃
- 编写最小化调试程序 `firmware/arduino/test4_debug/test4_debug.ino` 定位问题

### 关键发现：IO8 不可用于 I2S

- ~~查阅 ESP32-S3 数据手册，发现 IO8 的 IO MUX 功能为 SUBSPICS1（SPI1 CS1，用于 PSRAM）~~ ← 3月17日已更正，见下方
- ~~N16R8 模组使用 Octal SPI PSRAM，虽然文档仅标注 GPIO26~37 为受限引脚，但 IO8 实际被 SPI 子系统锁定~~
- ~~GPIO Matrix 无法覆盖已被 IO MUX 占用的引脚，因此软件层面无法修复~~
- **结论：IO8 在 ESP32-S3 上不可用于 I2S DIN，需要飞线到其他 GPIO**（根因已在3月17日更正）
- 建议飞线目标：IO21（完全空闲，已通过 test4_debug 验证可用）
- ⚠️ 测试4/5 待飞线后重新测试

---

## 2026-03-09 - 后端搭建（Phase 1~4 完成）

### Phase 1: 项目骨架 + nanobot 精简移植

- 创建 `server/` 目录结构（main.py, config.py, config.yaml, requirements.txt）
- 从 `nanobot-src/nanobot/` 精简复制核心模块到 `server/nanobot/`：
  - `agent/`（AgentLoop、ContextBuilder、Memory、Skills、工具系统）
  - `bus/`（消息总线）、`providers/`（LiteLLM Provider）、`session/`（会话管理）、`config/`（配置加载）、`cron/`（定时任务）
- 删除不需要的模块：Telegram/Discord/Slack 等 10 个 Channel、CLI、Heartbeat、Templates
- 保留 WhatsApp Channel 作为消息渠道，新增 Channel Manager
- 全局修复 import 路径，验证核心模块加载无报错
- 创建 `server/workspace/SOUL.md` AI 人格设定
- `/api/health` 端点正常响应，AgentLoop 成功调用 Claude API

### Phase 2: ASR + TTS 服务

- 实现 `server/services/asr.py`（ASRService）：
  - 基于 faster-whisper，加载 base 模型
  - PCM 16kHz 16bit 单声道 → WAV 转换 → Whisper 识别
  - 使用 `asyncio.to_thread()` 避免阻塞事件循环
- 实现 `server/services/tts.py`（TTSService）：
  - 基于 Edge-TTS，默认语音 `zh-CN-XiaoxiaoNeural`
  - MP3 → PCM 16kHz 16bit 转换（使用 miniaudio，无需 ffmpeg）
  - 实现流式合成 `synthesize_stream()`，边合成边产出音频块
- 统一音频格式约定：ESP32 ↔ 服务端统一 PCM 16kHz 16bit 单声道

### Phase 3: DeviceChannel WebSocket

- 实现 `server/channels/device_channel.py`：
  - 继承 nanobot BaseChannel，注册 `/ws/device` WebSocket 路由
  - JSON 文本帧按 type 分发，二进制帧累积到音频 buffer
  - 连接状态管理（在线/离线）
- 定义 WebSocket 消息协议 `server/models/protocol.py`：
  - 设备→服务端：audio_end, touch_event, shake_event, device_status, text_input
  - 服务端→设备：state_change, display_update, led_control, audio_play, audio_play_end, text_reply
- 编写 WebSocket 测试客户端 `server/tools/test_client.py`
- 验证：文字消息成功走完 DeviceChannel → MessageBus → AgentLoop → Claude API → 回复

### Phase 4: 语音交互全链路串联

- 音频接收 + ASR 集成：二进制帧累积 → audio_end 触发识别 → 文本送入 AgentLoop
- TTS 集成 + 流式音频发送：AI 回复 → TTS 合成 → 流式发送 PCM 到设备
- 完整语音链路：说话 → ASR → AI处理 → TTS → 播放
- 各环节耗时日志记录
- ✅ 核心里程碑达成：端到端语音交互可用

### 待完成

- Phase 5：屏幕/LED 控制 + 设备状态机
- Phase 6：稳定性、错误处理、日志、配置完善

---

## 2026-03-11 - Demo 准备（WhatsApp Channel + ESP32 固件）

### Demo 方案

- 因 MAX98357A 功放 IO8 不可用无法发声，采用 WhatsApp 渠道展示 AI 对话
- 演示流程：用户对硬件说话 → ASR识别 → AI回复 → WhatsApp显示回复 + ESP32屏幕显示

### 服务端修改

- `server/config.yaml`：添加 whatsapp 配置段（enabled, bridge_url, bridge_token, allow_from）
- `server/config.py`：`generate_nanobot_config()` 添加 channels.whatsapp 到 config.json
- `server/main.py`：
  - 集成 WhatsApp Channel（直接初始化 WhatsAppChannel，不使用 ChannelManager 避免复杂度）
  - 新增 `unified_outbound_consumer()` 替代 DeviceChannel 单独的 outbound 消费者
  - 解决 MessageBus 单队列竞争问题：统一消费者同时路由到设备屏幕和 WhatsApp
  - 设备 channel 的回复自动转发到 WhatsApp（demo 模式，发给最近联系人）

### ESP32 Demo 固件

- 新建 `firmware/arduino/demo/demo.ino`，整合：
  - WiFi 连接（SSID: EE3070_P1615_1）
  - WebSocket 客户端连接服务端
  - INMP441 麦克风 I2S 采集（16kHz 16bit 单声道）
  - 触摸 IO7（按住录音，松开发送 audio_end）
  - ST7789 屏幕显示（连接状态 + AI 回复文字）
  - 连接成功后发送 text_input 触发 AI 自我介绍
- 依赖库：TFT_eSPI, arduinoWebSockets, ArduinoJson

### 工作流程文档

- 更新 `功能讨论区/工作流程.md`，记录完整 demo 搭建步骤和消息流

---

## 2026-03-11（续）- Demo 联调完成 + Flutter App 开发启动 + 文档整理

### Demo 联调

- ESP32 demo 固件烧录并成功连接服务端 WebSocket
- 语音全链路调通：触摸录音 → ASR 识别 → AI 回复 → 屏幕显示 + WhatsApp 转发
- ASR 模型升级：base → small → medium（1.5GB），解决英文识别准确率过低问题
- ASR 语言设置从 `zh` 改为自动检测（`language: ""`），支持中英文混合识别
- 修复 faster-whisper 空字符串 language 导致 ValueError 的 bug（`asr.py`）
- WhatsApp 转发调通：需要外部用户先发消息给 bridge 绑定的 WhatsApp 号码才能激活转发

### Flutter 手机 App 开发启动

- 在 `software/flutter_application_1/` 中搭建 Flutter 项目框架
- 实现数据模型：`models/message.dart`（消息模型）、`models/device_status.dart`（设备状态模型）
- 实现 Provider 状态管理：`chat_provider.dart`、`config_provider.dart`、`device_provider.dart`、`event_provider.dart`、`task_provider.dart`
- 实现服务层：`api_service.dart`（REST API）、`ws_service.dart`（WebSocket 通信）、`discovery_service.dart`（局域网服务发现）
- 在 `AI-Bot Mobile App (Flutter)/` 目录添加项目文档和配置参考

### 文档整理

- 新建 `功能讨论区/demo流程.md`：项目介绍、完整项目历程、系统架构图、Demo 演示流程、硬件清单、软件技术栈
- 重写 `功能讨论区/工作流程.md`：11步 demo 搭建指南（从查 IP 到语音交互），含常见问题排查
- 新建 `功能讨论区/待做.md`：记录已知待优化项（WhatsApp 信任 ID 过滤、nanobot 功能扩展、屏幕/喇叭、ASR 准确率、响应速度）

---

## 当前状态

**阶段：** Demo 已完成，Flutter App 开发中

**已完成：**

- [x] 项目规划与功能定义
- [x] 全部元件选型与引脚分配
- [x] 7个模块原理图设计 + PCB 布局布线（ERC/DRC通过）
- [x] 触摸子板设计（DRC通过）
- [x] 嘉立创PCB下单 + 元件采购
- [x] PCB焊接 + 硬件测试（8/10通过）
- [x] 后端搭建 Phase 1~4（nanobot移植、ASR、TTS、WebSocket、语音全链路）
- [x] WhatsApp Channel 集成 + ESP32 demo 固件
- [x] Demo 联调完成（语音交互 + 屏幕显示 + WhatsApp 转发）
- [x] Demo 文档（demo流程.md、工作流程.md）

**进行中：**

- [ ] Flutter 手机 App 开发（框架已搭建，Provider/Service 已实现）
- [ ] Autodesk Fusion 3D外壳设计（3D打印）

**待完成：**

- [ ] AMS1117→AP2114H-3.3 更换 + 功放/喇叭/灯带重新测试
- [ ] WhatsApp 信任 ID 过滤（当前任何人发消息都能触发 AI）
- [ ] nanobot 功能扩展（日历、摇一摇等）
- [ ] 屏幕和喇叭功能完善
- [ ] ASR 准确率优化 + 响应速度优化
- [ ] 后端 Phase 5~6（屏幕/LED控制、状态机、稳定性完善）

---

## 引脚分配总览

| 引脚 | 功能 | 模块 |
|------|------|------|
| IO1 | TOUCH_UP（备用触摸） | 触摸交互 |
| IO2 | TOUCH_DOWN（备用触摸） | 触摸交互 |
| IO3 | 备用触摸 | 触摸交互 |
| IO4 | MPU6050中断 | 陀螺仪 |
| IO5 | I2C_SDA | 陀螺仪 |
| IO6 | I2C_SCL | 陀螺仪 |
| IO7 | TOUCH_MAIN（主触摸） | 触摸交互 |
| IO8 | I2S_DOUT（功放DIN） | MAX98357A（原理图正确，之前崩溃是电源问题） |
| IO9 | SPI_CS | ST7789 |
| IO10 | SPI_DC | ST7789 |
| IO11 | SPI_MOSI | ST7789 |
| IO12 | SPI_SCK | ST7789 |
| IO13 | 备用触摸 | 触摸交互 |
| IO14 | I2S_SCK（麦克风） | INMP441 |
| IO15 | I2S_WS（麦克风） | INMP441 |
| IO16 | I2S_SD（麦克风） | INMP441 |
| IO17 | I2S_BCLK（功放） | MAX98357A |
| IO18 | I2S_LRC（功放） | MAX98357A |
| IO19 | USB D- | USB（固定） |
| IO20 | USB D+ | USB（固定） |
| IO38 | LED_DIN | WS2812B |
| IO46 | SPI_RST | ST7789 |

---

## 2026-03-08 - 后端搭建计划制定

### 后端搭建计划

- 基于 `功能讨论区/架构.md` 制定了详细的后端搭建计划，写入 `功能讨论区/后端搭建计划.md`
- 计划分为 6 个阶段，每阶段配有 Checkpoint 验收标准：
  1. **Phase 1** — 项目骨架 + nanobot 精简移植（复制核心模块，删除不需要的 Channel/CLI/Heartbeat）
  2. **Phase 2** — ASR（faster-whisper）+ TTS（Edge-TTS）服务实现
  3. **Phase 3** — DeviceChannel WebSocket 端点（`/ws/device`）+ 测试客户端
  4. **Phase 4** ⭐ — 语音交互全链路串联（音频→ASR→AgentLoop→TTS→音频回传）
  5. **Phase 5** — 屏幕/LED 控制 + 设备状态机同步
  6. **Phase 6** — 稳定性、错误处理、日志、配置完善
- 明确了从 `nanobot-src/` 复制哪些模块、删除哪些模块、新写哪些文件

---

## 2026-03-17 - IO8 问题根因更正 & 喇叭调试

### IO8 根因更正（推翻3月10日结论）

3月10日的结论认为 IO8 崩溃是因为 SUBSPICS1（SPI1 CS1，PSRAM 占用），**经系统排查证实该结论有误**。

排查过程：

1. **Disable PSRAM 测试**：Arduino IDE 中将 PSRAM 设为 Disabled，运行 `test4_tts`，IO8 仍然在 `i2s_channel_init_std_mode()` 崩溃 → 排除 PSRAM
2. **QSPI PSRAM 测试**：改用 Quad SPI PSRAM 模式，仍然崩溃 → 排除 Octal SPI 特有问题
3. **逐步诊断**（`test10_i2s_debug`）：将 I2S 初始化拆为 5 步，确认崩溃精确发生在 `i2s_channel_init_std_mode()` 调用时
4. **对比测试**（`test11_io8_diag`）：
   - TEST_MODE 2: IO8 做 I2S DIN → 崩溃
   - TEST_MODE 3: IO21 做 I2S DIN → 正常，串口稳定
5. **尝试软件绕过**（`test11_io8_diag` TEST_MODE 5）：
   - `gpio_reset_pin(GPIO_NUM_8)` 重置 IO8 → 仍崩溃
   - 将 SUBSPICS1 信号通过 GPIO Matrix 重定向到 IO39 → 仍崩溃
   - → 排除 SUBSPICS1 是根因

### ~~真正的根因：IO8 被 SPI Flash 保留~~ ← 3月17日再次更正，见下方

- ~~ESP32-S3 的 SPI Flash 在 QIO 模式下占用 GPIO 6, 7, 8, 9, 10, 11~~
- ~~GPIO8 在所有 Flash 模式下都被 SPI Flash 接口占用，无法释放~~
- ~~这是硬件级限制，软件无法绕过~~

### 最终结论（3月17日更正）：IO8 可用，根因是电源问题

- **IO8 崩溃的真正原因是 AMS1117 电源输出不足（仅2.9V），不是 IO8 引脚限制**
- AMS1117 压差 1.1V，锂电池 4.2V 输入不够，导致 3.3V 输出仅 2.9V
- ESP32-S3 在 I2S 初始化时电流尖峰使电压进一步跌落，触发 Brownout 重启
- IO21 测试通过是因为恰好当时电源状态较好，并非 IO8 本身有问题
- **IO8 原理图设计无误，无需飞线，无需改版**
- 待更换 AP2114H-3.3 LDO 后重新验证 IO8 I2S 功能
- 新增调试固件：`firmware/arduino/test10_i2s_debug/`、`firmware/arduino/test11_io8_diag/`

### 喇叭飞线IO21后TTS测试

- 飞线 IO8 → IO21 完成，MAX98357A I2S 通信正常
- 使用 `firmware/arduino/test4_tts/test4_tts.ino`（ESP32-audioI2S 库 + Google TTS）进行语音播放测试
- **低音量（VOLUME=5）可正常播放**，确认 I2S 链路和功放芯片工作正常

### 发现电源问题：AMS1117 压差不足导致系统崩溃

- **现象**：音量调高（VOLUME≥10）时 ESP32-S3 触发 Brownout Detector 重启，VOLUME=3 也崩溃
- **排查过程**：
  1. 尝试软件关闭欠压检测（`RTCCNTL.brown_out.ena = 0`）→ 无效，芯片在代码执行前就已重启
  2. 示波器测量 AMS1117 输出：空载时仅 **2.9V**（应为 3.3V）
- **根因**：AMS1117 是高压差 LDO（dropout 1.1V），需要输入至少 4.4V 才能稳定输出 3.3V。锂电池满电仅 4.2V，输入电压不足，导致输出仅约 2.9V，ESP32-S3 供电不稳
- **解决方案**：将 AMS1117 更换为 **AP2114H-3.3**（低压差 LDO，dropout 0.25V，最大 1A，SOT-223 封装可直接替换）
  - 锂电池 3.5V 时仍可稳定输出 3.3V
  - 发热量大幅降低：(3.7-3.3)×0.5 = 0.2W vs AMS1117 无法稳压

### WS2812B 灯带

- 灯带待下周焊接后再测试

---

## 2026-03-18 - Phase 5 后端状态机 + 事件处理

### 5.1 设备状态机（服务端侧）

- 新建 `server/models/device_state.py`：
  - `DeviceState` 枚举：IDLE / LISTENING / PROCESSING / SPEAKING / ERROR
  - `VALID_TRANSITIONS` 状态转换表，防止非法跳转
  - `STATE_DISPLAY_HINTS` 各状态对应屏幕提示文字
- `DeviceChannel` 集成状态机：
  - `_set_state()` 方法：校验转换合法性 → 通知设备 `state_change` → 自动发送屏幕提示
  - 收到第一帧音频自动切换 `IDLE → LISTENING`
  - `audio_end` 触发 `LISTENING → PROCESSING → SPEAKING → IDLE` 全流程
  - 异常时 `→ ERROR → IDLE` 自动恢复

### 5.2 LED 灯效控制 — 暂不实现

- LED 灯效控制暂缓，等硬件（AP2114H 电源更换 + WS2812B 灯带焊接）完成后再做

### 5.3 屏幕显示控制

- `_send_display_update()` 方法：
  - 支持长文本自动截断（DISPLAY_MAX_CHARS = 120 字符，约10字×12行适配 240×280 屏幕）
  - AI 回复文字通过 `display_update` 发送给设备
  - 状态切换时自动显示提示（如 "🎤 聆听中..."、"🤔 思考中..."）
  - ASR 失败时显示 "语音识别失败，请重试" / "没听清，请再说一次"

### 5.4 设备事件处理

- **触摸事件** (`touch_event`):
  - `single` — 单击切换录音开始/结束；播放中单击打断
  - `double` — 双击取消当前操作，回到 IDLE
  - `long_press` — 长按开始录音
  - `long_release` — 长按松开结束录音
- **摇一摇事件** (`shake_event`):
  - 空闲时摇一摇 → 向 AI 发送 "讲一个有趣的笑话或者冷知识"
  - 非空闲状态忽略
- **设备状态上报** (`device_status`):
  - 记录电量、WiFi 信号强度、充电状态到 `device_info` 字典
  - 新增 `/api/device` 端点查询设备信息（连接状态 + 电量 + WiFi + 当前状态）

### 测试客户端更新

- `test_client.py` 新增命令：
  - `touch <动作>` — 模拟触摸事件 (single/double/long_press/long_release)
  - `shake` — 模拟摇一摇
  - `status <电量> <WiFi>` — 上报设备状态（如 `status 85 -55`）
  - `state` — 查看当前设备状态

---

## 2026-03-18 - Phase 6 稳定性 + 配置完善

### 6.1 连接管理

- WebSocket 心跳保活: aiohttp 内置 `heartbeat=30s` 自动 ping/pong
- 独立心跳任务 `_heartbeat_loop()` 作为备用检测
- 断线检测: `_handle_ws` finally 块清理状态 + 记录在线时长
- 重连计数: `_reconnect_count` 追踪设备重连次数
- 重连后自动恢复到 IDLE 状态（会话通过 SessionManager 保持）
- 优雅关闭: 注册 SIGINT/SIGTERM 信号处理 → 按顺序关闭 WebSocket → outbound → agent → HTTP

### 6.2 错误处理

- ASR 识别失败 → 屏幕显示 "语音识别失败，请重试"（Phase 5 已实现）
- LLM API 调用失败 → AgentLoop 内部处理: 不持久化错误响应防止死循环，返回友好提示
- TTS 合成失败 → 降级为纯文字回复 `send_text_reply()`
- WebSocket 消息格式错误 → `json.JSONDecodeError` 忽略并记录日志（Phase 3 已实现）
- 音频 buffer 溢出保护: 超过 `MAX_AUDIO_BYTES`（30s = 960KB）自动截断并触发处理

### 6.3 日志系统

- `setup_logging()`: loguru 双输出
  - 控制台: INFO 级别，`HH:mm:ss | LEVEL | module:func - message`
  - 文件: DEBUG 级别，写入 `server/logs/server_YYYY-MM-DD.log`，按天轮转保留 7 天
- 各环节耗时日志统一格式: `[ASR 0.8s]`, `[TTS 1.2s]`

### 6.4 配置完善

- `validate_config()`: 启动时检查 API Key、SOUL.md 存在性、端口范围
- `/api/health` 增强: 返回版本号、模型、provider、ASR/TTS 配置、设备在线状态、运行时长
- `/api/device` 增加 `reconnect_count` 字段
- 启动日志打印完整配置摘要（模型、ASR、TTS、端口）

### 6.5 SOUL.md + Skills

- SOUL.md 已在 Phase 3 创建，ContextBuilder 自动加载（`BOOTSTRAP_FILES` 包含 "SOUL.md"）
- 新建 `workspace/skills/computer-control/SKILL.md`:
  - 定义电脑控制能力: 打开应用、文件操作、系统信息、进程管理
  - 安全规则: 危险命令需确认、禁止 rm -rf / shutdown 等
  - 标记 `always: true`，SkillsLoader 自动加载到上下文
- 版本号: v0.6.0

---

## 2026-03-18（续）- WhatsApp Self-Chat 支持 + Bridge 移植 + Demo 文档

### WhatsApp Self-Chat 功能

之前 WhatsApp AI 助手存在安全问题：任何人给你发消息都能触发 AI 回复。现已实现 **self_only 模式**，AI 只在"给自己发消息"（Message yourself）中响应。

**Bridge 端修改**（`server/bridge/src/whatsapp.ts`）：
- 移除原先 `if (msg.key.fromMe) continue` 的无差别跳过逻辑
- 新增 `getMyJid()` 方法获取自己的 JID，判断是否为 self-chat
- 新增 `sentMessageIds` 集合追踪 bot 发出的消息 ID，防止 AI 回复→触发自己→无限循环
- `sendMessage()` 记录已发消息 ID（保留最近 200 条）
- 消息中新增 `isSelfChat` 字段传给 Python 端

**Python 端修改**（`server/nanobot/channels/whatsapp.py`）：
- 新增 `self_only` 模式检查：启用时只处理 `isSelfChat=true` 的消息，其他全部忽略

**配置修改**（`server/nanobot/config/schema.py` + `server/config.yaml`）：
- `WhatsAppConfig` 新增 `self_only: bool = False` 字段
- `config.yaml` 设置 `self_only: true`

### WhatsApp Bridge 移植到 server/

- 将 WhatsApp Bridge（Node.js）从参考代码 `nanobot-src/bridge/` 移植到 `server/bridge/`
- 包含全部源码：`index.ts`、`server.ts`、`whatsapp.ts`、`types.d.ts`
- 完成 `npm install` + `npm run build`，构建验证通过
- 从此所有运行代码统一在 `server/` 目录下，`nanobot-src/` 仅作参考可删除

### Demo 启动指南

- 新建 `DEMO/启动指南.md`，包含：
  - 环境要求（Python 3.11+、Node.js 20+）
  - 首次安装依赖步骤
  - 两终端启动流程（Bridge → Python 后端）
  - WhatsApp 扫码连接步骤
  - Self-Chat 使用方法
  - 常见问题排查
  - 配置文件速查（切换模型、切换 WhatsApp 模式）
  - 项目文件结构说明

### 代码依赖确认

- 确认 `server/` 下已包含 WhatsApp 测试所需全部文件
- `channels/manager.py` 中其他 channel（Telegram、Discord 等）的导入在 `if enabled:` 条件内，config.yaml 中均为 `false`，不会触发
- `nanobot-src/` 中的 templates/、skills/、其他 channel 文件在当前 WhatsApp 测试阶段不需要

### self_only 配置传递修复

- 修复 `server/main.py` 中创建 `WhatsAppConfig` 时遗漏 `self_only` 参数的 bug
- 原因：`main.py:273` 构造 `WhatsAppConfig` 时没有从 `config.yaml` 读取 `self_only` 字段，导致始终为默认值 `False`，别人发消息仍能触发 AI
- 修复：添加 `self_only=wa_cfg.get("self_only", False)`，现在 config.yaml 中的 `self_only: true` 正确生效
- 验证通过：别人发来的消息已被成功屏蔽

### Demo 启动指南更新

- `DEMO/启动指南.md` 中所有 `cd` 命令和路径更新为完整绝对路径

---

## 2026-03-18 - ASR 引擎更换：faster-whisper → SenseVoice-Small

### 调研

- 完成 SenseVoice 语音识别调研报告（`功能讨论区/SenseVoice调研.md`）
- 对比结论：SenseVoice-Small 推理速度快 5 倍（10秒音频 70ms vs 350ms），中文识别精度更高，额外支持情感识别和音频事件检测

### ASR 引擎替换

- 编写详细更换计划（`功能讨论区/output.md`）
- 替换 `server/services/asr.py`：用 FunASR AutoModel 替代 faster-whisper，保持 `transcribe()` 接口不变
- 更新 `server/config.yaml`：新增 `device`、`use_vad`、`use_itn` 配置项，模型改为 `FunAudioLLM/SenseVoiceSmall`
- 更新 `server/main.py`：适配新的 ASRService 构造参数
- 更新 `server/requirements.txt`：`faster-whisper` → `funasr`（需额外安装 `torchaudio`）
- 修改 `server/channels/device_channel.py`：ASR 识别后将情感信息（`last_emotion`）附加到消息 metadata

### 新增能力

- **情感识别**：SenseVoice 输出包含情感标签（happy/sad/angry/neutral），解析后存入 `ASRService.last_emotion`，通过 metadata 传递给 AI 引擎
- **音频输入优化**：PCM 数据直接用 numpy 解析为 float32 数组，避免临时文件 I/O
- **逆文本正则化（ITN）**：口语数字自动转书面形式（如"二零二六年"→"2026年"）

### 调试记录

- 修复 `torchaudio` 缺失问题：FunASR 依赖 torchaudio 但未自动安装，需手动 `pip install torchaudio`
- 修复 VAD 参数冲突：`model.generate()` 传入 `key="wav"` 与 FSMN-VAD 内部参数冲突，移除 `key` 和 `fs` 参数解决
- ESP32 固件无需改动：音频格式（PCM 16kHz 16bit 单声道）和 WebSocket 协议均未变化

### 测试结果

- 硬件端到端测试通过：ESP32 触摸录音 → SenseVoice 识别 → AI 回复
- 中文识别准确率大幅提升

---

## 2026-03-18 - 屏幕表情显示系统（Phase 1~3）

### 设计计划

- 编写屏幕表情显示系统设计文档（`功能讨论区/output.md`）
- 设计理念："屏幕 = 脸"，不画轮廓框，眼睛和嘴巴直接绘制在黑色背景上
- 三区布局：状态栏 (24px) + 表情区 (168px) + 文字区 (48px) = 240px
- 5 种表情状态：IDLE（空闲）、ACTIVE（最近聊过天）、LISTENING（聆听）、PROCESSING（思考）、SPEAKING（回复）
- 技术方案：TFT_eSPI 基本图形绘制（fillCircle/drawLine/drawPixel），零位图资源

### Phase 1: 静态表情框架

新增 3 个文件：

- **`firmware/arduino/demo/face_config.h`**：布局常量、颜色定义、眼睛/嘴巴尺寸参数、动画参数预定义
- **`firmware/arduino/demo/face_display.h`**：FaceState 枚举 + 接口声明（faceInit/faceSetState/faceUpdate/faceSetText/faceSetStatusBar）
- **`firmware/arduino/demo/face_display.cpp`**：5 种静态表情绘制实现
  - IDLE：圆眼 + 微笑抛物线嘴
  - ACTIVE：大圆眼 + 上扬笑嘴
  - LISTENING：歪头倾听（一大一小不对称眼 + 偏侧短横嘴，模拟透视歪头效果）
  - PROCESSING：横线眯眼 + 波浪嘴 + 三个加载点
  - SPEAKING：圆眼 + 弯眉毛 + 椭圆张嘴
  - 状态栏：时间 + WiFi/WS 连接状态指示
  - 文字区：自动换行显示

修改 **`firmware/arduino/demo/demo.ino`**：
- 集成 face_display 模块，替代原有纯文字显示函数
- `handleServerMessage()` 映射 `state_change` 到 `faceSetState()`
- 新增处理 `face_update` 消息类型（ACTIVE 状态）
- `handleTouch()` 中使用表情状态切换

### Phase 2: 动画系统

在 `face_display.cpp` 中实现 `faceUpdate()` 动画驱动（~15fps 帧率控制）：

| 状态 | 动画效果 | 实现方式 |
|------|----------|----------|
| IDLE | 定期眨眼 | 每 3~5 秒随机触发，圆眼→横线眼→圆眼，持续 200ms |
| ACTIVE | 眼球左右移动 | 正弦波驱动 ±3px，周期 2 秒 |
| LISTENING | 歪头摇摆 + 单眼眨眼 | tiltX 在 3~7 间正弦摇摆，大眼侧每 2~3 秒眨一次 |
| PROCESSING | 加载点循环 | 依次显示 1→2→3→0 个点，500ms 切换 |
| SPEAKING | 嘴巴开合 + 音符上飘 | 嘴巴 400ms 开合交替 + ♪ 音符从右侧上飘 2 秒并渐淡 |

- 使用局部刷新（clearEyeArea/clearMouthArea/clearDotArea/clearNoteArea）避免全屏刷新闪烁
- `faceSetState()` 切换状态时自动重置所有动画变量
- 新增 `drawNote()` 绘制像素风音符 ♪

### Phase 3: 状态栏与文字区

**固件端改进：**

- 状态栏升级：
  - WiFi 图标改为弧线图形（替代"WiFi"文字+圆点），断开时显示 X
  - 新增电池图标（16×10px，带电量颜色：≤20% 红色、≤50% 黄色、>50% 绿色）
  - 新增 `faceSetBattery(int percent)` 接口
- 文字区升级：
  - 文字 buffer 从 128→256 字节
  - 超出 3 行时自动滚动显示（3 秒一次循环），右下角显示↓箭头提示
  - 新增 `countTextLines()`、`updateTextScroll()` 辅助函数
- `demo.ino` 新增处理 `status_bar_update` 消息类型（接收时间 + 电池电量）

**服务端改进：**

- `server/models/protocol.py`：新增 `STATUS_BAR_UPDATE` 和 `FACE_UPDATE` 消息类型
- `server/models/device_state.py`：去除 `STATE_DISPLAY_HINTS` 中的 emoji（ST7789 默认字库不支持），状态提示改为由表情系统承担
- `server/channels/device_channel.py`：
  - 定时推送时间：连接后立即推送 + 每 60 秒自动更新
  - ACTIVE 状态判定：记录 `_last_chat_time`，回到 IDLE 时如果 30 秒内聊过天则发送 `face_update: ACTIVE`
  - 新方法：`_time_push_loop()`、`_send_status_bar_update()`
  - 断线/关闭时正确取消时间推送任务
  - 修正屏幕参数注释：1.69寸→1.54寸

---

## 2026-03-18 - 屏幕表情系统 Phase 4: 服务端集成

### Phase 4: 服务端表情指令集成

- `server/channels/device_channel.py`：
  - 新增 `_STATE_TO_FACE` 映射字典，将 DeviceState 映射为表情状态字符串（IDLE/LISTENING/PROCESSING/SPEAKING/ERROR→IDLE）
  - 修改 `_set_state()` 方法：每次状态切换均发送 `face_update` 消息（之前仅 ACTIVE 状态发送）
  - ACTIVE 判定保留：IDLE 状态下如果 30 秒内聊过天，face_state 覆盖为 "ACTIVE"
  - 完整消息流：状态变化 → `state_change`（设备状态同步）+ `face_update`（表情切换）同时发送
- 步骤14（protocol.py 消息类型）、步骤15（ACTIVE 判定逻辑）此前已完成
- 步骤17（联调测试）需设备连接后进行

### 后端 Skill 创建

- 新增 `.claude/commands/backend.md`：后端开发助手 skill，可通过 `/backend` 调用
- 内容涵盖：架构速查、关键文件表、6大设计模式、编码规范、开发工作流、启动测试命令

---

## 2026-03-19 - 屏幕显示时间和天气

### NTP 本地时间同步（固件）

- `demo.ino` WiFi 连接后调用 `configTime()` 配置 NTP 服务器（`pool.ntp.org` + `time.nist.gov`，时区 UTC+8 香港）
- `loop()` 中每 30 秒通过 `getLocalTime()` 获取本地时间，调用 `faceSetStatusBar()` 更新状态栏
- 移除对服务端时间推送的强依赖：NTP 为主时间源，服务端 `status_bar_update` 中的 time 字段仍可接收但不再是唯一来源
- 解决了之前状态栏显示 `--:--` 的问题（原因是时间完全依赖服务端推送，推送不稳定或未连接时无法显示）

### 天气温度显示（固件端）

- `face_display.cpp` 新增 `_weatherBuf[16]` 静态变量存储天气字符串
- `drawStatusBar()` 中在 WS 状态点 (x=118) 和电池图标 (x=210) 之间显示天气文字 (x=130)
- 新增 `faceSetWeather(const char* weather)` 公开接口
- `face_display.h` 声明 `faceSetWeather()`
- `demo.ino` 的 `handleServerMessage()` 中解析 `status_bar_update` 的 `weather` 字段并调用 `faceSetWeather()`

### 天气推送（服务端）

- `server/config.yaml` 新增 `weather` 配置段：`api_key`（环境变量 `OPENWEATHERMAP_API_KEY`）、`city`（Hong Kong）、`units`（metric）
- `server/config.py` 新增 weather API Key 环境变量解析（支持 `${OPENWEATHERMAP_API_KEY}` 格式）
- `server/channels/device_channel.py`：
  - 新增 `_weather_push_loop()`：每 30 分钟从 OpenWeatherMap API 获取天气并推送到设备
  - 新增 `_fetch_weather()`：调用 OpenWeatherMap Current Weather API，返回格式化温度字符串（如 `"23°C"`）
  - `_send_status_bar_update()` 新增 `weather` 参数
  - 设备连接时自动启动天气推送任务，断开/关闭时正确取消
  - 新增 `set_weather_config()` 方法接收配置
- `server/main.py`：DeviceChannel 初始化时传入 weather 配置

### 验证方法

1. 上传固件后，连 WiFi 即可看到状态栏显示正确时间（不依赖服务端）
2. 设置 `OPENWEATHERMAP_API_KEY` 环境变量并启动服务端后，状态栏显示温度（如 `23°C`）
3. Serial 监视器可检查 NTP 同步和天气接收日志

---

## 2026-03-22 - 电源模块更换与主板重构

### 电源模块调整与问题复测

- 更换电源模块后，系统供电电压由原先约 `2.8V` 提升至约 `3.1V`
- 重新验证后确认：初始化喇叭时出现的设备断连问题仍未解决，说明问题不只在原电源模块

### 问题定位

- 进一步详细查阅数据手册后发现，音频传输和屏幕 `SPI` 传输都使用了 `FSPI/SUBSPI` 相关线路
- 判断该复用关系可能导致总线占用冲突，进而引发喇叭异常启动和连接不稳定问题

### 原理图与PCB重做

- 于 `2026-03-22` 重新绘制主板原理图
- 除更换为当前电源模块方案外，同时将喇叭相关接线调整至 `IO21`
- 重新完成 PCB 布线
- 板层由原 `4` 层板调整为 `2` 层板，以简化设计并降低打样成本
- 当前已完成布线，预计次日下单打板

---

## 2026-03-25 - 后端架构回写 + 本地方向确认

### 后端架构文档更新

- 阅读 `server/` 与 `server/bridge/` 当前本地代码实现，重写 `功能讨论区/架构.md`
- 将文档从早期设计稿更新为“按实际代码整理”的当前后端架构说明
- 明确当前后端定位：本地单机、可运行 Demo 级后端，核心链路为 ESP32 设备 WebSocket + Python 服务端 + Node.js WhatsApp Bridge

### 产品方向确认

- 确认当前阶段优先目标是“稳定的本地 AI 设备 / 电脑中枢”，而不是云端平台
- 确认网络范围先只做局域网，不做“App 远程控制家里电脑”的公网方案
- 确认后端运行在用户电脑，定位为单人单设备、单人多端
- 确认 WhatsApp 当前只保留为测试通道，后续正式客户端以 Flutter App 为主
- 确认会话策略：设备、Flutter App、WhatsApp 各自独立会话，但共享当前任务、任务队列以及后续 Todo / 日历等全局运行态

### 规划文档新增

- 新增 `功能讨论区/TODO/2026-03-25-后端优化强化计划.md`
- 新增 `功能讨论区/TODO/2026-03-25-Flutter本地局域网API与实时事件模型草案.md`

---

## 2026-03-26 - Flutter 本地局域网 App Runtime API + 实时事件流落地

### 后端装配与运行时整理

- 新增 `server/bootstrap.py`，统一运行时构建、配置校验、日志装配与 HTTP App 挂载
- 重构 `server/main.py`，将其收口为启动、关闭与后台任务管理入口
- 新增 `server/services/outbound_router.py`，统一处理 device / whatsapp / app 的 outbound 路由

### Flutter App Runtime API 第一版

- 新增 `server/services/app_runtime.py`，提供面向 Flutter 本地局域网版的最小 REST API 与 WebSocket 事件流
- 已落地能力包括：`bootstrap`、会话列表/创建、会话消息分页、发消息、全局运行态、停止任务、Todo 摘要、日历摘要、设备快照、设备播报、capabilities、`/ws/app/v1/events`
- 会话消息查询支持 `limit / before / after` 分页语义
- 发消息后立即返回 `accepted_message + task_id`，为 Flutter 端先落本地消息提供基础

### 实时事件模型与断线恢复

- WebSocket 事件流新增 `system.hello` 握手事件
- 支持 `last_event_id` 断线续传与事件回放
- 已落地事件包括：用户消息创建、AI 处理中进度、AI 最终完成、任务失败、当前任务变化、任务队列变化、设备连接变化、设备状态变化、设备状态详情更新、Todo 摘要变化、日历摘要变化
- 为 Flutter 端建立了“REST 拿快照 + WebSocket 拿实时”的标准接入模型

### Agent / Session / 配置补强

- `server/nanobot/agent/loop.py` 改为“同一 session 串行、不同 session 可并行”的处理方式
- 完善 `/stop` 取消链路，打通 App 停止任务与设备中断的基础能力
- 会话消息补齐 `message_id`、`task_id`、`client_message_id` 等持久化字段，便于 Flutter 去重和任务跟踪
- `server/config.py` 与 `server/config.yaml` 补充 App token、运行依赖检查与启动前配置校验
- `server/channels/device_channel.py` 接入 App Runtime 事件观察器，设备状态变化可同步到 App 事件流

### 测试与接入文档

- 新增 `server/tests/test_app_runtime.py`、`server/tests/test_agent_loop.py`、`server/tests/test_device_channel.py`、`server/tests/test_config.py`
- 当前服务端测试结果：`server/tests` 共 `16` 项 unittest 通过
- 新增 `功能讨论区/TODO/2026-03-26-Flutter本地局域网接入说明.md`，面向 Flutter 端说明接口、事件流、断线恢复与错误处理方式

### 后续稳定性计划拆分

- 按问题拆分新增 5 份后端优化计划，分别覆盖：模型调用超时与卡死保护、App 消息幂等与重试安全、消息总线队列上限与背压、运行时任务清理与保留策略、会话与摘要原子写
- 将 5 份计划文件重命名为带顺序编号的版本，便于后续按依赖顺序实施

---

## 当前待办更新

- [x] IO8 飞线至 IO21 — 已完成，I2S 通信正常
- [x] AMS1117 电源问题定位 — 已确认压差不足，更换为 AP2114H-3.3
- [x] 后端 Phase 1-6 全部完成
- [x] WhatsApp self-chat 安全过滤（self_only 模式）
- [x] WhatsApp Bridge 移植到 server/bridge/
- [x] Demo 启动指南文档
- [x] 屏幕表情显示系统 Phase 1~3（静态表情 + 动画 + 状态栏文字区）
- [x] 屏幕表情显示系统 Phase 4 服务端集成（所有状态切换均发送 face_update）
- [x] NTP 本地时间同步（ESP32 固件，解决状态栏 `--:--` 问题）
- [x] 天气温度显示（固件端 + 服务端 OpenWeatherMap 推送）
- [x] Flutter 本地局域网 App Runtime API 与 WebSocket 事件流第一版
- [x] Flutter App 会话列表 / 消息分页 / 发消息 / 共享运行态 / 设备控制接口
- [x] `last_event_id` 断线续传与事件回放
- [x] Flutter 本地局域网接入说明文档
- [ ] 屏幕表情显示系统 联调测试（需设备连接）
- [ ] AP2114H-3.3 焊接更换 + 重新测试大音量 TTS 播放
- [ ] WS2812B 灯带焊接与测试
- [ ] LED 灯效控制（后端 Phase 5.2，等硬件就绪）
- [ ] 2026-03-23 下单新版两层主板 PCB 打样
- [ ] ESP32 固件开发（连接后端 WebSocket + 音频采集/播放）
- [ ] 模型调用超时与卡死保护
- [ ] App 消息幂等与重试安全
- [ ] 消息总线队列上限与背压
- [ ] 运行时任务清理与保留策略
- [ ] 会话与摘要原子写
