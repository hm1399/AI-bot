# Backend API Contract For Flutter Frontend

## 1. 文档目的

这份文档给后端使用，目的是把 Flutter 前端需要的接口、字段、错误码和事件流契约一次性说明清楚，避免前后端分别实现成两套协议。

前提约束：

- 前端目标架构是 Flutter，不再沿用当前 React 的接口写法
- AI 回复必须由后端提供，前端不再直连任何模型供应商
- 协议应尽量复用当前 `AI-bot/server` 已有的 `app-v1`
- 当前后端已有接口优先复用；只有原前端功能无法覆盖时才新增接口

## 2. 必须保留的协议基础

### 2.1 Base Path

- HTTP: `/api/app/v1`
- WebSocket: `/ws/app/v1/events`

### 2.2 成功响应格式

```json
{
  "ok": true,
  "data": {},
  "request_id": "req_xxx",
  "ts": "2026-04-01T12:00:00+08:00"
}
```

### 2.3 错误响应格式

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

### 2.4 命名规则

- JSON 字段统一使用 `snake_case`
- 时间字段统一 ISO-8601 带时区
- ID 字段统一字符串

### 2.5 鉴权规则

- HTTP:
  - `Authorization: Bearer <token>`
  - 或 `X-App-Token: <token>`
- WebSocket:
  - `?token=<token>`
  - 支持 `?last_event_id=<event_id>&replay_limit=<n>`

## 3. 后端现有接口，Flutter 将直接复用

以下接口后端已经有实现，前端将直接按现有协议接入，不建议改路径：

| Endpoint | 用途 |
| --- | --- |
| `GET /api/health` | 连接页检测服务存活 |
| `GET /api/app/v1/bootstrap` | App 首屏初始化 |
| `GET /api/app/v1/sessions` | 获取会话列表 |
| `POST /api/app/v1/sessions` | 创建会话 |
| `GET /api/app/v1/sessions/{session_id}` | 获取单会话信息 |
| `GET /api/app/v1/sessions/{session_id}/messages` | 获取消息列表 |
| `POST /api/app/v1/sessions/{session_id}/messages` | 发送用户消息 |
| `GET /api/app/v1/runtime/state` | 获取运行态快照 |
| `POST /api/app/v1/runtime/stop` | 停止当前任务 |
| `GET /api/app/v1/runtime/todo-summary` | 获取 Todo 摘要 |
| `POST /api/app/v1/runtime/todo-summary` | 更新 Todo 摘要 |
| `GET /api/app/v1/runtime/calendar-summary` | 获取日历摘要 |
| `POST /api/app/v1/runtime/calendar-summary` | 更新日历摘要 |
| `GET /api/app/v1/device` | 获取设备快照 |
| `POST /api/app/v1/device/speak` | 触发设备播报 |
| `GET /api/app/v1/capabilities` | 获取能力开关 |
| `GET /ws/app/v1/events` | 实时事件流 |

## 4. 现有接口如何被 Flutter 使用

### 4.1 Bootstrap

用途：App 启动后的唯一初始化入口。

前端依赖字段：

- `server_version`
- `capabilities`
- `runtime`
- `sessions`
- `event_stream.path`
- `event_stream.resume.latest_event_id`

### 4.2 Chat

聊天必须采用以下流程：

1. Flutter 调 `POST /api/app/v1/sessions/{session_id}/messages`
2. 后端返回：
   - `accepted_message`
   - `task_id`
   - `queued`
3. 后端通过事件流推送：
   - `session.message.created`
   - `session.message.progress`
   - `session.message.completed`
   - `session.message.failed`

这意味着：

- AI 回复不需要新增单独 HTTP 接口
- AI 回复不能再由前端直接请求第三方模型

### 4.3 Home / Dashboard

首页需要的生产数据可先由以下现有接口和事件满足：

- `bootstrap.runtime`
- `GET /api/app/v1/runtime/state`
- `runtime.task.current_changed`
- `runtime.task.queue_changed`
- `device.connection.changed`
- `device.state.changed`
- `device.status.updated`
- `todo.summary.changed`
- `calendar.summary.changed`

## 5. 为保留当前前端功能，后端需要新增的接口

以下新增接口是为了完整覆盖当前 React 页面能力。

---

## 5.1 Settings

### `GET /api/app/v1/settings`

用途：设置页读取当前配置。

返回的 `data` 建议形态：

