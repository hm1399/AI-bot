# AI-Bot 15分钟 Presentation 文稿

> 版本基准：`2026-04-20` 当前仓库真实实现状态  
> 适用场景：课程 project presentation  
> 建议页数：`18 页`  
> 建议总时长：`约 15 分钟`

## 这份文稿怎么用

- 每一页都按 `页内要点 + 建议素材 + 讲稿提示 + 时长` 来写。
- `页内要点` 适合直接放到 PPT 上。
- `讲稿提示` 是你现场讲的时候的提词，不建议逐字读。
- 整体口径遵循 `presentation/这次Presentation要求-中文版.md`：重点讲清楚问题、方案、方法、结果、亮点和边界。

## 本文稿主要依据

- `Project_proposal/Project_Proposal.md`
- `CHANGELOG.md`
- `功能讨论区/架构.md`
- `DEMO/final demo/2026-04-15-导师demo流程-实体机器人+FlutterApp版.md`
- `DEMO/final demo/2026-04-15-最新demo对比上一次demo-大白话版.md`
- `DEMO/final demo/2026-04-15-nanobot-src与当前项目差异-大白话版.md`
- `app/lib/config/routes.dart`
- `server/main.py`
- `server/bootstrap.py`
- `server/services/app_runtime.py`
- `server/services/planning_runtime_service.py`
- `server/services/computer_control/service.py`
- `server/services/experience/service.py`
- `server/config.yaml`

## 整体叙事主线

- 我们发现传统语音助手不适合桌面电脑控制，也缺少一个真正“摆在桌上”的 AI 入口。
- 所以我们做了一个软硬件一体的桌面 AI 助手：有实体机器人、有本地服务端、有 Flutter 桌面工作台。
- 它不只会聊天，还能把对话落成任务、提醒、日历和结构化电脑动作。
- 当前版本已经完成主链路联调，并进入产品骨架成型阶段。

---

## Slide 01 标题页

### 页内要点

- `AI-Bot`
- `A Desktop AI Assistant with Physical Device, Voice Interaction, and Structured Computer Control`
- 课程名、组员名、学号
- 一句副标题：`An integrated AI assistant system combining hardware, backend orchestration, and a desktop app workspace.`

### 建议展示素材

- 一张实体硬件照片
- 或者硬件照片 + App 界面拼图
- 可优先从 `images/焊板/` 挑 1 张最清晰的板子照片

### 讲稿提示

- 开场先不要直接讲技术细节。
- 先用一句话定义项目：`我们做的不是单纯聊天机器人，而是一个放在桌面上、能和电脑协同工作的 AI 助手系统。`

### 建议时长

- `30 秒`

---

## Slide 02 场景与问题

### 页内要点

- 桌面场景里，用户经常重复做这些动作：
- 打开应用、找文件、查看提醒、切换任务、查询状态
- 现有语音助手大多：
- 偏云端
- 不直接面向个人电脑操作
- 缺少实体交互入口和即时状态反馈
- 我们想解决的问题：
- `如何做一个真正适合桌面场景的 AI 助手，而不只是一个聊天窗口？`

### 建议展示素材

- 一张“桌面工作流”示意图
- 或者简单列出用户日常场景：工作、会议、专注、休息

### 讲稿提示

- 强调项目不是为了“做一个会说话的硬件”。
- 真正的问题是：桌面用户需要一个更自然、更低摩擦、更可见的 AI 入口。

### 建议时长

- `45 秒`

---

## Slide 03 现有方案为什么不够

### 页内要点

- 商业语音助手的问题：
- 更偏家庭场景，不擅长个人电脑控制
- 云端依赖重，隐私感知弱
- 纯软件助手的问题：
- 没有专用物理入口
- 缺少屏幕、触摸、状态反馈等“设备感”
- 我们需要的是：
- 一个桌面摆件形态的 AI 助手
- 能连接电脑、管理任务、接受物理交互

### 建议展示素材

- 左右对比图：`Smart Speaker` vs `Software-only Assistant` vs `AI-Bot`

### 讲稿提示

- 这页要把“为什么要做这个项目”讲透。
- 老师要先相信这个问题有价值，后面方案才有说服力。

### 建议时长

- `45 秒`

---

## Slide 04 我们的目标与项目定位

### 页内要点

- 我们的目标不是单点功能，而是一整套系统：
- 一个实体 AI 设备
- 一个本地服务端编排层
- 一个 Flutter 桌面工作台
- 目标能力包括：
- 语音交互
- 任务 / 提醒 / 日历管理
- 结构化电脑控制
- 场景模式与人格切换
- 设备控制与状态可视化

