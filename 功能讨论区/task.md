# 桌面AI助手 - MVP任务列表

> 基于 CLAUDE.md 原理图v2.0 整理
> 创建日期: 2026-02-05 | 更新日期: 2026-02-25
> 最小MVP方案：ESP32-S3 + INMP441 + MAX98357A + 喇叭 + 屏幕 + MPU6050 + 触摸 + WS2812B + 电源管理

---

## ~~一、硬件准备与采购~~ ✅ 已完成

### 1.1 元件采购清单

| 元件 | 型号 | 封装 | 数量 | 用途 |
|------|------|------|------|------|
| 主控模组 | ESP32-S3-WROOM-1-N16R8 | 模组 | 1 | WiFi/蓝牙双核主控 (16MB Flash + 8MB PSRAM) |
| 麦克风 | EV_INMP441 | 模组 | 1 | I2S 24bit数字语音采集 |
| 功放 | MAX98357AETE+T | QFN-16 | 1 | I2S D类音频功放 |
| 扬声器 | 3W 4Ω | - | 1 | 语音播放 |
| 显示屏 | 1.69" IPS TFT ST7789 | 12P FPC | 1 | 时间/天气/状态显示 |
| 六轴传感器 | ZY-MPU-6050 | 邮票孔(2×4, 2.54mm) | 1 | 摇一摇检测 |
| 充电IC | TP4056 | SOP-8 | 1 | 锂电池充电管理（1A） |
| 稳压 | AMS1117-3.3 | SOT-223 | 1 | 3.3V LDO |
| 锂电池 | 3.7V 1000-2000mAh | - | 1 | 便携供电 |
| 电池座 | B2B-PH-K-S (JST PH 2P) | - | 1 | 锂电池连接 |
| USB座 | KH-TYPE-C-16P-N | 16P母座 | 1 | 充电与USB调试 |
| 屏幕FPC座 | AFC01-S12FCA-00 | 12P FPC | 1 | 显示屏连接 |
| 喇叭座 | PZ254V-11-02P | 2P | 1 | 扬声器连接 |
| 电源开关 | SK12D07VG4 | 拨动开关 | 1 | 电源总开关 |
| 复位按键 | 轻触开关 | - | 1 | ESP32-S3 EN复位 |
| LED灯带 | WS2812B | - | 若干 | 氛围灯/状态指示 |
| 电阻电容 | 详见CLAUDE.md | 0603/0805 | 若干 | 去耦/限流/滤波 |
| 充电LED | 红(D1)+绿(D2) | 0603 | 2 | 充电状态指示 |
| 扩展排母 | 2.54mm 1×5P | - | 3 | H1/H2/H4扩展接口 |
| 触摸子板 | PCB铜皮触摸板 | - | 1 | 电容触摸交互 |

### 1.2 采购任务

- [x] 全部元件已通过嘉立创商城一站式采购

---

## ~~二、硬件开发环境搭建~~ （焊接后进行）

### 2.1 开发环境

- [ ] 安装 Arduino IDE 或 PlatformIO
- [ ] 安装 ESP32-S3 开发板支持包（选择 ESP32-S3-WROOM-1-N16R8）
- [ ] 安装必要的库：
  - [ ] TFT_eSPI（ST7789显示驱动）
  - [ ] ESP32-audioI2S 或 ESP-IDF I2S驱动
  - [ ] Adafruit_NeoPixel 或 FastLED（WS2812B灯带）
  - [ ] MPU6050 / Adafruit_MPU6050（六轴传感器）
  - [ ] ArduinoWebsockets（WebSocket通信）
  - [ ] ArduinoJson（数据序列化）
- [ ] 配置串口调试工具（USB直连，IO19/IO20）

### 2.2 TFT_eSPI 配置

- [ ] 修改 User_Setup.h，设定ST7789引脚：
  - SCK=IO12, MOSI=IO11, DC=IO10, CS=IO9, RST=IO46
- [ ] 设定屏幕分辨率 240×280（1.69寸）
- [ ] 设定SPI频率（建议40MHz起步）

