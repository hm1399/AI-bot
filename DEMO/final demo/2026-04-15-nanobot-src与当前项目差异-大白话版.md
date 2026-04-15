# nanobot-src 和当前项目，到底差在哪

> 说明：这份对比是按 `2026-04-15` 仓库里的真实代码来写的，不把纯规划当成功能。

## 先说最简单的一句话

`nanobot-src` 更像一个通用 AI agent 底盘。

当前这个项目，已经不是单纯“把 nanobot 搬过来”了，而是把它改造成了一个给 `AI-Bot` 这个具体产品服务的系统：前面接机器人硬件，旁边接 Flutter 桌面 App，后面再挂上任务、提醒、日历、电脑控制和运行态管理。

所以如果用很大白话来讲：

- `nanobot-src`：像一个通用发动机和底盘
- 当前项目：像一台已经装上外壳、方向盘、仪表盘、音响和专用功能的整车

## 1. 原版 nanobot-src 是什么

从 `nanobot-src/README.md` 和目录结构看，原版 nanobot 的定位很明确：

- 它是一个超轻量、通用型的个人 AI assistant 框架
- 核心目标是让你快速跑起一个 agent
- 主要入口是命令行和通用聊天渠道

原版最典型的东西是这些：

- `python -m nanobot`
- `nanobot onboard`
- `nanobot agent`
- `nanobot gateway`

它本身已经带很多通用能力：

- 多聊天渠道
  - Telegram
  - Discord
  - WhatsApp
  - Feishu
  - Slack
  - QQ
  - Email
  - DingTalk
  - Matrix
  - Mochat
- 多 provider
- 通用工具
  - shell
  - filesystem
  - web
  - cron
  - mcp
  - spawn
- 一套默认模板和技能包
  - `templates/`
  - `skills/`

所以原版 nanobot 的重点是：`做一个通用、轻量、可接很多平台的 agent 框架。`

## 2. 当前项目是什么

当前项目的目标已经完全不是“做一个通用 AI agent 框架”了。

它更像是在 nanobot 内核上，做了一个具体产品：

- 有机器人硬件
- 有本地服务端
- 有 Flutter 桌面端
- 有设备配对流程
- 有任务 / 日历 / 提醒
- 有结构化电脑控制
- 有物理交互和场景 / 人格

而且当前项目的顶层目录已经很能说明问题：

- `server/`
- `app/`
- `firmware/`
- `DEMO/`
- `原理图设计/`
- `硬件设计文件/`

这些东西在原版 `nanobot-src` 里都没有。

也就是说，当前项目已经不是“一个 AI 框架仓库”，而是“一个软硬件一体的产品仓库”。

## 3. 当前项目比原版 nanobot 多了什么

这部分是最能体现“已经不是原版 nanobot” 的地方。

### 3.1 多了一整条机器人硬件链路

原版 nanobot 主要面向 CLI 和聊天软件。

当前项目多了完整的设备链路：

- `server/channels/device_channel.py`
- `server/models/device_state.py`
- `server/models/protocol.py`
- `firmware/arduino/demo/`

这代表当前项目已经在处理这些原版没有的东西：

- ESP32 设备 WebSocket 通信
- 设备状态机
- 麦克风音频上行
- 屏幕显示
- 设备命令回传
- 触摸 / 摇一摇这类物理事件

大白话说，原版 nanobot 是“聊天软件里回消息”，当前项目是“真的要和一个桌面硬件机器人打交道”。

### 3.2 多了语音输入输出产品层，不只是文本 agent

原版 nanobot 的主视角还是文本 agent。

当前项目专门加了：

- `server/services/asr.py`
- `server/services/tts.py`
- `server/services/desktop_voice_service.py`

这意味着当前项目在做：

- 本地语音识别
- 文本转语音
- 桌面麦克风桥接
- 设备和桌面端协同的语音路径

简单讲，原版 nanobot 更像“打字聊天”；当前项目已经变成“语音是主链路之一”。

### 3.3 多了 Flutter 桌面 App，不只是聊天入口

原版 nanobot 没有这一层。

当前项目有完整 Flutter 工程 `app/`，而且不是空壳，已经有这些页面：

- Connect
- Home
- Chat
- Agenda
- Tasks
- Control Center
- Settings
- Demo Mode