### 建议展示素材

- 三段式结构图：`Device / Backend / App`

### 讲稿提示

- 可以直接说：`我们做的其实不是一个 demo，而是一套正在成型的产品骨架。`

### 建议时长

- `40 秒`

---

## Slide 05 系统总览

### 页内要点

- 硬件端：ESP32-S3 设备
- 服务端：Python 本地后端
- 桌面端：Flutter App
- 当前主链路：
- 设备触发交互
- 服务端做 AI 编排
- App 实时同步状态与结果
- 支持 planning 和 computer control 两条业务能力线

### 建议展示素材

- 直接画一个总框图：
- `ESP32-S3 device -> Python backend -> Flutter App`
- 可加 `planning`、`computer control`、`experience` 三个业务模块

### 讲稿提示

- 这页先讲“整体是什么”，不要一上来就讲实现细节。
- 让听众脑子里先有系统轮廓。

### 建议时长

- `50 秒`

---

## Slide 06 Selected Hardware Components

### 页内要点

- main controller: ESP32-S3-WROOM-1-N16R8, WiFi, memory capacity, and embedded control
- digital microphone: INMP441, stable I2S audio capture
- amplifier: MAX98357, compact digital playback
- speaker: 4Ω 2W speaker, audio output
- display: 1.54-inch ST7789, on-device status and text feedback
- touch input: capacitive touch, press-to-talk and lightweight interaction
- 6-axis sensor: MPU6050, motion sensing and gesture-based input such as shake detection
- battery: 1200mAh Li-ion battery, portable standalone power supply
- power management: TP4056 + TPS631000, battery charging and voltage regulation

### 建议展示素材

- a clean labeled hardware block diagram
- or a component table with function and reason for selection

### 讲稿提示

- This page should clearly answer one question: what hardware did we choose, and why?
- Keep the explanation short and practical, focusing on function, integration, and product fit.

### 建议时长

- `55 秒`

---

## Slide 07 Hardware Realization

### 页内要点

- The selected hardware was turned into a working prototype through:
- schematic design
- PCB layout and routing
- board assembly and soldering
- The prototype integrates:
- audio input and output
- on-device display
- physical sensing and touch interaction
- battery-powered operation

### 建议展示素材

- `images/原理图v2.0/image.png`
- `images/布线v2.0/image.png`
- one clear soldered-board photo from `images/焊板/`

### 讲稿提示

- This page is the bridge between architecture and implementation.
- It shows that the design moved from component selection to a fabricated and assembled hardware prototype.

### 建议时长

- `45 秒`

---

## Slide 08 From Nanobot Demo to Product Backend

### 页内要点

- Started from a `nanobot`-based demo backend
- Reused `AgentLoop`, tool calling, and session memory as the initial core
- Expanded into a local backend for both the desktop app and the device
- Added the ESP32 WebSocket channel and audio pipeline
- Added desktop app APIs and realtime state sync
- Added planning, reminders, calendar, and scheduler
- Added computer control and the experience layer

### 建议展示素材

- a two-column slide: `Inherited from nanobot` on the left, `Built for AI-Bot` on the right
- or a simple evolution arrow: `nanobot demo -> AI-Bot product backend`

### 讲稿提示

- Explain this page as an evolution path, not as a technical deep dive.
- The key message is that nanobot gave us a fast starting point, but the current backend already includes substantial product-specific extensions.

### 建议时长

- `45 秒`

---

## Slide 09 Backend Architecture

### 页内要点

- deployment: local LAN backend, desktop app and device connect to the same server
- connection: aiohttp + WebSocket, HTTP APIs for app data and WebSocket for realtime updates
- device channel: backend-to-device WebSocket bridge
- desktop app channel: realtime state sync for the desktop client
- llm: OpenRouter, `x-ai/grok-4.1-fast`
- local task execution: CLI tools, the LLM can help users execute tasks on the computer
- database: SQLite + dual storage, sessions and planning data persistence
- asr: `FunAudioLLM/SenseVoiceSmall`, server-side speech-to-text
- tts: `edge-tts`, default voice `en-US-AriaNeural` for reply synthesis
- agent and services: `nanobot AgentLoop` + planning + computer control, task handling and desktop actions

### 建议展示素材

- a simple system diagram: Desktop App / Device / Local Backend / LLM / ASR / TTS
- or a short table with module, protocol, and model