---

## ~~三、焊接质量检查与上电测试~~

### 3.0 焊接质量检查（上电前必做）

- [ ] 目视检查所有焊点（放大镜），确认无虚焊、桥连、漏焊
- [ ] 万用表测 3.3V 与 GND 之间不短路
- [ ] 万用表测 VBAT 与 GND 之间不短路
- [ ] 万用表测 USB 5V 与 GND 之间不短路
- [ ] 确认SW1拨动开关在断开位置

### 3.1 电源系统测试

- [ ] 插入USB Type-C，检查TP4056工作（D1红灯亮=充电中）
- [ ] 接入锂电池，充满后D2绿灯亮
- [ ] 打开SW1，万用表测AMS1117输出 = 3.3V（±0.1V）
- [ ] 确认3.3V供电稳定，无明显纹波

### 3.2 ESP32-S3 基础测试

- [ ] USB连接电脑，确认串口设备被识别
- [ ] 烧录Blink测试程序，验证主控正常运行
- [ ] 测试 WiFi 扫描功能（验证天线工作）
- [ ] 测试串口打印输出

### 3.3 显示屏（ST7789，SPI）

- [ ] 配置 TFT_eSPI 引脚（SCK=12, MOSI=11, DC=10, CS=9, RST=46）
- [ ] 烧录屏幕测试程序（填充颜色、显示文字）
- [ ] 验证屏幕背光亮度正常（R6=4.7Ω限流）
- [ ] 测试屏幕刷新率，确认无明显闪烁

### 3.4 麦克风（EV_INMP441，I2S）

- [ ] 烧录I2S录音测试程序（SCK=14, WS=15, SD=16）
- [ ] 串口打印采样数据，确认非全0/全1
- [ ] 对麦克风说话，观察数据波形变化
- [ ] 测试采样率（建议16kHz，语音识别够用）

### 3.5 功放与扬声器（MAX98357A，I2S）

- [ ] 烧录I2S播放测试程序（BCLK=17, LRC=18, DIN=8）
- [ ] 播放正弦波测试音，确认喇叭有声
- [ ] 测试不同音量等级
- [ ] 测试音质，确认无明显底噪或失真

### 3.6 六轴传感器（ZY-MPU-6050，I2C）

- [ ] 烧录I2C扫描程序，确认检测到设备地址 0x68
- [ ] 读取加速度计数据，平放时Z轴≈1g
- [ ] 读取陀螺仪数据，静止时≈0
- [ ] 测试摇一摇检测（加速度突变判定）

### 3.7 触摸输入（ESP32-S3内置电容触摸）

- [ ] 烧录touchRead()测试程序（IO7 = TOUCH_MAIN）
- [ ] 串口打印触摸值，观察触摸/未触摸的数值差异
- [ ] 确定触摸阈值
- [ ] 测试备用触摸引脚（IO1, IO2, IO3, IO13）

### 3.8 WS2812B RGB灯带

- [ ] 烧录NeoPixel/FastLED测试程序（数据线=IO38）
- [ ] 测试所有LED亮起、颜色切换
- [ ] 测试呼吸灯、流水灯等动画效果

### 3.9 触摸子板

- [ ] 确认触摸子板与主板通过H4排母正确连接（IO3, 3V3, GND, LED_DIN）
- [ ] 测试触摸铜皮区域的电容触摸灵敏度
- [ ] 确认子板上WS2812B灯带数据线（LED_DIN）通路正常

---

## ~~四、硬件功能整合~~

### 4.1 音频系统整合

- [ ] 实现麦克风录音 → 内存缓冲 → 扬声器播放（回声测试）
- [ ] 测试录音同时播放是否有串扰
- [ ] 优化音频参数（采样率、位深、缓冲区大小）

### 4.2 显示+触摸整合

- [ ] 触摸切换屏幕页面（时钟页/状态页/设置页）
- [ ] 触摸触发录音（长按=开始录音，松开=结束）
- [ ] 屏幕显示触摸反馈动画

