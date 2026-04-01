# Flutter Frontend Alignment With AI-Bot Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不减少现有前端功能的前提下，将当前 React/Vite 原型迁移为位于 `AI-bot/app` 的 Flutter 客户端，并完全对齐 `AI-bot/server` 的接口协议、鉴权方式、事件流模型与后端驱动 AI 回复方案。

**Architecture:** 前端工程根目录固定为 `app/`，后端工程根目录固定为 `server/`。`app/lib` 采用页面优先结构，以 `screens + providers + widgets` 组织 UI 和状态；协议、鉴权、错误映射、事件流恢复等公共底座统一沉到 `services + models + utils`，保证页面结构贴近产品视图、数据结构贴近后端协议。

**Tech Stack:** Flutter, Dart, Riverpod, Dio, web_socket_channel, go_router, freezed/json_serializable, flutter_secure_storage, mocktail/flutter_test

---

## 1. 当前状态与目录结论

- 当前可参考的前端原型主要位于 `AI-bot/APP for BASS 44`，页面和交互较完整，但大量数据来自 mock 或尚未对接的旧接口。
- 新前端唯一工程根目录固定为 `AI-bot/app`，目录形态直接参考标准 Flutter 工程：
  - `app/android`
  - `app/ios`
  - `app/web`
  - `app/assets`
  - `app/lib`
  - `app/test`
  - `app/pubspec.yaml`
- 后端唯一工程根目录固定为 `AI-bot/server`，当前 App 协议以 `server/services/app_runtime.py` 注册的真实路由为准。
- 后端已经有一套成型的 Flutter App 协议：
  - HTTP: `/api/app/v1/...`
  - WebSocket: `/ws/app/v1/events`
  - 成功 envelope：`{ ok, data, request_id, ts }`
  - 失败 envelope：`{ ok: false, error: { code, message }, request_id, ts }`
- 当前 React 前端使用的旧接口形态并不匹配后端：
  - 旧前端写法：`/api/config`、`/api/tasks`、`/api/events`、`/ws/app`
  - 后端现有写法：`/api/app/v1/bootstrap`、`/api/app/v1/sessions/...`、`/api/app/v1/runtime/state`、`/ws/app/v1/events`
- 当前 React 前端还直接连接 OpenAI / Anthropic / Gemini，这一层必须删除。AI 回复必须从后端返回，前端不再直连任何第三方大模型。

## 2. 不可妥协的约束

- 保持现有产品功能范围不缩水：
  - Connect
  - Home / Dashboard
  - Chat
  - Tasks & Events
  - Control Center
  - Settings
  - Demo Mode
  - Voice 输入能力
- 所有生产数据必须以后端为准，前端不能自己伪造生产数据。
- 所有生产环境 AI 能力必须由后端提供，前端不再保存或直接使用模型提供商 SDK。
- 前端工程代码只放在 `app/`，后端工程代码只放在 `server/`，不得在计划中再引入 `flutter_app/`、`frontend/` 等并行根目录。
- 新前端的 API、事件、鉴权、错误处理全部遵循后端已有协议。
- 对于后端暂未提供的接口，Flutter 端也要先把 service 层和错误处理写好：
  - 方法签名先稳定
  - 返回统一错误
  - UI 给出“后端未提供 / 功能暂不可用”的可恢复提示
- Demo Mode 保留，但必须与真实后端模式彻底隔离，不能污染生产协议层。

## 3. 推荐 Flutter 项目结构