### 讲稿提示

- Keep this page simple: where the backend runs, how the desktop app and device connect, and which models are used.
- Avoid going too deep into internal service names unless someone asks.

### 建议时长

- `60 秒`

---

## Slide 10 End-to-End Interaction Flow

### 页内要点

- Stable demo path for the current version
- Press and speak on the device
- Audio is captured by the desktop microphone
- The backend runs `ASR -> AgentLoop -> TTS`
- The device provides status feedback, screen updates, and voice playback
- This architecture prioritizes reliability during product validation
- The device remains the primary interaction entry point and feedback terminal

### 建议展示素材

- 流程图：
- `Press on device -> Desktop mic capture -> ASR -> AgentLoop -> TTS -> Device display & speaker -> App sync`

### 讲稿提示

- 这里一定要口径准确。
- 不要说成“完全靠设备本地麦克风直采”，当前稳定 demo 主线不是这个。
- 反而可以把这点讲成：`我们在产品验证阶段优先选了更稳定的主链路。`

### 建议时长

- `60 秒`

---

## Slide 11 Flutter 桌面工作台

### 页内要点

- 当前 App 已有正式路由和工作台结构：
- `Connect`
- `Home`
- `Chat`
- `Agenda`
- `Tasks`
- `Control Center`
- `Settings`
- 它的意义不是“再做一个界面”
- 而是把机器人、AI、planning、设备控制整合成可操作工作台

### 建议展示素材

- 一页拼 4 张截图：
- Connect
- Home
- Chat
- Tasks / Agenda / Control Center 任意两张

### 讲稿提示

- 这页是“从硬件样机走向产品”的关键证据。
- 可以直接说：`这次和上一次 demo 最大不同，就是我们已经不再只有硬件和聊天结果，而是有一个真正的桌面工作台。`

### 建议时长

- `55 秒`

---

## Slide 12 会话型聊天与体验层

### 页内要点

- Chat 已不只是单轮问答：
- 多会话列表
- 新建 / 改名 / 置顶 / 归档
- 当前会话切换
- Experience 层已经接入：
- `scene`
- `persona`
- `physical interaction readiness`
- 当前场景包括：
- `Focus / Off Work / Meeting`

### 建议展示素材

- Chat 页面截图
- 或者会话列表 + scene/persona chip bar 的组合图

### 讲稿提示

- 强调 AI 不再是“固定一个说话风格”。
- 项目已经在往“同一个 AI，根据场景和人格切换交互方式”发展。

### 建议时长

- `55 秒`

---

## Slide 13 Planning 能力：任务、提醒、日历

### 页内要点

- 当前系统不只会回答问题，也会把事情落进系统：
- `Tasks`
- `Events`
- `Reminders`
- planning 相关能力包括：
- overview
- timeline
- conflicts
- bundle create
- 前端已经有 `Agenda` 和 `Tasks` 两个核心工作页面

### 建议展示素材

- Agenda 页面截图
- Tasks 页面截图
- 再配一个 “chat -> planning item” 的箭头示意

### 讲稿提示

- 这页一定要突出“从聊天到事情管理”的升级。
- 你可以说：`我们希望 AI 不只是回答一句“好的”，而是真的把事情组织起来。`

### 建议时长

- `60 秒`

---

## Slide 14 Reminder Scheduler 与运行态汇总

### 页内要点

- 提醒现在不只是存一条数据
- 后端已经有真实调度器：
- `sync`
- `snooze`
- `complete`
- `reconcile`
- 同时系统会生成：
- `todo summary`
- `calendar summary`
- planning overview 和 runtime state 会推送到 App

### 建议展示素材

- 一张 reminder 生命周期图
- 或者用 4 个词直接画流程：`create -> schedule -> trigger/snooze -> complete`

### 讲稿提示

- 这页体现“系统性”。
- 老师听到这里会感觉你们不是只做界面，而是在做后台运行逻辑。

### 建议时长

- `50 秒`

---

## Slide 15 结构化电脑控制与安全设计

### 页内要点

- 电脑控制不是直接把所有 shell 暴露给用户
- 我们做了结构化 action 层
- 当前支持的动作包括：
- `open_app`
- `open_path`
- `open_url`
- `run_shortcut`
- `run_script`
- `system_info`
- 设计重点：
- allowlist
- 风险分级
- confirm / cancel
- pending approvals
- recent actions

### 建议展示素材

- Control Center 中 computer action 面板截图
- 或者风险分级小图：`low / medium / high`

