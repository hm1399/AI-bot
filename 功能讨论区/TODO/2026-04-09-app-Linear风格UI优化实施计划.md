# app Linear 风格 UI 优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依据 `app/DESIGN.md` 将 Flutter 前端改造成更接近 Linear 的桌面控制台，同时保留当前全部功能和按钮，并补上少量高价值但当前缺失的操作入口。

**Architecture:** 这次改造以 `frontend-first` 为主，优先通过主题系统、响应式壳层、页面重排和现有 API 能力补齐来完成。后端 `app-v1` 已经覆盖 bootstrap、chat、tasks/events、notifications/reminders、runtime stop、device commands、todo/calendar summaries 和 capabilities，因此主改造不需要先扩后端接口；只在确有必要时补最小状态解析或 provider/service 封装。

**Tech Stack:** Flutter, Material 3, hooks_riverpod, go_router, aiohttp app-v1 API, WebSocket events, Markdown

---

## 调研结论

- `app/lib/main.dart` 仍使用默认 `ColorScheme.fromSeed(...)`，距离 `app/DESIGN.md` 的 Linear 深色 token 体系差距很大。
- `app/lib/widgets/common/app_scaffold.dart` 现在是顶部状态横条加底部 `NavigationBar`，适合保留五个入口，但桌面端还没有 Linear 风格的紧凑侧边壳层。
- 五个主页面都已经有真实功能，不是 placeholder。后续重构必须保全现有交互，不允许“为了美观删按钮”。
- 后端 `server/services/app_runtime.py` 已提供一批前端尚未充分利用的能力，包括 `DELETE /api/app/v1/notifications`、`GET/POST /api/app/v1/runtime/todo-summary`、`GET/POST /api/app/v1/runtime/calendar-summary`、`GET /api/app/v1/capabilities`。
- 设备控制首轮不应臆造新命令。当前后端明确支持的 app command 只有 `mute`、`toggle_led`、`wake`、`sleep`、`set_volume`、`set_led_color`、`set_led_brightness`。
- 聊天会话目前只有读取、创建、切换和发消息接口，没有 pin/archive/rename 的写接口，因此首轮 UI 不应加入这些不可落地按钮。

## 现有功能保全矩阵

- `Connect`: `Try Demo Mode`、`Use Current Page Origin(web)`、`Validate Connection`、Host/Port/Token/HTTPS 输入。
- `Shell`: 顶部连接状态条、`home/chat/tasks/control/settings` 五个入口。
- `Home`: 运行态刷新、`Speak`、`Stop`、设备快照、当前任务、Todo Summary、Calendar Summary。
- `Chat`: 会话列表唤起、会话刷新、创建会话、发送消息、语音提示按钮。
- `Tasks`: `Tasks/Events` 切换、刷新、`Add Task/Event`、编辑、完成切换、删除。
- `Control`: 刷新、`Speak`、`Sync Runtime`、发送音量/亮度/颜色、`Wake`、`Sleep`、`Mute`、通知已读/删除、提醒新增/启停/编辑/删除。
- `Settings`: `Save Settings`、`Test AI Connection`、现有全部配置字段和状态提示。

## 新增功能边界

- 本轮允许新增高价值按钮和轻量功能，但必须建立在现有后端能力或明确的前端本地能力上。
- 推荐纳入首轮的新增项：全局 `Disconnect`、全局 `Refresh All`、控制中心 `Clear All Notifications`、设备 `Toggle LED`、聊天页 `Copy Session ID`、设置页 `Reset Draft`、任务与事件的本地筛选/搜索。
- 首轮不纳入：会话 pin/archive/rename 写操作、设备 `unmute`、唤醒词真实启用、app 内直接录音。

## 计划文件结构映射