```text
app/
  android/
  ios/
  web/
  assets/
  lib/
    main.dart
    config/
      app_config.dart
      env.dart
      routes.dart
    constants/
      api_constants.dart
      app_constants.dart
    l10n/
      ...
    models/
      api/
        api_envelope.dart
        api_error.dart
        app_event_model.dart
      connect/
        connection_config_model.dart
      chat/
        session_model.dart
        message_model.dart
      home/
        runtime_state_model.dart
        device_status_model.dart
      settings/
        settings_model.dart
      tasks/
        task_model.dart
      events/
        event_model.dart
      notifications/
        notification_model.dart
      reminders/
        reminder_model.dart
    providers/
      app_providers.dart
      auth_provider.dart
      connectivity_provider.dart
      connect_provider.dart
      home_provider.dart
      chat_provider.dart
      settings_provider.dart
      tasks_provider.dart
      events_provider.dart
      control_center_provider.dart
    screens/
      connect/
        connect_screen.dart
      home/
        home_screen.dart
      chat/
        chat_screen.dart
      tasks/
        tasks_screen.dart
      control_center/
        control_center_screen.dart
      settings/
        settings_screen.dart
      demo_mode/
        demo_mode_screen.dart
    services/
      api/
        api_client.dart
        auth_interceptor.dart
        error_mapper.dart
      realtime/
        ws_service.dart
        ws_reconnect_service.dart
      storage/
        auth_storage_service.dart
      connect/
        connect_service.dart
      bootstrap/
        bootstrap_service.dart
      chat/
        chat_service.dart
        voice_capture_service.dart
      home/
        runtime_service.dart
        device_service.dart
      settings/
        settings_service.dart
      tasks/
        tasks_service.dart
      events/
        events_service.dart
      notifications/
        notifications_service.dart
      reminders/
        reminders_service.dart
      demo/
        demo_service_bundle.dart
    utils/
      result.dart
      retry.dart
      date_time_utils.dart
    widgets/
      common/
      chat/
      home/
      settings/
  test/
    ...
  pubspec.yaml
  README.md
```

### 3.1 分层职责

- `screens/*`
  - 页面入口和页面级布局
  - 只负责渲染、交互触发、错误提示、空态和 loading
- `providers/*`
  - 页面状态机
  - 管理异步加载、按钮禁用、提交状态、事件增量更新
- `services/*`
  - 所有后端协议交互入口
  - 统一处理路径、headers、envelope、错误映射、重连与 bootstrap 重拉
- `models/*`
  - 对齐后端 DTO 和前端业务模型
  - 字段命名优先对齐 `server/` 返回结构
- `widgets/*`
  - 可复用页面组件
  - 不直接承担网络请求或协议解析

## 4. 现有 React 功能到 Flutter 页面结构的映射

| 当前 React 功能 | Flutter 页面/组件 | 状态与服务层 | 数据来源 |
| --- | --- | --- | --- |
| `Connect.tsx` | `screens/connect/connect_screen.dart` | `connect_provider.dart` + `connect_service.dart` + `bootstrap_service.dart` | `GET /api/health` + `GET /api/app/v1/bootstrap` + 本地存储 |
| `Home.tsx` | `screens/home/home_screen.dart` | `home_provider.dart` + `runtime_service.dart` + `device_service.dart` | `bootstrap.runtime` + `runtime/state` + 事件流 |
| `Chat.tsx` | `screens/chat/chat_screen.dart` | `chat_provider.dart` + `chat_service.dart` + `ws_service.dart` | `sessions` + `messages` + `session.message.*` 事件 |
| `TasksEvents.tsx` | `screens/tasks/tasks_screen.dart` | `tasks_provider.dart` + `events_provider.dart` + `tasks_service.dart` + `events_service.dart` | 后端新增 `tasks/events` CRUD 接口 |
| `ControlCenter.tsx` | `screens/control_center/control_center_screen.dart` | `control_center_provider.dart` + `device_service.dart` + `notifications_service.dart` + `reminders_service.dart` | 现有 `device/runtime` + 后端新增通知/提醒/设备命令接口 |
| `Settings.tsx` | `screens/settings/settings_screen.dart` | `settings_provider.dart` + `settings_service.dart` | 后端新增 `settings` 接口，AI 配置完全后端化 |
| `VoiceContext.tsx` | `widgets/chat/*` + `screens/chat/chat_screen.dart` | `chat_provider.dart` + `voice_capture_service.dart` | Flutter 本地语音插件 + 后端消息接口 |
| Demo Mode | `screens/demo_mode/demo_mode_screen.dart` | `app_providers.dart` + `demo_service_bundle.dart` | 本地假数据，不走生产 API |

## 5. Flutter 端总数据流设计

### 5.1 连接阶段

1. 用户在 `connect_screen.dart` 输入 `host`、`port`、可选 `app token`
2. `connect_provider.dart` 调用 `connect_service.dart` 先请求 `GET /api/health`
3. 健康检查通过后调用 `bootstrap_service.dart` 请求 `GET /api/app/v1/bootstrap`
4. 成功后保存：
   - host
   - port
   - token
   - `latest_event_id`
   - default session 信息