### 讲稿提示

- 这页要说明你们不是为了炫技而做“AI 乱控电脑”。
- 你们是把电脑控制做成了有边界、有确认、有策略的产品能力。

### 建议时长

- `60 秒`

---

## Slide 16 配网流程与物理交互

### 页内要点

- 当前项目不只是“开发者提前配好再演示”
- Connect 页面已经做出三步式流程：
- backend connection
- USB pairing
- WiFi / host bundle 下发
- 设备交互也不只是一颗按钮：
- hold-to-talk
- tap confirmation
- shake routing
- scene / persona 会影响物理交互策略

### 建议展示素材

- Connect 页面截图
- Physical Interaction 面板截图

### 讲稿提示

- 这页体现“产品化程度”。
- 以前更像研究者自己能跑起来；现在开始往“别人按流程也能接起来”走。

### 建议时长

- `55 秒`

---

## Slide 17 当前可展示成果

### 页内要点

- 当前已经能展示一条完整主线：
- 设备在线
- Chat 同步
- 场景 / 人格切换
- 语音或文本生成任务 / 提醒
- 在 Tasks / Agenda 中落地
- 控制中心查看设备与电脑动作状态
- 这说明项目已经具备“系统级联动”的演示价值

### 建议展示素材

- 用一页流程图总结 demo：
- `Robot input -> AI response -> App sync -> Planning landing -> Computer / device action`

### 讲稿提示

- 这一页和真正 demo 的关系最强。
- 你可以说：`我们现在展示的不是零散功能，而是一条完整产品主线。`

### 建议时长

- `55 秒`

---

## Slide 18 这次版本相比早期 demo 的进展

### 页内要点

- 早期 demo 更像：
- 一个能说话、能显示、能简单控电脑的硬件样机
- 当前版本更像：
- 一个软硬件一体的桌面 AI 助手系统
- 具体提升体现在：
- 从设备优先的功能演示，发展到 Flutter 工作台
- 从单轮聊天，发展到会话管理
- 从即时回复，发展到 planning 系统
- 从简单控制，发展到结构化 computer control
- 从开发者手工准备，发展到配网与连接流程

### 建议展示素材

- 左右对比页：
- `Previous Demo`
- `Current Demo`

### 讲稿提示

- 这页很适合体现“这段时间做了很多真实工作”。
- 但不要说成“全部完成”，而是说“产品骨架已经成型”。

### 建议时长

- `55 秒`

---

## Slide 19 当前边界、反思与下一步

### 页内要点

- 我们当前不会夸太满，仍有边界：
- App 原生语音采集链路还未完全闭环
- wake word / auto listen 还不能按已完成能力宣传
- 外部日历同步、推送通知等更高层能力还没完全打通
- 个别硬件外围项仍在收尾
- 但当前已经完成最重要的事：
- 软硬件一体主链路跑通
- 产品核心模块成型
- 后续迭代方向明确

### 建议展示素材

- 三列结构：
- `What works now`
- `What is still limited`
- `What we will do next`

### 讲稿提示

- 最后一页一定要诚实。
- 老师往往更认可“知道自己做到哪、还差哪”的团队。
- 收尾句建议用：
- `我们认为这个项目已经从功能验证进入产品成型阶段，下一步重点是把未闭环能力继续收口，而不是推翻重来。`

### 建议时长

- `60 秒`

---

## 结尾可直接讲的一句话

`AI-Bot 的核心价值，不只是把 AI 放进一个硬件里，而是把桌面场景下的语音交互、任务组织、设备反馈和电脑控制整合成一个真正可操作的系统。`

## 制作 PPT 时的版式建议

- 不要一页塞太多字，每页保留 `3-5` 个核心点就够。
- 多放系统图、流程图、界面截图、硬件照片，少放大段文字。
- 颜色保持统一，避免背景过花。
- 每页都要让老师一眼看懂“这页在讲什么”。
- 讲的时候按这条顺序推进：
- `为什么做 -> 做了什么 -> 怎么做 -> 做出来了什么 -> 还有什么没做完`

## 口径提醒

- 不要把 `README.md` 里一些旧描述当成当前状态直接讲。
- 当前 presentation 更适合以最新代码和 `DEMO/final demo/` 的口径为准。
- 特别注意这三点：
- 当前稳定语音主线是 `设备按住说话 + 桌面麦克风代采`
- WhatsApp 不是当前主展示链路
- App 已经不是“开发中占位”，而是有真实工作台结构