### 4.3 灯光+传感器整合

- [ ] WS2812B随设备状态变色（待机=呼吸蓝，录音=红，播放=绿，思考=黄）
- [ ] MPU6050摇一摇触发唤醒/特定功能
- [ ] MPU6050中断引脚（IO4）配置，支持运动检测唤醒

### 4.4 整体联调

- [ ] 所有模块同时工作，检查功耗（万用表测总电流）
- [ ] 检查各模块发热情况
- [ ] 锂电池供电下运行稳定性测试
- [ ] 估算电池续航（记录电流，计算 mAh/实际使用时间）

---

## ~~五、原理图与PCB设计~~ ✅ 已完成

- [x] 嘉立创EDA专业版完成原理图v2.0
- [x] PCB布局布线完成
- [x] ERC/DRC检查通过
- [x] 触摸子板原理图与PCB完成
- [x] 嘉立创PCB下单打样
- [x] 全部元件采购完成

---

## 六、固件开发

### 6.1 项目框架搭建

- [ ] 创建 PlatformIO/Arduino 项目
- [ ] 设定编译目标：ESP32-S3-WROOM-1-N16R8（16MB Flash, 8MB PSRAM, OPI）
- [ ] 配置分区表（OTA分区，方便后续无线升级）
- [ ] 创建模块化代码结构（audio/, display/, network/, sensor/, led/）

### 6.2 WiFi与通信模块

- [ ] 实现 WiFi 自动连接（读取已保存SSID/密码）
- [ ] 实现首次配网功能（SmartConfig 或 Web AP配网）
- [ ] 实现 WebSocket 客户端，连接电脑服务端
- [ ] 实现心跳保活与断线自动重连
- [ ] 定义通信协议（JSON消息格式：音频数据、控制指令、状态同步）

### 6.3 音频采集模块

- [ ] 封装INMP441 I2S录音驱动（SCK=14, WS=15, SD=16）
- [ ] 实现VAD语音活动检测（检测说话开始/结束）
- [ ] 实现录音缓冲区管理（环形缓冲，PSRAM存储）
- [ ] 实现音频数据通过WebSocket流式发送到服务端
- [ ] 支持配置采样率（16kHz）、位深（16bit）、单声道

### 6.4 音频播放模块

- [ ] 封装MAX98357A I2S播放驱动（BCLK=17, LRC=18, DIN=8）
- [ ] 实现从WebSocket接收音频流并实时播放
- [ ] 实现播放缓冲区管理（防止卡顿，至少缓冲200ms再开始播放）
- [ ] 实现音量控制（软件增益调节）
- [ ] 支持播放本地提示音（开机音、错误音、触摸反馈音）

### 6.5 显示界面模块

- [ ] 封装ST7789 SPI显示驱动（SCK=12, MOSI=11, DC=10, CS=9, RST=46）
- [ ] 实现待机主界面：
  - [ ] 数字时钟显示（从服务端同步NTP时间）
  - [ ] 天气图标+温度（从服务端获取）
  - [ ] WiFi信号强度指示
  - [ ] 电池电量指示（通过ADC读取电池电压）
- [ ] 实现状态界面：
  - [ ] 录音中 — 声波动画/麦克风图标
  - [ ] AI思考中 — 加载动画
  - [ ] 播放中 — 音频波形/扬声器图标
- [ ] 实现设置界面（WiFi配置、音量调节等）
- [ ] 实现页面切换动画（触摸滑动/点击切换）

### 6.6 触摸交互模块

- [ ] 封装ESP32-S3电容触摸驱动（IO7主触摸）
- [ ] 实现触摸手势识别：
  - [ ] 单击 — 开始/停止录音
  - [ ] 双击 — 播放/暂停
  - [ ] 长按 — 持续录音模式（按住说话）
- [ ] 实现触摸去抖与阈值自适应校准
- [ ] 触摸事件通过回调通知状态机

### 6.7 传感器模块