5. `ws_service.dart` 建立 `ws://<host>:<port>/ws/app/v1/events` 连接

### 5.2 启动阶段

1. App 打开时先从 `auth_storage_service.dart` 读取上一次连接配置
2. `bootstrap_service.dart` 拉取 bootstrap
3. 页面层读取：
   - sessions
   - runtime
   - capabilities
   - websocket resume 参数
4. `ws_service.dart` 建立事件流订阅
5. 如果事件流返回 `should_refetch_bootstrap = true`，则由 provider 重新拉取 bootstrap

### 5.3 聊天阶段

1. 用户在 `chat_screen.dart` 发送消息时，只调用后端：
   - `POST /api/app/v1/sessions/{session_id}/messages`
2. `chat_provider.dart` 只把后端返回的 `accepted_message` 渲染为 pending
3. AI 进度和结果只能来自事件流：
   - `session.message.progress`
   - `session.message.completed`
   - `session.message.failed`
4. 不再存在任何直连第三方模型的 `aiService`

### 5.4 Dashboard / Control 阶段

1. 首页设备状态来自：
   - `bootstrap.runtime.device`
   - `GET /api/app/v1/runtime/state`
   - `device.connection.changed`
   - `device.state.changed`
   - `device.status.updated`
2. 当前任务、任务队列来自：
   - `runtime.task.current_changed`
   - `runtime.task.queue_changed`
3. Todo / Calendar 摘要来自：
   - `runtime/state`
   - `todo.summary.changed`
   - `calendar.summary.changed`
4. `home_provider.dart` 与 `control_center_provider.dart` 只消费统一 service 输出，不在页面里拼装协议

### 5.5 Tasks / Events / Notifications / Reminders

- 这些能力需要后端补口后才能真实落地。
- Flutter 端应先定义好 service、DTO、provider 状态机和错误展示。
- 在后端接口未就绪前：
  - 页面可以展示“后端未提供此接口”
  - 创建/编辑按钮保留，但点击后给出明确提示
  - 不允许静默失败

## 6. 前后端对齐规则

### 6.1 目录边界

- 前端代码只放在 `app/`
- 后端代码只放在 `server/`
- 协议与接口真源以 `server/services/app_runtime.py` 和 `功能讨论区/前后端对接/2026-04-01-backend-api-contract-for-flutter.md` 为准

### 6.2 路由到服务层的映射

| 后端路由组 | Flutter 服务文件 | 主要消费页面 |
| --- | --- | --- |
| `/api/app/v1/bootstrap`、`/api/app/v1/capabilities` | `services/bootstrap/bootstrap_service.dart` | Connect / Home / App 启动 |
| `/api/app/v1/sessions*` | `services/chat/chat_service.dart` | Chat |
| `/api/app/v1/runtime/*` | `services/home/runtime_service.dart` | Home / Control Center |
| `/api/app/v1/device*` | `services/home/device_service.dart` | Home / Control Center |
| `/api/app/v1/settings*` | `services/settings/settings_service.dart` | Settings |
| `/api/app/v1/tasks*` | `services/tasks/tasks_service.dart` | Tasks |
| `/api/app/v1/events*` | `services/events/events_service.dart` | Tasks |
| `/api/app/v1/notifications*` | `services/notifications/notifications_service.dart` | Control Center |
| `/api/app/v1/reminders*` | `services/reminders/reminders_service.dart` | Control Center |
| `/ws/app/v1/events` | `services/realtime/ws_service.dart` | Home / Chat / Control Center |

### 6.3 基础协议规则

- 生产模式统一前缀：`/api/app/v1`
- 仅保留一个后端协议版本：`app-v1`
- 字段命名统一使用后端现有风格：`snake_case`
- 所有接口统一解析后端 envelope：