- Create: `app/lib/theme/linear_tokens.dart`
- Create: `app/lib/theme/linear_theme.dart`
- Create: `app/lib/widgets/common/app_shell_header.dart`
- Create: `app/lib/widgets/common/app_sidebar.dart`
- Create: `app/lib/widgets/common/app_bottom_dock.dart`
- Create: `app/lib/widgets/common/status_pill.dart`
- Create: `app/lib/widgets/home/overview_stat_card.dart`
- Create: `app/lib/widgets/home/runtime_queue_panel.dart`
- Create: `app/lib/widgets/chat/chat_session_panel.dart`
- Create: `app/lib/widgets/chat/voice_handoff_card.dart`
- Create: `app/lib/widgets/tasks/task_filter_bar.dart`
- Create: `app/lib/widgets/control/notification_panel.dart`
- Create: `app/lib/widgets/control/reminder_panel.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/widgets/common/app_scaffold.dart`
- Modify: `app/lib/screens/connect/connect_screen.dart`
- Modify: `app/lib/screens/home/home_screen.dart`
- Modify: `app/lib/widgets/home/device_card.dart`
- Modify: `app/lib/screens/chat/chat_screen.dart`
- Modify: `app/lib/widgets/chat/message_input.dart`
- Modify: `app/lib/widgets/chat/message_bubble.dart`
- Modify: `app/lib/screens/tasks/tasks_screen.dart`
- Modify: `app/lib/screens/control_center/control_center_screen.dart`
- Modify: `app/lib/screens/settings/settings_screen.dart`
- Modify: `app/lib/widgets/settings/settings_form.dart`
- Modify: `app/lib/providers/app_providers.dart`
- Modify: `app/lib/models/connect/bootstrap_model.dart`
- Modify: `app/lib/constants/api_constants.dart`
- Modify: `app/lib/services/bootstrap/bootstrap_service.dart`
- Modify: `app/lib/services/home/runtime_service.dart`
- Modify: `app/lib/services/notifications/notifications_service.dart`

### Task 1: Linear 主题基建与响应式主壳层

**Files:**
- Create: `app/lib/theme/linear_tokens.dart`
- Create: `app/lib/theme/linear_theme.dart`
- Create: `app/lib/widgets/common/app_shell_header.dart`
- Create: `app/lib/widgets/common/app_sidebar.dart`
- Create: `app/lib/widgets/common/app_bottom_dock.dart`
- Create: `app/lib/widgets/common/status_pill.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/widgets/common/app_scaffold.dart`

- [x] Step 1: 将 `app/DESIGN.md` 中的深色 token、字体、边框、圆角和状态色转成 Flutter 主题常量与 `ThemeData`。
- [x] Step 2: 在 `main.dart` 接入新的深色主题，替换默认 seed theme，统一 `Scaffold/Card/Input/NavigationBar/Dialog` 的视觉语义。
- [x] Step 3: 把主壳层改成桌面端 `NavigationRail/Sidebar`、移动端底部 dock 的响应式布局，同时保留五个入口名称和顺序。
- [x] Step 4: 保留现有顶部连接状态可见性，但改成更接近 Linear 的紧凑 header，显示连接、事件流、demo 状态。
- [x] Step 5: 在主壳层加入新增的全局操作入口：`Disconnect`、`Refresh All`、当前连接详情入口；这些入口不能替代现有页面内按钮，只能补充。

### Task 2: 状态面板与服务封装补齐

**Files:**
- Modify: `app/lib/providers/app_providers.dart`
- Modify: `app/lib/models/connect/bootstrap_model.dart`
- Modify: `app/lib/constants/api_constants.dart`
- Modify: `app/lib/services/bootstrap/bootstrap_service.dart`
- Modify: `app/lib/services/home/runtime_service.dart`
- Modify: `app/lib/services/notifications/notifications_service.dart`