```json
{
  "server_url": "192.168.1.100",
  "server_port": 8000,
  "llm_provider": "openai",
  "llm_model": "gpt-4o",
  "llm_base_url": null,
  "llm_api_key_configured": true,
  "stt_provider": "openai",
  "stt_model": "whisper-1",
  "stt_language": "en-US",
  "tts_provider": "edge_tts",
  "tts_model": "tts-1",
  "tts_voice": "alloy",
  "tts_speed": 1.0,
  "device_volume": 75,
  "led_enabled": true,
  "led_brightness": 50,
  "led_mode": "breathing",
  "led_color": "#0000ff",
  "wake_word": "Hey Assistant",
  "auto_listen": true
}
```

注意：

- 不要回传原始 `llm_api_key`
- 仅返回 `llm_api_key_configured`

### `PUT /api/app/v1/settings`

用途：保存设置页。

请求体建议：

```json
{
  "llm_provider": "openai",
  "llm_model": "gpt-4o",
  "llm_api_key": "optional-new-secret",
  "llm_base_url": null,
  "stt_language": "en-US",
  "tts_voice": "alloy",
  "tts_speed": 1.0,
  "device_volume": 75,
  "led_mode": "breathing",
  "led_color": "#0000ff",
  "wake_word": "Hey Assistant",
  "auto_listen": true
}
```

### `POST /api/app/v1/settings/llm/test`

用途：替代当前前端“Test AI Connection”。

建议返回：

```json
{
  "success": true,
  "provider": "openai",
  "model": "gpt-4o",
  "message": "connection ok"
}
```

建议错误码：

- `INVALID_ARGUMENT`
- `LLM_NOT_CONFIGURED`
- `UPSTREAM_AUTH_FAILED`
- `UPSTREAM_TIMEOUT`

---

## 5.2 Tasks

### `GET /api/app/v1/tasks`

用途：任务列表页。

支持 query：

- `completed=true|false`
- `priority=high|medium|low`
- `limit`

返回项建议：

```json
{
  "items": [
    {
      "task_id": "task_001",
      "title": "Review proposal",
      "description": "Prepare feedback",
      "priority": "high",
      "completed": false,
      "due_at": "2026-04-02T10:00:00+08:00",
      "created_at": "2026-04-01T10:00:00+08:00",
      "updated_at": "2026-04-01T10:00:00+08:00"
    }
  ]
}
```

### `POST /api/app/v1/tasks`

### `PATCH /api/app/v1/tasks/{task_id}`

### `DELETE /api/app/v1/tasks/{task_id}`

要求：

- 支持改 `completed`
- 支持改 `priority`
- 支持改 `title/description/due_at`

建议事件：

- `task.created`
- `task.updated`
- `task.deleted`

---

## 5.3 Events

### `GET /api/app/v1/events`

### `POST /api/app/v1/events`

### `PATCH /api/app/v1/events/{event_id}`

### `DELETE /api/app/v1/events/{event_id}`

字段建议：

```json
{
  "event_id": "event_001",
  "title": "Team Standup",
  "description": "Daily meeting",
  "start_at": "2026-04-02T09:00:00+08:00",
  "end_at": "2026-04-02T09:30:00+08:00",
  "location": "Meeting Room A",
  "created_at": "2026-04-01T08:00:00+08:00",
  "updated_at": "2026-04-01T08:00:00+08:00"
}
```

建议事件：

- `event.created`
- `event.updated`
- `event.deleted`

---

## 5.4 Notifications

### `GET /api/app/v1/notifications`

用途：通知中心与首页最近通知。

返回建议：

```json
{
  "items": [
    {
      "notification_id": "notif_001",
      "type": "task_due",
      "priority": "high",
      "title": "Task Due Soon",
      "message": "Review project proposal is due in 1 hour",
      "read": false,
      "created_at": "2026-04-01T11:00:00+08:00",
      "metadata": {
        "task_id": "task_001"
      }
    }
  ],
  "unread_count": 3
}
```

### `PATCH /api/app/v1/notifications/{notification_id}`

请求：

```json
{
  "read": true
}
```

### `POST /api/app/v1/notifications/read-all`

### `DELETE /api/app/v1/notifications/{notification_id}`

### `DELETE /api/app/v1/notifications`

建议事件：

- `notification.created`
- `notification.updated`
- `notification.deleted`

---

## 5.5 Reminders

### `GET /api/app/v1/reminders`

### `POST /api/app/v1/reminders`

### `PATCH /api/app/v1/reminders/{reminder_id}`

### `DELETE /api/app/v1/reminders/{reminder_id}`

字段建议：

```json
{
  "reminder_id": "rem_001",
  "title": "Morning Standup",
  "message": "Daily team standup meeting",
  "time": "09:00",
  "repeat": "daily",
  "enabled": true,
  "created_at": "2026-04-01T09:00:00+08:00",
  "updated_at": "2026-04-01T09:00:00+08:00"
}
```

建议事件：

- `reminder.created`
- `reminder.updated`
- `reminder.deleted`