- [ ] 封装MPU6050 I2C驱动（SDA=5, SCL=6, INT=4）
- [ ] 实现摇一摇检测算法（加速度阈值判定）
- [ ] 摇一摇触发功能（如：唤醒设备、切换模式、随机回答）
- [ ] 配置MPU6050运动检测中断，降低轮询功耗

### 6.8 LED灯带模块

- [ ] 封装WS2812B驱动（IO38）
- [ ] 实现状态灯效：
  - [ ] 待机 — 缓慢呼吸蓝光
  - [ ] 录音中 — 红色脉冲
  - [ ] AI思考中 — 黄色旋转
  - [ ] 播放中 — 绿色流动
  - [ ] 错误 — 红色快闪
  - [ ] 充电中 — 橙色渐变
- [ ] 实现灯效平滑过渡（颜色渐变，不突变）
- [ ] 支持亮度调节

### 6.9 设备状态机

- [ ] 设计并实现主状态机：
  ```
  IDLE(待机) → LISTENING(录音) → PROCESSING(等待AI) → SPEAKING(播放) → IDLE
  ```
- [ ] 各状态对应的屏幕显示、灯效、音频行为
- [ ] 状态切换触发条件（触摸、摇一摇、服务端指令、VAD检测）
- [ ] 异常状态处理（WiFi断线、服务端无响应、电量低）

### 6.10 系统功能

- [ ] 实现OTA无线固件升级（从服务端下载固件）
- [ ] 实现低功耗模式（无操作N分钟后进入Light Sleep，触摸/摇一摇唤醒）
- [ ] 实现开机自检（检查各模块是否正常，屏幕显示结果）
- [ ] 实现电池电量监测（ADC读取分压电压，映射为百分比）
- [ ] 实现配置持久化（NVS存储WiFi密码、音量、亮度等设置）

---

## 七、电脑服务端开发

> 架构详见 `功能讨论区/架构.md`
> 后端风格：单体 FastAPI + asyncio 异步驱动，一个 Python 进程

### 7.1 项目初始化

- [ ] 创建项目目录结构：
  ```
  server/
  ├── main.py              # 入口，启动 FastAPI + uvicorn
  ├── config.yaml          # 用户配置
  ├── api/                 # 对外接口层
  ├── core/                # 核心业务逻辑（编排层）
  ├── services/            # 具体服务实现
  │   └── tools/           # LLM 工具实现
  ├── prompts/             # 提示词文件（纯 Markdown）
  │   └── tools/           # 每个工具的使用说明
  ├── models/              # 数据模型 / 协议定义
  ├── db/                  # 数据库（schema.sql + database.py）
  └── data/                # 运行时数据（gitignore）
  ```
- [ ] 初始化 FastAPI + uvicorn 入口 (`main.py`)
- [ ] 配置依赖管理（requirements.txt / pyproject.toml）
- [ ] 配置日志系统（logging）
- [ ] 编写配置文件 `config.yaml`（LLM API Key、Whisper模型、TTS语音、服务端端口等）
- [ ] 实现配置热加载（修改 config.yaml 不需要重启服务）

### 7.2 通信服务（WebSocket + REST API）

**两条 WebSocket 端点：**

- [ ] 实现 `/ws/device` — 硬件设备端点（`api/ws_device.py`）
  - [ ] 接收二进制音频帧（`audio_stream`）
  - [ ] 接收 JSON 控制指令（`audio_end`、`touch_event`、`shake_event`、`device_status`）
  - [ ] 发送 TTS 音频流（`audio_play`、`audio_play_end`）
  - [ ] 发送屏幕更新（`display_update`）、LED控制（`led_control`）、状态切换（`state_change`）
- [ ] 实现 `/ws/app` — 手机App端点（`api/ws_app.py`）
  - [ ] 接收文字消息（`chat_message`）和控制指令（`command`）
  - [ ] 发送 AI回复（`chat_reply`）、用户消息同步（`chat_user`）、设备状态推送（`device_status`）、工具执行结果（`tool_result`）