- [x] Step 1: 扩展 `CapabilitiesModel`，补齐后端已经返回但前端尚未建模的字段，例如 `device_commands`、`desktop_voice`、`settings`、`tasks`、`events`、`notifications`、`reminders`。
- [x] Step 2: 在 provider 层补一个统一的 `refreshAll` 流程，至少覆盖 runtime、sessions、tasks/events、notifications、reminders、settings。
- [x] Step 3: 把 `clearNotifications()` 暴露到 `AppController`，为控制中心新增 `Clear All Notifications` 做好调用链。
- [x] Step 4: 视首页方案需要，为 todo/calendar summary 增加 runtime service 常量与封装，但只在 UI 真的消费时再接入，避免无意义扩面。
- [x] Step 5: 增加壳层和页面会用到的派生状态，例如未读通知数、当前连接显示文案、capability badges、全局 loading/refresh 中状态。

### Task 3: Connect 页改造成 Linear 风格入口台

**Files:**
- Modify: `app/lib/screens/connect/connect_screen.dart`

- [x] Step 1: 将连接页改成深色、居中、紧凑的 operator login/workspace entry 风格，替换当前浅色 Card 观感。
- [x] Step 2: 原样保留 `Try Demo Mode`、`Validate Connection`、Host/Port/Token/HTTPS 和 web `Use Current Page Origin`。
- [x] Step 3: 新增“最近一次连接配置摘要”和“当前 app token/auth 状态”展示，减少用户反复试错。
- [x] Step 4: 将当前“LAN scan removed”提示改成更稳的 muted note 样式，但保留语义，不制造功能已恢复的误解。
- [x] Step 5: 处理连接中、失败、demo、已连接自动跳转四种状态的视觉反馈，使入口页和新主壳风格一致。

### Task 4: Home 改造成真正的运行态总览页

**Files:**
- Create: `app/lib/widgets/home/overview_stat_card.dart`
- Create: `app/lib/widgets/home/runtime_queue_panel.dart`
- Modify: `app/lib/screens/home/home_screen.dart`
- Modify: `app/lib/widgets/home/device_card.dart`

- [x] Step 1: 将首页从单列卡片改成更接近 Linear 的多面板 dashboard，桌面端优先采用 2 列或 3 列布局。
- [x] Step 2: 保留 `Speak`、`Stop`、刷新按钮，并把它们放进明确的 quick actions 区。
- [x] Step 3: 新增 server/version/capabilities/event-stream/connection 信息面板，把现有 `bootstrap` 和 `connection` 状态利用起来。
- [x] Step 4: 新增 runtime queue、未读通知、提醒数、任务/事件概览等摘要卡片，让首页能承担真正的“总览入口”角色。
- [x] Step 5: 将 `Todo Summary` 和 `Calendar Summary` 从普通 `ListTile` 提升为更可扫描的指标卡，但继续明确 backend enabled/not ready 口径。

### Task 5: Chat 改造成双栏工作区

**Files:**
- Create: `app/lib/widgets/chat/chat_session_panel.dart`
- Create: `app/lib/widgets/chat/voice_handoff_card.dart`
- Modify: `app/lib/screens/chat/chat_screen.dart`
- Modify: `app/lib/widgets/chat/message_input.dart`
- Modify: `app/lib/widgets/chat/message_bubble.dart`

- [x] Step 1: 桌面端把聊天页改成“会话列表 + 当前会话 + 侧边状态”的工作区布局，移动端再退化回单列。
- [x] Step 2: 保留会话刷新、新建、切换、发送、语音提示按钮，不允许减少任何现有入口。
- [x] Step 3: 新增 `Copy Session ID` 和当前会话摘要的更清晰展示，方便调试和对接后端。
- [x] Step 4: 重做消息气泡、输入框、顶部会话信息和 Voice Handoff 卡片，使其符合 `DESIGN.md` 的紧凑深色风格。
- [x] Step 5: 不新增 pin/archive/rename 这类没有后端写接口支撑的按钮，只展示只读 metadata 即可。

### Task 6: Tasks 与 Events 页做成高密度列表工作台

**Files:**
- Create: `app/lib/widgets/tasks/task_filter_bar.dart`
- Modify: `app/lib/screens/tasks/tasks_screen.dart`