---

## 5.6 Device Commands

当前前端功能包含：

- 静音
- LED 开关
- 重启
- 唤醒
- 休眠
- 设音量
- 设 LED 颜色
- 设 LED 亮度

建议统一走一个命令接口：

### `POST /api/app/v1/device/commands`

请求：

```json
{
  "client_command_id": "cmd_local_001",
  "command": "set_volume",
  "params": {
    "level": 80
  }
}
```

允许的 `command` 建议枚举：

- `mute`
- `toggle_led`
- `restart`
- `wake`
- `sleep`
- `set_volume`
- `set_led_color`
- `set_led_brightness`

成功返回建议：

```json
{
  "accepted": true,
  "command_id": "cmd_srv_001",
  "command": "set_volume",
  "device": {
    "connected": true,
    "state": "IDLE",
    "battery": 85,
    "wifi_rssi": -52,
    "charging": false,
    "reconnect_count": 0
  }
}
```

建议错误码：

- `DEVICE_OFFLINE`
- `INVALID_ARGUMENT`
- `COMMAND_NOT_SUPPORTED`

建议事件：

- `device.command.accepted`
- `device.command.failed`
- 或直接继续复用 `device.status.updated` / `device.state.changed`

---

## 5.7 可选：Voice Command History

如果后端希望把“语音命令历史”也做成跨设备同步能力，可补：

- `GET /api/app/v1/voice/commands`
- `POST /api/app/v1/voice/commands`

但这不是 P0。P0 可以先让 Flutter 本地维护语音识别历史，然后把最终文本当普通聊天消息发给 `sessions/{session_id}/messages`。

## 6. WebSocket 事件约束

以下事件已存在，Flutter 会直接消费：

- `system.hello`
- `runtime.task.queue_changed`
- `runtime.task.current_changed`
- `session.message.created`
- `session.message.progress`
- `session.message.completed`
- `session.message.failed`
- `device.connection.changed`
- `device.state.changed`
- `device.status.updated`
- `todo.summary.changed`
- `calendar.summary.changed`

新增接口落地后，建议继续补这些事件：

- `task.created`
- `task.updated`
- `task.deleted`
- `event.created`
- `event.updated`
- `event.deleted`
- `notification.created`
- `notification.updated`
- `notification.deleted`
- `reminder.created`
- `reminder.updated`
- `reminder.deleted`
- `settings.updated`

## 7. Flutter 对错误的预期处理

为避免前端写很多特殊分支，建议后端错误码稳定化：

| code | 含义 | 前端动作 |
| --- | --- | --- |
| `UNAUTHORIZED` | token 无效 | 回到连接页 |
| `INVALID_ARGUMENT` | 请求参数错误 | 表单提示 |
| `SESSION_NOT_FOUND` | 会话不存在 | 刷新列表并提示 |
| `TASK_NOT_FOUND` | 任务不存在 | 刷新页面 |
| `DEVICE_OFFLINE` | 设备离线 | 禁用控制按钮 |
| `COMMAND_NOT_SUPPORTED` | 不支持的设备命令 | 显示功能不可用 |
| `NOT_IMPLEMENTED` | 接口尚未提供 | 前端统一展示“后端未提供” |
| `UPSTREAM_TIMEOUT` | 上游模型超时 | 聊天提示可重试 |

## 8. 关于 AI 的明确边界

后端需要明确承担以下责任：

- 保存并使用 LLM 配置
- 负责所有模型调用
- 负责 message -> agent -> assistant reply 全链路
- 负责 progress / completed / failed 事件推送

前端不再承担：

- 存储 provider SDK client
- 直接请求 OpenAI / Anthropic / Gemini
- 直接测试外部模型连通性

## 9. 交付优先级建议

### P0：先让 App 能跑通

- 保持现有：
  - `bootstrap`
  - `sessions`
  - `messages`
  - `runtime/state`
  - `device`
  - `capabilities`
  - `events`
- 新增：
  - `GET /api/app/v1/settings`
  - `PUT /api/app/v1/settings`
  - `POST /api/app/v1/settings/llm/test`
  - `POST /api/app/v1/device/commands`

### P1：恢复原型里的数据管理能力

- `tasks` CRUD
- `events` CRUD
- `notifications` CRUD
- `reminders` CRUD

### P2：增强能力

- 语音命令历史后端化
- 局域网发现增强
- 更多设备命令事件

## 10. 与前端文档的对应关系

前端实施计划见：

- `docs/superpowers/plans/2026-04-01-flutter-frontend-implementation-plan.md`

后端补口和字段命名请以本文件为准，避免 Flutter 端再去兼容旧 React 的 `/api/config`、`/api/tasks`、`/ws/app` 风格接口。