- [ ] 统一 JSON 消息格式：`{ type, data, timestamp }`
- [ ] 实现心跳保活（30秒 ping/pong）与断线处理

**REST API 端点：**

- [ ] 实现 `GET /api/health` — 服务端在线检测（App 局域网发现用）
- [ ] 实现 `GET /api/config` — 读取当前配置（API Key 脱敏）
- [ ] 实现 `PUT /api/config` — 修改配置，服务端热加载生效
- [ ] 实现 `GET /api/device/status` — 硬件设备状态（在线/电量/WiFi信号）
- [ ] 实现 `GET /api/history` — 对话历史
- [ ] 实现 `POST /api/chat` — App端文字发送消息（HTTP替代方案）

### 7.3 会话管理（SessionManager）

- [ ] 实现 SessionManager（`core/session.py`）
  - [ ] 单用户单 Session，硬件和 App 共享对话上下文
  - [ ] 维护 `conversation` 列表、`device_ws`、`app_ws` 连接引用
  - [ ] 维护 `device_status`（电量、WiFi信号、在线状态）
- [ ] 实现状态同步规则：
  - [ ] 任一端发消息 → 写入共享 conversation → 另一端实时推送
  - [ ] 硬件离线时 App 仍可对话，硬件上线后自动同步
  - [ ] App 离线时硬件正常工作，App 上线后拉取历史
- [ ] 实现设备状态管理（`core/state.py`）

### 7.4 语音识别（ASR）

- [ ] 集成 Whisper（本地部署，推荐 base 模型）
- [ ] Whisper 是 CPU 密集型 → 放到 `线程池/进程池` 异步执行，不阻塞主循环
- [ ] 实现音频流接收 → PCM转WAV → Whisper转文字（`services/asr.py`）
- [ ] 支持中英文识别
- [ ] 实现流式识别（可选，初版可用完整音频识别）
- [ ] 识别结果传给 LLM 对话引擎

### 7.5 语音合成（TTS）

- [ ] 集成 Edge-TTS（`services/tts.py`）
- [ ] 实现文字 → PCM 音频（转为 ESP32 可播放的 16kHz 16bit）
- [ ] 实现音频流式发送给设备（边合成边发送，降低等待时间）
- [ ] 支持选择语音角色（config.yaml 中 `tts.voice` 配置）
- [ ] Edge-TTS 是 IO 密集型 → 用 `async/await` 原生异步

### 7.6 LLM + Tool Use 对话引擎

- [ ] 实现 Claude API 调用封装（`services/llm.py`）
  - [ ] 使用 Claude `tool_use` 功能
  - [ ] 实现流式响应（Streaming），边生成边合成语音