```json
{
  "ok": true,
  "data": {},
  "request_id": "req_xxx",
  "ts": "2026-04-01T12:00:00+08:00"
}
```

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_ARGUMENT",
    "message": "content is required"
  },
  "request_id": "req_xxx",
  "ts": "2026-04-01T12:00:00+08:00"
}
```

### 6.4 鉴权规则

- HTTP:
  - 优先 `Authorization: Bearer <token>`
  - 兼容 `X-App-Token: <token>`
- WebSocket:
  - 使用 `?token=<token>`
  - 同时支持 `last_event_id` 和 `replay_limit`

### 6.5 事件流规则

- 所有实时更新统一走 `/ws/app/v1/events`
- Flutter 端必须保存最后一个 `event_id`
- 重连后必须带上 `last_event_id`
- 如果后端返回 `resume.accepted = false` 且 `should_refetch_bootstrap = true`，则立即重新 bootstrap
- 事件解析统一在 `models/api/app_event_model.dart` 与 `services/realtime/ws_service.dart` 完成

### 6.6 AI 规则

- Flutter 不允许直接请求：
  - OpenAI
  - Anthropic
  - Gemini
  - 任何自定义 OpenAI-compatible 推理地址
- Flutter 不允许直接保存 provider SDK client
- `settings_screen.dart` 只能编辑后端配置，不直接测试第三方模型
- “测试 AI 连接”必须改成调用后端测试接口

## 7. Flutter 端应立即定义的服务层接口

```dart
abstract class ConnectService {
  Future<void> saveConnection(ConnectionConfigDto config);
  Future<ConnectionConfigDto?> loadConnection();
  Future<HealthCheckDto> checkHealth(String host, int port);
}

abstract class BootstrapService {
  Future<BootstrapDto> fetchBootstrap();
  Future<CapabilitiesDto> fetchCapabilities();
}

abstract class ChatService {
  Future<List<SessionDto>> listSessions({int limit = 20, bool? archived});
  Future<SessionDto> createSession({required String title});
  Future<SessionDto> getSession(String sessionId);
  Future<MessagePageDto> getMessages(
    String sessionId, {
    int limit = 50,
    String? before,
    String? after,
  });
  Future<PostMessageAcceptedDto> postMessage(
    String sessionId, {
    required String content,
    required String clientMessageId,
  });
}

abstract class RuntimeService {
  Future<RuntimeStateDto> fetchRuntimeState();
  Future<TodoSummaryDto> fetchTodoSummary();
  Future<CalendarSummaryDto> fetchCalendarSummary();
}

abstract class DeviceService {
  Future<DeviceSnapshotDto> getDevice();
  Future<DeviceSpeakResultDto> speak(String text);
  Future<DeviceCommandResultDto> sendCommand(
    String command, {
    Map<String, dynamic>? params,
    String? clientCommandId,
  });
}

abstract class SettingsService {
  Future<AppSettingsDto> getSettings();
  Future<AppSettingsDto> updateSettings(UpdateSettingsRequest body);
  Future<AiConnectionTestDto> testAiConnection();
}

abstract class TasksService {
  Future<List<TaskDto>> listTasks();
  Future<TaskDto> createTask(CreateTaskRequest body);
  Future<TaskDto> updateTask(String taskId, UpdateTaskRequest body);
  Future<void> deleteTask(String taskId);
}

abstract class EventsService {
  Future<List<EventDto>> listEvents();
  Future<EventDto> createEvent(CreateEventRequest body);
  Future<EventDto> updateEvent(String eventId, UpdateEventRequest body);
  Future<void> deleteEvent(String eventId);
}

abstract class NotificationsService {
  Future<List<NotificationDto>> listNotifications();
  Future<NotificationDto> markRead(String notificationId, {required bool read});
  Future<void> markAllRead();
  Future<void> deleteNotification(String notificationId);
  Future<void> clearNotifications();
}