这说明当前项目已经不是“AI 在某个聊天窗口里回复你”，而是“有一个桌面工作台来管理整个系统”。

### 3.4 多了机器人首次配对和设备配置流程

原版 nanobot 不需要考虑“给机器人配 WiFi、写回局域网地址”这件事。

当前项目专门做了：

- `app/lib/widgets/connect/device_pairing_panel.dart`
- `app/lib/providers/device_pairing_controller.dart`
- `server/services/app_runtime.py` 里的 `device/pairing/bundle`

也就是说，当前项目不仅要让 AI 跑起来，还要处理真实设备第一次怎么接进系统。

### 3.5 多了任务、日历、提醒这整套 planning 产品层

原版 nanobot 有 cron 和通用调度思路，但没有当前这么完整的产品面。

当前项目明显加了完整 planning 系统：

- `server/services/planning_runtime_service.py`
- `server/services/planning/`
- `server/services/reminder_scheduler.py`
- `server/services/app_api/`
- Flutter 里的 `Tasks` / `Agenda` 页面

现在这个项目里已经有：

- task
- event
- reminder
- planning overview
- planning timeline
- planning conflicts
- planning bundle

大白话说，原版 nanobot 能帮你做事；当前项目开始管“这些事怎么被排进去、怎么提醒、怎么展示”。

### 3.6 多了结构化电脑控制，不再只是随便 exec

原版 nanobot 有通用工具，偏“你给 agent 一把万能刀”。

当前项目多了一整套结构化电脑控制：

- `server/services/computer_control/`
- `server/nanobot/agent/tools/computer_control.py`
- Flutter `Control Center`

现在项目里电脑控制已经变成这种产品化形态：

- action request
- risk level
- requires confirmation
- pending approvals
- recent actions
- allowlist
- permission hints

这和原版“通用工具式调用”很不一样。

大白话说：

- 原版更像“agent 自己想办法调工具”
- 当前项目更像“先把电脑动作包装成可审计、可确认、可限制的产品能力”

### 3.7 多了场景模式、人格和物理交互

原版 nanobot 没有这套明显的产品人格层。

当前项目里已经有：

- `server/services/experience/`
- `app/lib/models/experience/experience_model.dart`
- Chat 里的 scene / persona 切换
- Control Center 里的 physical interaction 面板

现在这套项目已经在处理：

- Focus / Off Work / Meeting
- persona preset
- shake routing
- tap confirmation
- hold-to-talk readiness

这很明显是“陪伴式硬件产品”的方向，而不是通用 agent 框架默认会做的事。

### 3.8 多了运行态观测和产品化接口

原版 nanobot 主要靠 CLI 和 gateway 跑起来。

当前项目多了大量产品化 API 和运行态投影：

- `server/services/app_runtime.py`
- `server/services/runtime_projection_service.py`
- `server/services/app_realtime_hub.py`

而且不是几个接口而已，是整套 `app-v1`：

- bootstrap
- settings
- sessions
- messages
- tasks
- events
- notifications
- reminders
- planning
- runtime state
- computer state
- device state
- capabilities
- websocket app events

这说明当前项目已经从“能跑的 agent”变成“可以被桌面端长期消费的一套产品后端”。

## 4. 当前项目把原版 nanobot 改了什么

这部分不是“加功能”，而是“把原版内核往产品方向掰了”。

### 4.1 启动方式改了

原版 nanobot 的典型入口是：

- `python -m nanobot`
- `nanobot agent`
- `nanobot gateway`
- `nanobot onboard`

当前项目的主入口已经变成：

- `server/main.py`
- `server/bootstrap.py`
- `server/config.yaml`

也就是说，当前项目不再强调“一个通用 CLI 工具怎么启动”，而是强调“AI-Bot 这个系统怎么启动”。

### 4.2 配置方式改了

原版 nanobot 更偏 `~/.nanobot/config.json` 这种通用用户级配置。

当前项目改成了项目本地配置：

- `server/config.yaml`

这里面直接写产品相关配置，比如：

- device auth
- app auth
- weather
- computer_control
- transport
- storage

这说明当前项目已经从“给任何人都能用的 agent”变成“给这个项目自己服务的本地系统”。

### 4.3 内核里加了项目专属 tool