- [x] Step 1: 保留 `Tasks/Events` 切换、刷新、新增、编辑、删除、完成切换等全部现有动作。
- [x] Step 2: 新增本地筛选与搜索能力，例如 `Open/Completed`、`High Priority`、`Due Soon`、`Today/Upcoming`，不依赖后端新增接口。
- [x] Step 3: 将当前单纯 `Card + ListTile` 重排为更紧凑的列表行与详情信息布局，增强到期时间、优先级、完成状态的可扫描性。
- [x] Step 4: 为空态、not-ready 和 error 状态设计统一的 muted empty/error panel，保持 Linear 风格并继续保留真实后端口径。
- [x] Step 5: 在桌面布局中为未来扩展右侧详情面板留空间，但首轮不做会导致接口扩面的复杂交互。

### Task 7: Control Center 做成设备与运营控制台

**Files:**
- Create: `app/lib/widgets/control/notification_panel.dart`
- Create: `app/lib/widgets/control/reminder_panel.dart`
- Modify: `app/lib/screens/control_center/control_center_screen.dart`
- Modify: `app/lib/providers/app_providers.dart`

- [x] Step 1: 保留当前全部设备命令、通知和提醒操作，不允许删掉 `Speak`、`Sync Runtime`、音量/亮度/颜色发送以及 `Wake/Sleep/Mute`。
- [x] Step 2: 新增缺失但后端已支持的 `Toggle LED` 和 `Clear All Notifications` 按钮。
- [x] Step 3: 将设备命令区改成更紧凑的 command console 版式，加入设备在线状态、命令支持范围和最近反馈提示。
- [x] Step 4: 把通知和提醒拆成更清晰的独立面板，增强未读、优先级、启停状态和时间信息的层次。
- [x] Step 5: 保证所有新增按钮都只调用现有 provider/service 能力，不引入未实现命令。

### Task 8: Settings 改成稳定的配置工作台

**Files:**
- Modify: `app/lib/screens/settings/settings_screen.dart`
- Modify: `app/lib/widgets/settings/settings_form.dart`

- [x] Step 1: 停止在 `build()` 内临时创建多个 `TextEditingController(text: ...)`，把设置页改成稳定的草稿状态管理。
- [x] Step 2: 将设置页重组为 `LLM`、`Voice/Device`、`Runtime Flags` 三个逻辑区块，保持现有字段完整。
- [x] Step 3: 保留 `Save Settings` 和 `Test AI Connection`，并新增 `Reset Draft` 按钮，避免编辑中途无法回滚。
- [x] Step 4: 增加 `API key configured`、STT/TTS provider/model、wake-word/auto-listen 当前只是配置位等状态说明，使设置页更接近控制台而不是简易表单。
- [x] Step 5: 对 backend not ready、demo、本地草稿未保存等状态设计一致的提示样式。

### Task 9: 收口、验证与人工检查

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/widgets/common/app_scaffold.dart`
- Modify: `app/lib/providers/app_providers.dart`
- Verify: `app/lib/screens/connect/connect_screen.dart`
- Verify: `app/lib/screens/home/home_screen.dart`
- Verify: `app/lib/screens/chat/chat_screen.dart`
- Verify: `app/lib/screens/tasks/tasks_screen.dart`
- Verify: `app/lib/screens/control_center/control_center_screen.dart`
- Verify: `app/lib/screens/settings/settings_screen.dart`

- [ ] Step 1: 按页面回归现有功能保全矩阵，确认没有任何已有按钮、路由、状态提示被删掉。
- [x] Step 2: 在用户确认允许验证后，再执行 `flutter analyze`、必要的 `flutter test` 和桌面端手动 smoke flow。
- [ ] Step 3: 手动核对连接页、demo、五页切换、聊天发消息、任务增删改、控制命令、设置保存与测试连接的完整路径。
- [ ] Step 4: 如实现中发现 README 或其他文档口径与新 UI 明显不一致，再单独征求用户是否补文档，不在本轮擅自扩任务。