- [ ] 实现提示词文件系统（`prompts/`）：
  - [ ] 主系统提示词 `prompts/system.md`（AI 人格、行为规范）
  - [ ] 每个工具的使用说明 `prompts/tools/*.md`（统一格式：描述、何时使用、可用操作、调用示例）
  - [ ] 每次 LLM 调用前拼接：system.md + 所有 tools/*.md + 历史摘要 + 最近20轮对话
- [ ] 实现提示词热加载（检查文件修改时间，有变化则重新加载，不需要重启服务）
- [ ] 实现 3 个 LLM 工具：
  - [ ] **task_queue**（任务队列）— `services/tools/task_queue.py` + `prompts/tools/task_queue.md`
    - [ ] 创建/查看/完成/删除任务，读写 SQLite tasks 表
  - [ ] **events**（日程+日历统一管理）— `services/tools/events.py` + `prompts/tools/events.md`
    - [ ] 日程提醒（type=reminder）、日历事件（type=event）、闹钟
    - [ ] 读写 SQLite events 表
    - [ ] 任务可通过 event_id 关联日历提醒
  - [ ] **computer**（电脑控制）— `services/tools/computer.py` + `prompts/tools/computer.md`
    - [ ] 调用 Nanobot 执行电脑操作（subprocess 调用）
- [ ] 实现 Tool 基类（`services/tools/base.py`）— 统一接口，工具自动发现注册
- [ ] 实现意图路由（`core/intent.py`）：LLM 返回 tool_use → 分发到对应工具 → 结果反馈给 LLM

### 7.7 Nanobot 集成（电脑控制）

- [ ] 安装 Nanobot（`pip install nanobot-ai`）
- [ ] 封装 Nanobot 调用接口（`services/computer.py`）
- [ ] 实现常用电脑控制功能：
  - [ ] 打开/关闭应用程序
  - [ ] 文件搜索与打开
  - [ ] 系统设置（音量、亮度等）
  - [ ] 网页操作（打开网址、搜索等）
- [ ] 实现执行结果反馈给 Claude（成功/失败/结果描述）
- [ ] Nanobot 配置项写入 config.yaml（`nanobot.enabled`）

### 7.8 数据库与数据服务

**SQLite 数据库（`db/`）：**

- [ ] 实现 SQLite 连接管理（`db/database.py`），开启 WAL 模式
- [ ] 创建建表脚本（`db/schema.sql`）：
  - [ ] `tasks` 表 — 任务队列（status、priority、event_id 外键关联 events）
  - [ ] `events` 表 — 日程+日历合并表（type 区分 reminder/event）
  - [ ] `conversations` 表 — 对话历史（source 区分 device/app，compressed 标记）
  - [ ] `summaries` 表 — 对话摘要（LLM 压缩后的长期记忆）
  - [ ] 索引：tasks(status, due_at)、events(start_time, type)、conversations(compressed, created_at)、summaries(source_start_id, source_end_id)
- [ ] 实现对话历史压缩策略：
  - [ ] 未压缩对话超过 50 轮时触发
  - [ ] 发给 Claude 生成 200 字以内摘要，存入 summaries 表
  - [ ] 原始对话标记 compressed = 1
  - [ ] 每次 LLM 调用：历史摘要（长期记忆）+ 最近 20 轮完整对话（精确上下文）

**数据服务（`services/data.py`）：**

- [ ] 实现 NTP 时间同步（推送给设备显示）
- [ ] 实现天气数据获取（调用免费天气API，推送给设备）
- [ ] 实现设备状态监控（电量、WiFi信号、在线状态）

---

## 八、手机 App 开发（Flutter）

> 架构详见 `功能讨论区/架构.md` 第八节
> 技术栈：Flutter 3.x + Riverpod + Material 3 + go_router

### 8.1 项目初始化

- [ ] 创建 Flutter 项目，配置目录结构：
  ```
  app/lib/
  ├── main.dart
  ├── config/      # 主题、路由
  ├── models/      # 数据模型（与服务端协议对齐）
  ├── services/    # 网络层（WebSocket + REST）
  ├── providers/   # 状态管理（Riverpod）
  ├── screens/     # 页面
  └── widgets/     # 可复用组件
  ```
- [ ] 配置依赖（pubspec.yaml）：
  - [ ] flutter_riverpod（状态管理）
  - [ ] web_socket_channel（WebSocket）
  - [ ] http（REST API）
  - [ ] go_router（路由）
  - [ ] shared_preferences（本地缓存）
- [ ] 配置 Material 3 主题（亮色/暗色模式）

### 8.2 网络层

- [ ] 实现 WebSocket 连接管理（`services/ws_service.dart`）
  - [ ] 连接 `/ws/app` 端点
  - [ ] 收到消息按 `type` 字段分发给对应 Provider
  - [ ] 心跳保活（30秒 ping/pong）
  - [ ] 断线自动重连
  - [ ] App 进入后台断开 WS，回到前台自动重连
- [ ] 实现 REST API 调用封装（`services/api_service.dart`）
  - [ ] GET /api/config、PUT /api/config
  - [ ] GET /api/device/status
  - [ ] GET /api/history
  - [ ] POST /api/chat
- [ ] 实现局域网服务发现（`services/discovery_service.dart`）
  - [ ] 局域网广播扫描 `GET /api/health`
  - [ ] 发现后记住 IP:端口
  - [ ] 备用方案：用户手动输入 IP:端口

### 8.3 数据模型

- [ ] 定义 `Message` 模型（对话消息，`models/message.dart`）
- [ ] 定义 `Task` 模型（任务，`models/task.dart`）
- [ ] 定义 `Event` 模型（日程/日历事件，`models/event.dart`）
- [ ] 定义 `DeviceStatus` 模型（设备状态，`models/device_status.dart`）
- [ ] 定义 `AppConfig` 模型（配置项，`models/app_config.dart`）

### 8.4 状态管理（Riverpod Providers）

- [ ] 实现 `chat_provider.dart` — 对话状态（消息列表、发送消息）
- [ ] 实现 `device_provider.dart` — 设备状态（在线、电量、WiFi）
- [ ] 实现 `task_provider.dart` — 任务列表状态
- [ ] 实现 `event_provider.dart` — 日程日历状态
- [ ] 实现 `config_provider.dart` — 配置状态

### 8.5 页面开发

**底部导航栏（4个 Tab）：首页 / 对话 / 任务日程 / 设置**

- [ ] **首页** (`screens/home_screen.dart`)
  - [ ] 设备状态卡片：在线/离线、电量、WiFi信号强度
  - [ ] 设备当前状态：待机/录音中/播放中
  - [ ] 快捷操作按钮：静音、LED开关、重启设备
- [ ] **对话** (`screens/chat_screen.dart`)
  - [ ] 聊天气泡界面（类似微信）
  - [ ] 区分消息来源：设备端(麦克风) / App端(文字)
  - [ ] 底部输入栏：文字输入 + 发送按钮 + 语音按钮(后期)
  - [ ] 工具调用结果以卡片形式展示
- [ ] **任务/日程** (`screens/tasks_screen.dart` + `screens/events_screen.dart`)
  - [ ] 顶部 Tab 切换：任务列表 / 日历视图
  - [ ] 任务列表：按优先级分组，支持滑动完成/删除
  - [ ] 日历视图：月历 + 日视图，标记有事件的日期
  - [ ] 浮动按钮：手动创建任务/事件
- [ ] **设置** (`screens/settings_screen.dart`)
  - [ ] 服务端连接：IP地址、端口、连接状态
  - [ ] LLM配置：API Key（脱敏显示）、模型选择
  - [ ] 语音配置：TTS语音角色、语速
  - [ ] 设备配置：音量、LED灯效模式
  - [ ] 关于：版本信息
- [ ] **首次连接** (`screens/connect_screen.dart`)
  - [ ] 局域网自动扫描 + 手动输入 IP

### 8.6 可复用组件

- [ ] `chat_bubble.dart` — 对话气泡
- [ ] `message_input.dart` — 消息输入框（文字 + 语音按钮）
- [ ] `device_card.dart` — 设备状态卡片
- [ ] `task_tile.dart` — 任务列表项
- [ ] `event_tile.dart` — 日程列表项

---

## 九、系统联调与测试

### 9.1 端到端语音交互测试

- [ ] 完整流程：说话 → 麦克风采集 → `/ws/device` 发送 → Whisper识别 → Claude + tool_use → TTS合成 → `/ws/device` 返回 → 扬声器播放
- [ ] 测量全链路延迟（目标：<3秒从说完到开始播放）
- [ ] 测试不同距离、不同环境噪声下的识别准确率
- [ ] 测试长句和短句的处理

### 9.2 电脑控制功能测试（Nanobot）

- [ ] 语音打开指定应用程序
- [ ] 语音搜索文件
- [ ] 语音调节系统音量/亮度
- [ ] 测试复杂指令的理解与执行
- [ ] 验证 Nanobot 执行结果正确反馈给 Claude

### 9.3 LLM 工具功能测试

- [ ] 语音创建任务，验证 tasks 表写入正确
- [ ] 语音创建日程提醒，验证 events 表写入正确
- [ ] 语音查询"今天有什么任务"，验证返回结果正确
- [ ] 测试任务关联日历提醒（event_id 外键）
- [ ] 测试对话历史压缩（超过50轮后自动摘要）

### 9.4 App 功能测试

- [ ] App 局域网发现服务端
- [ ] App 文字对话功能（`/ws/app` 发送，接收AI回复）
- [ ] App 与硬件共享对话上下文（硬件说的话 App 能看到）
- [ ] App 读写配置（API Key、TTS语音、音量等）
- [ ] App 查看/管理任务和日程
- [ ] App 查看设备状态（在线、电量、WiFi）

### 9.5 显示与交互测试

- [ ] 待机界面信息准确（时间、天气、电量）
- [ ] 状态切换时屏幕和灯光同步变化
- [ ] 触摸操作响应灵敏
- [ ] 摇一摇触发正常

### 9.6 稳定性与续航测试

- [ ] 连续运行4小时无崩溃
- [ ] WiFi断线后硬件自动重连
- [ ] 服务端重启后设备自动恢复连接
- [ ] App 后台切前台自动重连 WebSocket
- [ ] 电池续航测试（记录不同使用模式下的续航时间）
- [ ] 内存泄漏检查（ESP32可用堆内存 + 服务端Python内存）

### 9.7 外壳装配测试

- [ ] PCB装入3D打印外壳，确认尺寸配合
- [ ] 扬声器出音孔位置正确
- [ ] 麦克风拾音孔位置正确
- [ ] 屏幕窗口对齐
- [ ] 触摸区域灵敏度（隔着外壳）
- [ ] USB充电口可正常插入
- [ ] 电源开关操作方便

---

## MVP验收标准

1. **硬件正常工作**：所有模块（ESP32-S3 + 麦克风 + 扬声器 + 屏幕 + MPU6050 + 触摸 + WS2812B）正常运行
2. **语音交互**：对设备说话，能识别并语音回复，全链路延迟<3秒
3. **LLM工具系统**：语音创建任务、设置日程提醒、查询日程，数据正确存入SQLite
4. **电脑控制**：能通过语音控制电脑（Nanobot：打开应用、文件操作等）
5. **待机显示**：屏幕显示时间/天气/电量信息
6. **交互体验**：触摸控制流畅，灯光状态同步，摇一摇功能正常
7. **手机App**：能通过App文字对话、查看任务日程、修改配置、查看设备状态
8. **多端协同**：硬件与App共享对话上下文，设备间无缝切换

---

## 引脚分配参考（ESP32-S3-WROOM-1-N16R8 原理图v2.0）

> **注意：N16R8模组的GPIO22~32、GPIO33~37均不可用（被Octal SPI Flash/PSRAM占用）**

| 模块 | 信号 | GPIO |
|------|------|------|
| INMP441 SCK | I2S_SCK | IO14 |
| INMP441 WS | I2S_WS | IO15 |
| INMP441 SD | I2S_SD | IO16 |
| MAX98357A BCLK | I2S_BCLK | IO17 |
| MAX98357A LRC | I2S_LRC | IO18 |
| MAX98357A DIN | I2S_DOUT | IO8 |
| ST7789 SCK | SPI_SCK | IO12 |
| ST7789 MOSI | SPI_MOSI | IO11 |
| ST7789 DC | SPI_DC | IO10 |
| ST7789 CS | SPI_CS | IO9 |
| ST7789 RST | SPI_RST | IO46 |
| MPU6050 SDA | I2C_SDA | IO5 |
| MPU6050 SCL | I2C_SCL | IO6 |
| MPU6050 INT | 中断 | IO4 |
| 触摸主板 | TOUCH_MAIN | IO7 |
| 触摸备用 | TOUCH_UP | IO1 |
| 触摸备用 | TOUCH_DOWN | IO2 |
| 触摸备用 | - | IO3, IO13 |
| WS2812B | LED_DIN | IO38 |
| USB | D- / D+ | IO19 / IO20 |

---

*创建日期: 2026-02-05 | 最后更新: 2026-02-25*