对比目录就能看到，当前项目在 `server/nanobot/agent/tools/` 里新增了原版没有的两块：

- `planning.py`
- `computer_control.py`

这说明当前项目不是只在 nanobot 外面套一层，而是已经把产品能力直接塞回 agent 工具层了。

### 4.4 会话和存储被改得更重了

原版 nanobot 更轻。

当前项目里会话和存储明显被增强了：

- `server/nanobot/session/sqlite_backend.py`
- `server/nanobot/session/jsonl_importer.py`
- `server/nanobot/storage/`
- `server/nanobot/utils/atomic_write.py`

再结合 `server/config.yaml` 里的：

- `session_storage_mode: dual`
- `planning_storage_mode: dual`

可以看出来，当前项目已经在做更偏产品和稳定性的存储方案，而不是只追求“极简能跑”。

### 4.5 消息总线也被改成了更偏生产化的版本

原版 `nanobot-src/nanobot/bus/queue.py` 很简单，本质上就是两个普通 `asyncio.Queue`。

当前项目的 `server/nanobot/bus/queue.py` 已经明显更复杂，开始处理：

- bounded queue
- reserved slots
- priority traffic
- observer queue
- metrics snapshot

大白话说，原版像一条普通小路，当前项目已经开始修成有车道、有限流、带监控的路了。

## 5. 当前项目相对原版，也删掉或收掉了什么

这部分也要说，不然会误以为当前项目是“原版 nanobot 全保留，再叠加一堆功能”。实际不是。

### 5.1 原版那套通用 CLI 入口，当前项目基本不走主线了

原版有：

- `nanobot/__main__.py`
- `nanobot/cli/commands.py`

当前项目 vendored 的 `server/nanobot/` 里，这块已经不保留成主路径了。

意思就是：当前项目不再把自己当成一个“给大家安装的通用 CLI 产品”。

### 5.2 原版自带的大量默认 skills / templates 被收掉了

原版 nanobot 有：

- `nanobot/skills/`
- `nanobot/templates/`

当前项目本地 vendored 的 `server/nanobot/` 里，这套原版公共技能包和模板基本没继续保留在主线里。

当前项目更像是：

- 保留需要的 agent 内核
- 再在 `server/workspace/` 放自己项目真正要用的内容

大白话说，就是从“开放通用工具箱”收成“这个产品自己要用的那几把工具”。

### 5.3 一些原版 provider 能力被裁掉了

从目录对比看，原版有这些 provider 文件：

- `custom_provider.py`
- `openai_codex_provider.py`
- `transcription.py`

当前项目本地 vendored 版本里，这些不再是主路径能力。

这也符合当前项目定位：它不是在追求“支持尽量多 provider 花样”，而是在追求“当前产品主链路稳定可控”。

### 5.4 heartbeat 这类原版通用模块被拿掉了

原版有：

- `nanobot/heartbeat/`

当前项目 vendored 版本里没有保留这套原样结构。

这说明当前项目没有照搬原版所有机制，而是保留自己当前产品链路真正在用的那部分。

## 6. 真正的核心差异，不是“多几个文件”，而是定位变了

如果只看代码文件，很容易变成“这里多了几个模块，那里少了几个模块”。

但真正重要的差异其实是这句：

`原版 nanobot 是通用 AI agent 框架，当前项目是基于它深度改造出来的 AI-Bot 产品系统。`

这个定位变化会导致所有后果都不一样：

- 原版强调通用、轻量、可接很多渠道
- 当前项目强调本地设备、桌面工作台、产品闭环、稳定运行

所以当前项目并不是“把 nanobot 下载下来再加几个脚本”。

更准确的说法应该是：

`当前项目把 nanobot 当成了 agent 内核，但已经在它外面和里面都做了很深的产品化改造。`

## 7. 如果非要用一句最口语的话总结

可以直接这么讲：

`nanobot-src 像一个通用 AI 助手底盘，谁都能拿去改。`

`当前项目则是把这个底盘改装成了一台专门给 AI-Bot 机器人和桌面工作台服务的整车。`

## 8. 最后给一个最短版结论

如果你只想记一句：

`当前项目不是“原版 nanobot”，而是“拿 nanobot 当内核，重新做成了一个带硬件、带 Flutter App、带任务提醒日历、带结构化电脑控制的产品系统”。`