abstract class RemindersService {
  Future<List<ReminderDto>> listReminders();
  Future<ReminderDto> createReminder(CreateReminderRequest body);
  Future<ReminderDto> updateReminder(String reminderId, UpdateReminderRequest body);
  Future<void> deleteReminder(String reminderId);
}
```

## 8. 错误处理与降级要求

### 8.1 通用错误映射

- `401 UNAUTHORIZED`
  - 提示 token 无效或未配置
  - 回到 Connect 页面
- `404`
  - 若是后端未补口，页面展示“功能待后端提供”
- `409 DEVICE_OFFLINE`
  - 展示设备离线状态
  - 控制按钮变灰
- `400 INVALID_ARGUMENT`
  - 表单字段错误提示
- 网络超时 / DNS / Socket 失败
  - 保留当前页面状态
  - 展示可重试提示

### 8.2 聊天错误

- `POST message` 成功但后续 `session.message.failed`
  - 将 pending assistant 气泡标成失败
  - 允许用户重试
- WebSocket 断线
  - 显示顶部连接状态
  - 自动指数退避重连

### 8.3 未实现接口

- Flutter service 层必须把以下情况统一转成 `BackendNotReadyFailure`：
  - HTTP 404
  - HTTP 501
  - `error.code == "NOT_IMPLEMENTED"`
- UI 文案统一：
  - “后端接口尚未提供，当前版本仅完成前端接线准备。”

## 9. Connect 页面调整建议

- 保留：
  - 手动输入 host
  - 手动输入 port
  - Demo Mode
- 新增：
  - `App Token` 输入框（可选）
  - “验证连接”动作
- 调整：
  - 当前“Scan Network”先降级为可选增强项
  - 不把假扫描结果当作真实联网能力
- 建议：
  - LAN 扫描未来单独做成 mDNS/zeroconf 能力，不绑定后端协议

## 10. Demo Mode 设计

- Demo Mode 必须保留，因为它承担 UI 展示和离线联调价值
- 实现方式与生产模式彻底隔离：
  - `services/demo/demo_service_bundle.dart`
  - `providers/app_providers.dart` 中按模式注入 real/demo services
- 页面层不得直接感知 mock 数据结构差异

## 11. 实施任务

### Task 1: 在 `app/` 创建 Flutter 工程骨架与公共协议底座

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`
- Create: `app/lib/config/app_config.dart`
- Create: `app/lib/config/routes.dart`
- Create: `app/lib/constants/api_constants.dart`
- Create: `app/lib/models/api/api_envelope.dart`
- Create: `app/lib/models/api/api_error.dart`
- Create: `app/lib/services/api/api_client.dart`
- Create: `app/lib/services/api/auth_interceptor.dart`
- Create: `app/lib/services/api/error_mapper.dart`
- Create: `app/lib/utils/result.dart`

- [ ] 创建标准 Flutter 工程，根目录固定为 `app/`
- [ ] 配置依赖与基础路由
- [ ] 实现统一 HTTP client、超时、headers、envelope 解析
- [ ] 实现统一错误映射器
- [ ] 为 `401/404/409/500/timeout` 编写单元测试
- [ ] 运行 `flutter test`

### Task 2: 完成 Connect、bootstrap、鉴权与事件流接入

**Files:**
- Create: `app/lib/models/connect/connection_config_model.dart`
- Create: `app/lib/providers/auth_provider.dart`
- Create: `app/lib/providers/connect_provider.dart`
- Create: `app/lib/services/storage/auth_storage_service.dart`
- Create: `app/lib/services/connect/connect_service.dart`
- Create: `app/lib/services/bootstrap/bootstrap_service.dart`
- Create: `app/lib/services/realtime/ws_service.dart`
- Create: `app/lib/services/realtime/ws_reconnect_service.dart`
- Create: `app/lib/screens/connect/connect_screen.dart`

- [ ] 实现 host/port/token 本地存储
- [ ] 接入 `GET /api/health`
- [ ] 接入 `GET /api/app/v1/bootstrap`
- [ ] 接入 `/ws/app/v1/events` 与 resume 逻辑
- [ ] 为断线重连与 bootstrap 重拉编写测试

### Task 3: 迁移 Chat 页面为后端驱动 AI

**Files:**
- Create: `app/lib/models/chat/session_model.dart`
- Create: `app/lib/models/chat/message_model.dart`
- Create: `app/lib/providers/chat_provider.dart`
- Create: `app/lib/services/chat/chat_service.dart`
- Create: `app/lib/services/chat/voice_capture_service.dart`
- Create: `app/lib/screens/chat/chat_screen.dart`
- Create: `app/lib/widgets/chat/message_bubble.dart`
- Create: `app/lib/widgets/chat/message_input.dart`

- [ ] 接入 `sessions` / `messages` / `post message`
- [ ] 渲染 `accepted_message` pending 状态
- [ ] 处理 `session.message.progress/completed/failed`
- [ ] 保留语音输入入口，但只通过本地采集 + 后端消息接口工作
- [ ] 删除前端直连 AI 的设计，不引入任何模型 SDK
- [ ] 为 pending / failed / retry 编写测试

### Task 4: 迁移 Home 与 Control Center 页面

**Files:**
- Create: `app/lib/models/home/runtime_state_model.dart`
- Create: `app/lib/models/home/device_status_model.dart`
- Create: `app/lib/providers/home_provider.dart`
- Create: `app/lib/providers/control_center_provider.dart`
- Create: `app/lib/services/home/runtime_service.dart`
- Create: `app/lib/services/home/device_service.dart`
- Create: `app/lib/screens/home/home_screen.dart`
- Create: `app/lib/screens/control_center/control_center_screen.dart`
- Create: `app/lib/widgets/home/device_card.dart`

- [ ] 接入 `runtime/state`
- [ ] 接入 `device` 快照
- [ ] 处理 `runtime.task.*` 与 `device.*` 事件
- [ ] 首页显示 todo/calendar 摘要
- [ ] 为断线、离线、空状态编写测试

### Task 5: 完成 Settings 页面重构

**Files:**
- Create: `app/lib/models/settings/settings_model.dart`
- Create: `app/lib/providers/settings_provider.dart`
- Create: `app/lib/services/settings/settings_service.dart`
- Create: `app/lib/screens/settings/settings_screen.dart`
- Create: `app/lib/widgets/settings/settings_form.dart`

- [ ] 设置页改为后端配置驱动
- [ ] “测试 AI 连接”改为后端测试接口
- [ ] 不在前端持久化任何第三方模型 SDK client
- [ ] 编写按钮禁用、表单错误和接口错误提示测试

### Task 6: 先写好 Tasks / Events / Notifications / Reminders 的页面占位与 service 接口

**Files:**
- Create: `app/lib/models/tasks/task_model.dart`
- Create: `app/lib/models/events/event_model.dart`
- Create: `app/lib/models/notifications/notification_model.dart`
- Create: `app/lib/models/reminders/reminder_model.dart`
- Create: `app/lib/providers/tasks_provider.dart`
- Create: `app/lib/providers/events_provider.dart`
- Create: `app/lib/services/tasks/tasks_service.dart`
- Create: `app/lib/services/events/events_service.dart`
- Create: `app/lib/services/notifications/notifications_service.dart`
- Create: `app/lib/services/reminders/reminders_service.dart`
- Create: `app/lib/screens/tasks/tasks_screen.dart`

- [ ] 按后端契约文档先定义所有 DTO、request、service
- [ ] 若接口未提供，统一映射为 `BackendNotReadyFailure`
- [ ] 页面保留原功能入口，但展示明确未就绪提示
- [ ] 编写 service 级错误处理测试

### Task 7: 保留 Demo Mode 并完成依赖注入切换

**Files:**
- Create: `app/lib/screens/demo_mode/demo_mode_screen.dart`
- Create: `app/lib/services/demo/demo_service_bundle.dart`
- Modify: `app/lib/providers/app_providers.dart`

- [ ] 抽象 real 与 demo 两套 service 集合
- [ ] 确保页面层不直接依赖 mock 数据结构
- [ ] 增加启动模式切换测试

### Task 8: 收尾与验收

**Files:**
- Modify: `README.md`
- Create: `app/README.md`

- [ ] 更新接入说明和运行说明
- [ ] 列出后端必需环境变量与 token 配置方式
- [ ] 跑通基础集成测试
- [ ] 确认删除任何前端直连 AI 的残留代码

## 12. 完成定义

满足以下条件才算此计划落地完成：

- Flutter 前端工程根目录已经固定为 `app/`
- 后端实现真源目录已经固定为 `server/`
- `app/lib` 采用页面优先结构：`screens/providers/services/models/widgets`
- Chat AI 回复完全来自后端事件流
- Connect / Home / Chat / Control / Settings 均已对齐后端协议
- Tasks / Events / Notifications / Reminders 在后端接口就绪后可直接接入
- 前端对所有未就绪接口都已有稳定方法签名和错误处理
- Demo Mode 与生产模式分离

## 13. 依赖文档

- 前端实施应同时参考：`功能讨论区/前后端对接/2026-04-01-backend-api-contract-for-flutter.md`
- 后端真实路由入口应同时参考：`server/services/app_runtime.py`
- 原 React 页面仅作为交互参考，不再作为协议来源
