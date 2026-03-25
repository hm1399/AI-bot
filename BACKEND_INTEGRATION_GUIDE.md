# 后端集成指南 (Backend Integration Guide)

## 目录

1. [概览](#概览)
2. [系统架构](#系统架构)
3. [通信协议](#通信协议)
4. [REST API 接口](#rest-api-接口)
5. [WebSocket 接口](#websocket-接口)
6. [数据模型](#数据模型)
7. [身份验证与安全](#身份验证与安全)
8. [设备发现机制](#设备发现机制)
9. [集成步骤](#集成步骤)
10. [测试指南](#测试指南)
11. [错误处理](#错误处理)
12. [性能优化建议](#性能优化建议)

---

## 概览

本文档为智能设备控制应用的后端集成提供完整的技术规范。前端应用基于 React + TypeScript + Tailwind CSS 开发，通过 REST API 和 WebSocket 与后端服务器通信。

### 核心功能模块

- **配置管理**: 设备配置、LLM/STT/TTS 设置
- **设备控制**: 实时状态监控、远程控制指令
- **聊天交互**: AI 对话、历史记录管理
- **任务管理**: 创建、更新、删除智能待办事项
- **日历事件**: 日程管理和提醒
- **通知系统**: 推送通知、提醒消息
- **语音交互**: 语音命令识别与处理
- **手机指令**: 设备远程控制命令

### 技术栈要求

**后端建议**:
- 语言: Python 3.8+, Node.js 16+, 或其他支持 WebSocket 的语言
- Web 框架: FastAPI (Python), Express (Node.js), 或等效框架
- WebSocket: Socket.IO, native WebSocket
- 数据库: SQLite, PostgreSQL, MongoDB (可选)

**通信协议**:
- REST API: HTTP/HTTPS
- 实时通信: WebSocket (ws:// 或 wss://)
- 数据格式: JSON

---

## 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                    React Web Application                    │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌────────────┐ │
│  │   Home     │ │    Chat    │ │  Tasks   │ │  Control   │ │
│  │   Page     │ │    Page    │ │  Events  │ │  Center    │ │
│  └────────────┘ └────────────┘ └──────────┘ └────────────┘ │
│                          │                                   │
│  ┌───────────────────────┼─────────────────────────────┐   │
│  │         Context Providers (State Management)        │   │
│  │  Config│Chat│Device│Task│Event│Notification│Voice  │   │
│  └───────────────────────┼─────────────────────────────┘   │
└────────────────────────────┼─────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  API Service │    │  WebSocket   │    │  AI Service  │
│  (REST API)  │    │   Service    │    │ (LLM APIs)   │
└──────────────┘    └──────────────┘    └──────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Backend Server                            │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌────────────┐ │
│  │   REST     │ │ WebSocket  │ │   LLM    │ │    STT     │ │
│  │   API      │ │   Server   │ │  Engine  │ │    TTS     │ │
│  └────────────┘ └────────────┘ └──────────┘ └────────────┘ │
│                                                              │
│  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌────────────┐ │
│  │  Database  │ │   Device   │ │  Voice   │ │   Tasks    │ │
│  │   Layer    │ │  Manager   │ │ Processor│ │  Scheduler │ │
│  └────────────┘ └────────────┘ └──────────┘ └────────────┘ │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   Smart Device Hardware                      │
│              (Microphone, Speaker, LED, etc.)               │
└─────────────────────────────────────────────────────────────┘
```

---

## 通信协议

### 连接流程

1. **设备发现**: 前端调用 `discoverDevices()` 扫描局域网
2. **连接建立**: 用户选择设备，前端建立 HTTP + WebSocket 连接
3. **初始化**: 获取设备配置和状态
4. **实时通信**: WebSocket 保持长连接，推送实时更新
5. **心跳保持**: 每 30 秒发送 ping/pong 保持连接

### 基础 URL 配置

```typescript
// REST API Base URL
const API_BASE_URL = `http://${serverUrl}:${port}/api`;

// WebSocket URL
const WS_URL = `ws://${serverUrl}:${port}/ws/app`;
```

**默认端口**: 8000 (可配置)

---

## REST API 接口

### 1. 配置管理 (Configuration)

#### 1.1 获取配置

```http
GET /api/config
```

**Response**:
```json
{
  "serverUrl": "192.168.1.100",
  "serverPort": 8000,
  "llmProvider": "openai",
  "llmModel": "gpt-4",
  "llmApiKey": "sk-...",
  "llmBaseUrl": "https://api.openai.com/v1",
  "sttProvider": "openai",
  "sttModel": "whisper-1",
  "sttLanguage": "zh",
  "ttsProvider": "openai",
  "ttsModel": "tts-1",
  "ttsVoice": "alloy",
  "ttsSpeed": 1.0,
  "deviceVolume": 80,
  "ledEnabled": true,
  "ledBrightness": 75,
  "ledMode": "breathing",
  "ledColor": "#3b82f6",
  "wakeWord": "你好",
  "autoListen": true
}
```

#### 1.2 更新配置

```http
PUT /api/config
Content-Type: application/json
```

**Request Body**:
```json
{
  "llmProvider": "anthropic",
  "llmModel": "claude-3-5-sonnet-20241022",
  "ledMode": "rainbow",
  "deviceVolume": 90
}
```

**Response**: 返回更新后的完整配置 (同 GET /api/config)

---

### 2. 设备状态与控制 (Device)

#### 2.1 获取设备状态

```http
GET /api/device/status
```

**Response**:
```json
{
  "online": true,
  "battery": 85,
  "wifiSignal": 72,
  "state": "idle",
  "lastSeen": "2026-03-18T10:30:45.123Z"
}
```

**State 枚举值**:
- `idle`: 空闲
- `recording`: 录音中
- `playing`: 播放中
- `processing`: 处理中

#### 2.2 静音设备

```http
POST /api/device/mute
```

**Response**: `204 No Content` 或 `200 OK`

#### 2.3 切换 LED

```http
POST /api/device/led/toggle
```

**Response**: `204 No Content`

#### 2.4 重启设备

```http
POST /api/device/restart
```

**Response**: `204 No Content`

**建议**: 返回 `202 Accepted` 并在后台执行重启

---

### 3. 聊天交互 (Chat)

#### 3.1 获取历史记录

```http
GET /api/history
```

**Query Parameters** (可选):
- `limit`: 返回数量限制 (默认 100)
- `offset`: 分页偏移 (默认 0)
- `since`: 时间戳筛选

**Response**:
```json
[
  {
    "id": "msg-001",
    "text": "今天天气怎么样？",
    "source": "app",
    "timestamp": "2026-03-18T09:15:30.000Z"
  },
  {
    "id": "msg-002",
    "text": "北京今天晴天，温度 15-25°C",
    "source": "assistant",
    "timestamp": "2026-03-18T09:15:32.500Z",
    "toolResult": {
      "toolName": "get_weather",
      "status": "success",
      "result": "查询成功"
    }
  }
]
```

#### 3.2 发送消息

```http
POST /api/chat
Content-Type: application/json
```

**Request Body**:
```json
{
  "text": "帮我创建一个明天下午3点的会议提醒",
  "source": "app"
}
```

**Response**:
```json
{
  "id": "msg-003",
  "text": "好的，已为您创建明天下午3点的会议提醒",
  "source": "assistant",
  "timestamp": "2026-03-18T10:32:15.123Z",
  "toolResult": {
    "toolName": "create_reminder",
    "status": "success",
    "result": "提醒已创建"
  }
}
```

**建议**: 支持流式响应 (Server-Sent Events) 提升用户体验

---

### 4. 任务管理 (Tasks)

#### 4.1 获取所有任务

```http
GET /api/tasks
```

**Query Parameters** (可选):
- `completed`: `true` | `false` - 筛选完成状态
- `priority`: `high` | `medium` | `low` - 筛选优先级

**Response**:
```json
[
  {
    "id": "task-001",
    "title": "Review project proposal",
    "description": "Review the Q2 project proposal document",
    "priority": "high",
    "completed": false,
    "dueDate": "2026-03-19T17:00:00.000Z",
    "createdAt": "2026-03-15T08:00:00.000Z"
  }
]
```

#### 4.2 创建任务

```http
POST /api/tasks
Content-Type: application/json
```

**Request Body**:
```json
{
  "title": "Prepare presentation",
  "description": "Create slides for team meeting",
  "priority": "medium",
  "dueDate": "2026-03-20T14:00:00.000Z",
  "completed": false
}
```

**Response**: 返回创建的任务对象 (包含 `id` 和 `createdAt`)

#### 4.3 更新任务

```http
PUT /api/tasks/{taskId}
Content-Type: application/json
```

**Request Body**:
```json
{
  "completed": true,
  "priority": "low"
}
```

**Response**: 返回更新后的完整任务对象

#### 4.4 删除任务

```http
DELETE /api/tasks/{taskId}
```

**Response**: `204 No Content`

---

### 5. 日历事件 (Events)

#### 5.1 获取所有事件

```http
GET /api/events
```

**Query Parameters** (可选):
- `start`: ISO 8601 日期时间 - 开始时间筛选
- `end`: ISO 8601 日期时间 - 结束时间筛选

**Response**:
```json
[
  {
    "id": "event-001",
    "title": "Team Standup",
    "description": "Daily team sync meeting",
    "startTime": "2026-03-19T09:00:00.000Z",
    "endTime": "2026-03-19T09:30:00.000Z",
    "location": "Conference Room A",
    "createdAt": "2026-03-15T10:00:00.000Z"
  }
]
```

#### 5.2 创建事件

```http
POST /api/events
Content-Type: application/json
```

**Request Body**:
```json
{
  "title": "Client Meeting",
  "description": "Quarterly review with client",
  "startTime": "2026-03-21T14:00:00.000Z",
  "endTime": "2026-03-21T15:30:00.000Z",
  "location": "Zoom"
}
```

**Response**: 返回创建的事件对象 (包含 `id` 和 `createdAt`)

#### 5.3 更新事件

```http
PUT /api/events/{eventId}
Content-Type: application/json
```

**Request Body**: 与创建相同，所有字段可选

**Response**: 返回更新后的完整事件对象

#### 5.4 删除事件

```http
DELETE /api/events/{eventId}
```

**Response**: `204 No Content`

---

### 6. 通知系统 (Notifications)

#### 6.1 获取通知列表

```http
GET /api/notifications
```

**Query Parameters** (可选):
- `unread`: `true` - 仅返回未读通知
- `type`: 通知类型筛选

**Response**:
```json
[
  {
    "id": "notif-001",
    "type": "task_due",
    "priority": "high",
    "title": "Task Due Soon",
    "message": "Review project proposal is due in 1 hour",
    "timestamp": "2026-03-18T10:00:00.000Z",
    "read": false,
    "metadata": {
      "taskId": "task-001"
    },
    "actionUrl": "/tasks",
    "actionLabel": "View Task"
  }
]
```

**Notification Types**:
- `reminder`: 提醒
- `task_due`: 任务到期
- `event_starting`: 事件即将开始
- `device_alert`: 设备警报
- `system`: 系统通知
- `message`: 消息通知

**Priority**: `low` | `medium` | `high` | `urgent`

#### 6.2 标记为已读

```http
PUT /api/notifications/{notificationId}/read
```

**Response**: `204 No Content`

#### 6.3 删除通知

```http
DELETE /api/notifications/{notificationId}
```

**Response**: `204 No Content`

---

### 7. 提醒管理 (Reminders)

#### 7.1 获取提醒列表

```http
GET /api/reminders
```

**Response**:
```json
[
  {
    "id": "reminder-001",
    "title": "Morning Standup",
    "message": "Daily team standup meeting",
    "time": "09:00",
    "repeat": "daily",
    "enabled": true,
    "createdAt": "2026-03-10T08:00:00.000Z"
  }
]
```

**Repeat 枚举值**:
- `once`: 一次性
- `daily`: 每天
- `weekly`: 每周
- `monthly`: 每月

#### 7.2 创建提醒

```http
POST /api/reminders
Content-Type: application/json
```

**Request Body**:
```json
{
  "title": "Lunch Break",
  "message": "Time to take a break",
  "time": "12:00",
  "repeat": "daily",
  "enabled": true
}
```

**Response**: 返回创建的提醒对象

#### 7.3 更新提醒

```http
PUT /api/reminders/{reminderId}
Content-Type: application/json
```

**Request Body**: 所有字段可选

**Response**: 返回更新后的提醒对象

#### 7.4 删除提醒

```http
DELETE /api/reminders/{reminderId}
```

**Response**: `204 No Content`

---

### 8. 手机指令 (Phone Commands)

#### 8.1 发送设备控制指令

```http
POST /api/commands/device
Content-Type: application/json
```

**Request Body**:
```json
{
  "type": "led_color",
  "parameters": {
    "color": "#ff0000",
    "brightness": 100
  }
}
```

**Command Types**:
- `mute` / `unmute`: 静音控制
- `led_on` / `led_off`: LED 开关
- `led_color`: LED 颜色设置
- `restart`: 重启设备
- `volume`: 音量控制
- `wake` / `sleep`: 唤醒/睡眠

**Response**:
```json
{
  "id": "cmd-001",
  "type": "led_color",
  "parameters": {
    "color": "#ff0000",
    "brightness": 100
  },
  "timestamp": "2026-03-18T10:45:00.000Z",
  "status": "completed",
  "result": "LED color changed successfully"
}
```

**Status 枚举值**:
- `pending`: 待执行
- `executing`: 执行中
- `completed`: 已完成
- `failed`: 失败

#### 8.2 获取指令历史

```http
GET /api/commands/history
```

**Query Parameters** (可选):
- `limit`: 数量限制
- `status`: 状态筛选

**Response**: 返回指令对象数组

---

### 9. 语音交互 (Voice)

#### 9.1 语音转文本 (STT)

```http
POST /api/voice/stt
Content-Type: multipart/form-data
```

**Request**:
```
audio: <audio file> (WAV, MP3, OGG, etc.)
language: zh (可选)
```

**Response**:
```json
{
  "text": "帮我设置一个明天上午10点的闹钟",
  "confidence": 0.95,
  "language": "zh",
  "duration": 2.5
}
```

#### 9.2 文本转语音 (TTS)

```http
POST /api/voice/tts
Content-Type: application/json
```

**Request Body**:
```json
{
  "text": "您的提醒已设置成功",
  "voice": "alloy",
  "speed": 1.0
}
```

**Response**: 
- Content-Type: `audio/mpeg` 或 `audio/wav`
- Body: 音频文件二进制数据

#### 9.3 处理语音命令

```http
POST /api/voice/command
Content-Type: application/json
```

**Request Body**:
```json
{
  "text": "创建一个提醒明天下午3点开会"
}
```

**Response**:
```json
{
  "id": "voice-cmd-001",
  "text": "创建一个提醒明天下午3点开会",
  "type": "create_reminder",
  "timestamp": "2026-03-18T11:00:00.000Z",
  "processed": true,
  "result": "已创建提醒：明天下午3点开会"
}
```

**Command Types**:
- `create_task`: 创建任务
- `create_event`: 创建事件
- `create_reminder`: 创建提醒
- `control_device`: 控制设备
- `query`: 查询信息
- `other`: 其他

---

### 10. 智能待办任务 (Smart Todos)

#### 10.1 获取智能任务

```http
GET /api/smart-todos
```

**Response**:
```json
[
  {
    "id": "smart-001",
    "title": "Complete quarterly report",
    "description": "Analyze Q1 data and prepare report",
    "priority": "high",
    "completed": false,
    "dueDate": "2026-03-25T17:00:00.000Z",
    "createdAt": "2026-03-18T08:00:00.000Z",
    "suggestedTime": "2026-03-24T14:00:00.000Z",
    "estimatedDuration": 120,
    "dependencies": ["smart-002"],
    "tags": ["work", "report", "urgent"],
    "aiGenerated": true,
    "aiSuggestion": "建议在下午 2-4 点完成，此时效率最高"
  }
]
```

**Smart 字段说明**:
- `suggestedTime`: AI 建议的最佳完成时间
- `estimatedDuration`: 预计耗时（分钟）
- `dependencies`: 依赖的其他任务 ID
- `tags`: 标签数组
- `aiGenerated`: 是否由 AI 生成
- `aiSuggestion`: AI 的建议说明

#### 10.2 AI 生成任务建议

```http
POST /api/smart-todos/suggest
Content-Type: application/json
```

**Request Body**:
```json
{
  "context": "我需要在本周完成项目报告和准备下周的演讲",
  "deadline": "2026-03-22T23:59:59.000Z"
}
```

**Response**:
```json
{
  "suggestions": [
    {
      "title": "准备项目报告数据分析",
      "priority": "high",
      "estimatedDuration": 90,
      "suggestedTime": "2026-03-19T10:00:00.000Z",
      "reason": "需要充足时间收集和分析数据"
    },
    {
      "title": "制作演讲 PPT",
      "priority": "medium",
      "estimatedDuration": 60,
      "suggestedTime": "2026-03-20T14:00:00.000Z",
      "reason": "依赖报告完成后的数据"
    }
  ]
}
```

---

### 11. 设备发现 (Device Discovery)

#### 11.1 扫描局域网设备

```http
GET /api/discover
```

**Response**:
```json
[
  {
    "ip": "192.168.1.100",
    "port": 8000,
    "name": "AI-Bot Desktop Assistant",
    "deviceId": "device-12345",
    "version": "1.0.0",
    "capabilities": ["chat", "voice", "led", "tasks"]
  }
]
```

**实现建议**:
- 使用 mDNS/Bonjour 或 SSDP 协议进行设备发现
- 设备应广播服务类型 `_ai-assistant._tcp` 或类似标识
- 超时时间建议 2-5 秒

---

## WebSocket 接口

### 连接端点

```
ws://{serverUrl}:{port}/ws/app
```

### 消息格式

所有 WebSocket 消息使用以下标准格式：

```typescript
interface WSMessage {
  type: WSMessageType;
  data: any;
  timestamp: number;
}

type WSMessageType = 
  | 'device_status'
  | 'chat_message'
  | 'task_update'
  | 'event_update'
  | 'config_update'
  | 'notification'
  | 'reminder_trigger'
  | 'voice_command'
  | 'command_status'
  | 'ping'
  | 'pong';
```

### 消息类型详解

#### 1. device_status - 设备状态更新

**服务器 → 客户端**:
```json
{
  "type": "device_status",
  "data": {
    "online": true,
    "battery": 80,
    "wifiSignal": 65,
    "state": "idle",
    "lastSeen": "2026-03-18T10:30:00.000Z"
  },
  "timestamp": 1710756600000
}
```

**触发条件**: 
- 设备状态变化
- 电池电量变化超过 5%
- WiFi 信号变化超过 10%
- 状态切换（idle/recording/playing/processing）

#### 2. chat_message - 聊天消息

**服务器 → 客户端**:
```json
{
  "type": "chat_message",
  "data": {
    "id": "msg-456",
    "text": "好的，已为您设置提醒",
    "source": "assistant",
    "timestamp": "2026-03-18T10:31:00.000Z",
    "toolResult": {
      "toolName": "create_reminder",
      "status": "success",
      "result": "提醒创建成功"
    }
  },
  "timestamp": 1710756660000
}
```

**客户端 → 服务器**:
```json
{
  "type": "chat_message",
  "data": {
    "text": "明天提醒我开会",
    "source": "app"
  },
  "timestamp": 1710756600000
}
```

#### 3. task_update - 任务更新

**服务器 → 客户端**:
```json
{
  "type": "task_update",
  "data": {
    "action": "created",
    "task": {
      "id": "task-789",
      "title": "新任务",
      "priority": "high",
      "completed": false,
      "createdAt": "2026-03-18T10:32:00.000Z"
    }
  },
  "timestamp": 1710756720000
}
```

**Action 类型**:
- `created`: 任务已创建
- `updated`: 任务已更新
- `deleted`: 任务已删除

#### 4. event_update - 事件更新

**服务器 → 客户端**:
```json
{
  "type": "event_update",
  "data": {
    "action": "updated",
    "event": {
      "id": "event-123",
      "title": "Team Meeting",
      "startTime": "2026-03-19T10:00:00.000Z",
      "endTime": "2026-03-19T11:00:00.000Z"
    }
  },
  "timestamp": 1710756780000
}
```

#### 5. config_update - 配置更新

**服务器 → 客户端**:
```json
{
  "type": "config_update",
  "data": {
    "ledEnabled": false,
    "deviceVolume": 70
  },
  "timestamp": 1710756840000
}
```

**说明**: 仅发送变更的配置项

#### 6. notification - 推送通知

**服务器 → 客户端**:
```json
{
  "type": "notification",
  "data": {
    "id": "notif-999",
    "type": "task_due",
    "priority": "high",
    "title": "任务即将到期",
    "message": "Review project proposal 将在 1 小时后到期",
    "timestamp": "2026-03-18T10:35:00.000Z",
    "read": false,
    "metadata": {
      "taskId": "task-001"
    }
  },
  "timestamp": 1710756900000
}
```

#### 7. reminder_trigger - 提醒触发

**服务器 → 客户端**:
```json
{
  "type": "reminder_trigger",
  "data": {
    "id": "reminder-001",
    "title": "Morning Standup",
    "message": "Daily team standup meeting",
    "time": "09:00"
  },
  "timestamp": 1710756960000
}
```

#### 8. voice_command - 语音命令

**服务器 → 客户端**:
```json
{
  "type": "voice_command",
  "data": {
    "id": "voice-001",
    "text": "打开 LED 灯",
    "type": "control_device",
    "processed": true,
    "result": "LED 已打开"
  },
  "timestamp": 1710757020000
}
```

#### 9. command_status - 指令状态更新

**服务器 → 客户端**:
```json
{
  "type": "command_status",
  "data": {
    "id": "cmd-123",
    "status": "completed",
    "result": "设备已重启"
  },
  "timestamp": 1710757080000
}
```

#### 10. ping / pong - 心跳保持

**客户端 → 服务器**:
```json
{
  "type": "ping",
  "data": {},
  "timestamp": 1710757140000
}
```

**服务器 → 客户端**:
```json
{
  "type": "pong",
  "data": {},
  "timestamp": 1710757140100
}
```

**频率**: 客户端每 30 秒发送一次 ping

### 连接管理

#### 重连机制

客户端实现了自动重连机制：
- 连接断开后等待 5 秒自动重连
- 最大重试次数：无限制（可配置）
- 指数退避策略（可选实现）

#### 错误处理

```json
{
  "type": "error",
  "data": {
    "code": "INVALID_MESSAGE",
    "message": "Invalid message format",
    "details": "Missing required field: type"
  },
  "timestamp": 1710757200000
}
```

---

## 数据模型

### TypeScript 类型定义

完整的类型定义位于前端代码：
- `/src/app/models/types.ts`: 核心数据类型
- `/src/app/models/notifications.ts`: 通知和语音相关类型

### 数据库 Schema 建议

#### Tasks 表

```sql
CREATE TABLE tasks (
  id VARCHAR(50) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  priority VARCHAR(10) CHECK (priority IN ('high', 'medium', 'low')),
  completed BOOLEAN DEFAULT FALSE,
  due_date TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tasks_completed ON tasks(completed);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_priority ON tasks(priority);
```

#### Events 表

```sql
CREATE TABLE events (
  id VARCHAR(50) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  start_time TIMESTAMP NOT NULL,
  end_time TIMESTAMP NOT NULL,
  location VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_events_start_time ON events(start_time);
CREATE INDEX idx_events_end_time ON events(end_time);
```

#### Messages 表

```sql
CREATE TABLE messages (
  id VARCHAR(50) PRIMARY KEY,
  text TEXT NOT NULL,
  source VARCHAR(20) CHECK (source IN ('device', 'app', 'assistant', 'system')),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  tool_name VARCHAR(50),
  tool_status VARCHAR(20),
  tool_result TEXT
);

CREATE INDEX idx_messages_timestamp ON messages(timestamp DESC);
CREATE INDEX idx_messages_source ON messages(source);
```

#### Notifications 表

```sql
CREATE TABLE notifications (
  id VARCHAR(50) PRIMARY KEY,
  type VARCHAR(30) NOT NULL,
  priority VARCHAR(10) CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  read BOOLEAN DEFAULT FALSE,
  action_url VARCHAR(255),
  action_label VARCHAR(100),
  metadata JSON
);

CREATE INDEX idx_notifications_read ON notifications(read);
CREATE INDEX idx_notifications_timestamp ON notifications(timestamp DESC);
CREATE INDEX idx_notifications_type ON notifications(type);
```

#### Reminders 表

```sql
CREATE TABLE reminders (
  id VARCHAR(50) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  message TEXT,
  time TIME NOT NULL,
  repeat VARCHAR(20) CHECK (repeat IN ('once', 'daily', 'weekly', 'monthly')),
  enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_reminders_enabled ON reminders(enabled);
CREATE INDEX idx_reminders_time ON reminders(time);
```

#### Config 表

```sql
CREATE TABLE config (
  key VARCHAR(50) PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**建议**: 配置也可以存储为 JSON 文件或使用 Redis

---

## 身份验证与安全

### 当前实现

当前版本为局域网内部使用，**未实现**身份验证机制。

### 推荐的安全增强

#### 1. API Token 认证

**生成 Token**:
```http
POST /api/auth/token
Content-Type: application/json

{
  "deviceId": "device-12345",
  "secret": "shared-secret-key"
}
```

**Response**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": 86400
}
```

**使用 Token**:
```http
GET /api/config
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### 2. WebSocket 认证

**连接时传递 Token**:
```javascript
const ws = new WebSocket('ws://server:8000/ws/app?token=your-jwt-token');
```

或者在连接后发送认证消息：
```json
{
  "type": "auth",
  "data": {
    "token": "your-jwt-token"
  },
  "timestamp": 1710757200000
}
```

#### 3. HTTPS/WSS

生产环境建议启用 TLS:
- REST API: `https://server:8443/api`
- WebSocket: `wss://server:8443/ws/app`

#### 4. CORS 配置

```javascript
// Express 示例
app.use(cors({
  origin: ['http://localhost:5173', 'http://192.168.1.0/24'],
  credentials: true
}));
```

#### 5. 速率限制

```javascript
// 限制每个 IP 每分钟 60 次请求
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60
});

app.use('/api', limiter);
```

---

## 设备发现机制

### mDNS 服务广播

#### 服务器端 (Node.js 示例)

```javascript
const mdns = require('mdns');

const ad = mdns.createAdvertisement(mdns.tcp('ai-assistant'), 8000, {
  name: 'AI-Bot Desktop Assistant',
  txtRecord: {
    version: '1.0.0',
    capabilities: 'chat,voice,led,tasks'
  }
});

ad.start();
```

#### 服务器端 (Python 示例)

```python
from zeroconf import ServiceInfo, Zeroconf
import socket

info = ServiceInfo(
    "_ai-assistant._tcp.local.",
    "AI-Bot._ai-assistant._tcp.local.",
    addresses=[socket.inet_aton("192.168.1.100")],
    port=8000,
    properties={
        'version': '1.0.0',
        'capabilities': 'chat,voice,led,tasks'
    },
    server="ai-bot.local."
)

zeroconf = Zeroconf()
zeroconf.register_service(info)
```

### HTTP 轮询发现

如果 mDNS 不可用，可以实现简单的 HTTP 广播扫描：

1. 客户端向局域网内所有 IP 的指定端口发送 HTTP 请求
2. 服务器响应设备信息
3. 客户端收集所有响应并展示给用户

```http
GET /api/info

Response:
{
  "name": "AI-Bot Desktop Assistant",
  "version": "1.0.0",
  "deviceId": "device-12345",
  "capabilities": ["chat", "voice", "led", "tasks"]
}
```

---

## 集成步骤

### 第一步: 环境准备

1. **选择技术栈**: Python (FastAPI) 或 Node.js (Express)
2. **安装依赖**:
   ```bash
   # Python
   pip install fastapi uvicorn websockets sqlalchemy
   
   # Node.js
   npm install express ws sqlite3 body-parser
   ```

3. **创建项目结构**:
   ```
   backend/
   ├── api/
   │   ├── routes/
   │   │   ├── config.py/js
   │   │   ├── device.py/js
   │   │   ├── chat.py/js
   │   │   ├── tasks.py/js
   │   │   └── events.py/js
   │   └── websocket.py/js
   ├── models/
   ├── services/
   ├── database/
   └── main.py/js
   ```

### 第二步: 实现 REST API

**FastAPI 示例 (config.py)**:

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

router = APIRouter(prefix="/api/config")

class Config(BaseModel):
    serverUrl: str
    serverPort: int
    llmProvider: str
    llmModel: str
    llmApiKey: Optional[str] = None
    # ... 其他字段

# 全局配置（实际应使用数据库）
config_data = Config(
    serverUrl="192.168.1.100",
    serverPort=8000,
    llmProvider="openai",
    llmModel="gpt-4"
)

@router.get("")
async def get_config():
    return config_data

@router.put("")
async def update_config(updates: dict):
    global config_data
    for key, value in updates.items():
        if hasattr(config_data, key):
            setattr(config_data, key, value)
    return config_data
```

**Express 示例 (config.js)**:

```javascript
const express = require('express');
const router = express.Router();

let config = {
  serverUrl: '192.168.1.100',
  serverPort: 8000,
  llmProvider: 'openai',
  llmModel: 'gpt-4',
  // ... 其他字段
};

router.get('/config', (req, res) => {
  res.json(config);
});

router.put('/config', (req, res) => {
  config = { ...config, ...req.body };
  res.json(config);
});

module.exports = router;
```

### 第三步: 实现 WebSocket 服务

**FastAPI 示例**:

```python
from fastapi import WebSocket, WebSocketDisconnect
from typing import List
import json
import asyncio

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            await connection.send_json(message)

manager = ConnectionManager()

@app.websocket("/ws/app")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message['type'] == 'ping':
                await websocket.send_json({
                    'type': 'pong',
                    'data': {},
                    'timestamp': int(time.time() * 1000)
                })
            elif message['type'] == 'chat_message':
                # 处理聊天消息
                await manager.broadcast({
                    'type': 'chat_message',
                    'data': message['data'],
                    'timestamp': int(time.time() * 1000)
                })
    except WebSocketDisconnect:
        manager.disconnect(websocket)
```

**Node.js 示例**:

```javascript
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8000, path: '/ws/app' });

const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log('Client connected');

  ws.on('message', (data) => {
    const message = JSON.parse(data);

    if (message.type === 'ping') {
      ws.send(JSON.stringify({
        type: 'pong',
        data: {},
        timestamp: Date.now()
      }));
    } else if (message.type === 'chat_message') {
      // 广播消息给所有客户端
      broadcast({
        type: 'chat_message',
        data: message.data,
        timestamp: Date.now()
      });
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    console.log('Client disconnected');
  });
});

function broadcast(message) {
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
    }
  });
}
```

### 第四步: 数据库集成

**SQLite 示例 (Python)**:

```python
from sqlalchemy import create_engine, Column, String, Boolean, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import uuid
from datetime import datetime

engine = create_engine('sqlite:///./app.db')
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

class Task(Base):
    __tablename__ = 'tasks'
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    title = Column(String, nullable=False)
    description = Column(String)
    priority = Column(String, default='medium')
    completed = Column(Boolean, default=False)
    due_date = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(engine)
```

### 第五步: 集成 AI 服务

后端可以选择：

1. **透传模式**: 前端直接调用 AI API（已实现在 `aiService.ts`）
2. **代理模式**: 后端代理 AI 请求，隐藏 API Key

**代理模式示例**:

```python
@router.post("/chat")
async def chat(request: ChatRequest):
    # 使用后端配置的 API Key
    response = await openai_client.chat.completions.create(
        model=config.llmModel,
        messages=[{"role": "user", "content": request.text}]
    )
    
    return {
        "id": str(uuid.uuid4()),
        "text": response.choices[0].message.content,
        "source": "assistant",
        "timestamp": datetime.utcnow().isoformat()
    }
```

### 第六步: 设备控制集成

```python
class DeviceController:
    def __init__(self):
        self.led_enabled = True
        self.volume = 80
        
    async def mute(self):
        # 控制硬件静音
        self.volume = 0
        await self.broadcast_status()
        
    async def toggle_led(self):
        self.led_enabled = not self.led_enabled
        # 发送指令给 LED 控制器
        await self.broadcast_status()
        
    async def broadcast_status(self):
        await manager.broadcast({
            'type': 'device_status',
            'data': {
                'online': True,
                'battery': self.get_battery(),
                'wifiSignal': self.get_wifi_signal(),
                'state': 'idle'
            },
            'timestamp': int(time.time() * 1000)
        })

device = DeviceController()

@router.post("/device/mute")
async def mute_device():
    await device.mute()
    return {"status": "muted"}
```

### 第七步: 启动服务器

**FastAPI**:

```python
# main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 导入路由
from api.routes import config, device, chat, tasks, events
app.include_router(config.router)
app.include_router(device.router)
app.include_router(chat.router)
app.include_router(tasks.router)
app.include_router(events.router)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

**Express**:

```javascript
// main.js
const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

// 导入路由
app.use('/api', require('./routes/config'));
app.use('/api', require('./routes/device'));
app.use('/api', require('./routes/chat'));
app.use('/api', require('./routes/tasks'));
app.use('/api', require('./routes/events'));

const PORT = 8000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
```

---

## 测试指南

### 单元测试

#### REST API 测试 (Python + pytest)

```python
# test_api.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_get_config():
    response = client.get("/api/config")
    assert response.status_code == 200
    assert "serverUrl" in response.json()

def test_create_task():
    response = client.post("/api/tasks", json={
        "title": "Test Task",
        "priority": "high",
        "completed": False
    })
    assert response.status_code == 200
    assert response.json()["title"] == "Test Task"
```

#### REST API 测试 (Node.js + Jest)

```javascript
// api.test.js
const request = require('supertest');
const app = require('./app');

describe('GET /api/config', () => {
  it('should return config', async () => {
    const res = await request(app).get('/api/config');
    expect(res.statusCode).toEqual(200);
    expect(res.body).toHaveProperty('serverUrl');
  });
});

describe('POST /api/tasks', () => {
  it('should create a task', async () => {
    const res = await request(app)
      .post('/api/tasks')
      .send({
        title: 'Test Task',
        priority: 'high',
        completed: false
      });
    expect(res.statusCode).toEqual(200);
    expect(res.body.title).toEqual('Test Task');
  });
});
```

### 集成测试

#### WebSocket 测试

```python
# test_websocket.py
import pytest
import websockets
import json

@pytest.mark.asyncio
async def test_websocket_ping_pong():
    uri = "ws://localhost:8000/ws/app"
    async with websockets.connect(uri) as websocket:
        # 发送 ping
        await websocket.send(json.dumps({
            "type": "ping",
            "data": {},
            "timestamp": 1710757200000
        }))
        
        # 接收 pong
        response = await websocket.recv()
        message = json.loads(response)
        assert message["type"] == "pong"
```

### 手动测试工具

#### 使用 curl 测试 REST API

```bash
# 获取配置
curl http://192.168.1.100:8000/api/config

# 更新配置
curl -X PUT http://192.168.1.100:8000/api/config \
  -H "Content-Type: application/json" \
  -d '{"ledEnabled": false}'

# 创建任务
curl -X POST http://192.168.1.100:8000/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Task",
    "priority": "high",
    "completed": false
  }'

# 获取设备状态
curl http://192.168.1.100:8000/api/device/status
```

#### 使用 Postman

1. 导入 API 集合（可创建 Postman Collection JSON）
2. 设置环境变量：`{{baseUrl}}` = `http://192.168.1.100:8000`
3. 测试所有端点

#### 使用 wscat 测试 WebSocket

```bash
# 安装 wscat
npm install -g wscat

# 连接 WebSocket
wscat -c ws://192.168.1.100:8000/ws/app

# 发送消息
> {"type":"ping","data":{},"timestamp":1710757200000}

# 接收响应
< {"type":"pong","data":{},"timestamp":1710757200100}
```

### 性能测试

#### 使用 Apache Bench

```bash
# 测试 GET 请求
ab -n 1000 -c 10 http://192.168.1.100:8000/api/config

# 测试 POST 请求
ab -n 1000 -c 10 -p task.json -T application/json \
  http://192.168.1.100:8000/api/tasks
```

#### 使用 wrk

```bash
# 安装 wrk
sudo apt-get install wrk

# 运行负载测试
wrk -t4 -c100 -d30s http://192.168.1.100:8000/api/config
```

---

## 错误处理

### 标准错误响应格式

所有 API 错误应返回统一格式：

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": "Additional error details or stack trace (dev mode only)",
    "timestamp": "2026-03-18T10:00:00.000Z"
  }
}
```

### HTTP 状态码规范

- `200 OK`: 请求成功
- `201 Created`: 资源创建成功
- `204 No Content`: 操作成功但无返回内容
- `400 Bad Request`: 请求参数错误
- `401 Unauthorized`: 未授权（需要认证）
- `403 Forbidden`: 禁止访问（已认证但无权限）
- `404 Not Found`: 资源不存在
- `409 Conflict`: 资源冲突
- `422 Unprocessable Entity`: 请求格式正确但语义错误
- `429 Too Many Requests`: 请求过于频繁
- `500 Internal Server Error`: 服务器内部错误
- `503 Service Unavailable`: 服务不可用

### 错误代码定义

```typescript
enum ErrorCode {
  // 通用错误
  INVALID_REQUEST = 'INVALID_REQUEST',
  RESOURCE_NOT_FOUND = 'RESOURCE_NOT_FOUND',
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  
  // 认证错误
  UNAUTHORIZED = 'UNAUTHORIZED',
  INVALID_TOKEN = 'INVALID_TOKEN',
  TOKEN_EXPIRED = 'TOKEN_EXPIRED',
  
  // 设备错误
  DEVICE_OFFLINE = 'DEVICE_OFFLINE',
  DEVICE_BUSY = 'DEVICE_BUSY',
  COMMAND_FAILED = 'COMMAND_FAILED',
  
  // AI 服务错误
  AI_SERVICE_ERROR = 'AI_SERVICE_ERROR',
  INVALID_API_KEY = 'INVALID_API_KEY',
  QUOTA_EXCEEDED = 'QUOTA_EXCEEDED',
  
  // 数据验证错误
  VALIDATION_ERROR = 'VALIDATION_ERROR',
  MISSING_REQUIRED_FIELD = 'MISSING_REQUIRED_FIELD',
  INVALID_FORMAT = 'INVALID_FORMAT',
}
```

### 错误处理示例

**FastAPI**:

```python
from fastapi import HTTPException
from datetime import datetime

@router.get("/tasks/{task_id}")
async def get_task(task_id: str):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(
            status_code=404,
            detail={
                "code": "RESOURCE_NOT_FOUND",
                "message": f"Task with id {task_id} not found",
                "timestamp": datetime.utcnow().isoformat()
            }
        )
    return task
```

**Express**:

```javascript
router.get('/tasks/:taskId', (req, res) => {
  const task = tasks.find(t => t.id === req.params.taskId);
  
  if (!task) {
    return res.status(404).json({
      error: {
        code: 'RESOURCE_NOT_FOUND',
        message: `Task with id ${req.params.taskId} not found`,
        timestamp: new Date().toISOString()
      }
    });
  }
  
  res.json(task);
});
```

### WebSocket 错误处理

```json
{
  "type": "error",
  "data": {
    "code": "INVALID_MESSAGE_FORMAT",
    "message": "Message must include 'type' field",
    "originalMessage": { ... }
  },
  "timestamp": 1710757200000
}
```

---

## 性能优化建议

### 1. 数据库优化

- **索引**: 为频繁查询的字段创建索引
  ```sql
  CREATE INDEX idx_tasks_completed ON tasks(completed);
  CREATE INDEX idx_messages_timestamp ON messages(timestamp DESC);
  ```

- **分页**: 大数据集使用分页
  ```python
  @router.get("/tasks")
  async def get_tasks(skip: int = 0, limit: int = 100):
      return db.query(Task).offset(skip).limit(limit).all()
  ```

- **连接池**: 使用数据库连接池
  ```python
  engine = create_engine('sqlite:///./app.db', pool_size=10, max_overflow=20)
  ```

### 2. 缓存策略

- **Redis 缓存**: 缓存频繁读取的配置和设备状态
  ```python
  import redis
  cache = redis.Redis(host='localhost', port=6379)
  
  @router.get("/config")
  async def get_config():
      cached = cache.get('config')
      if cached:
          return json.loads(cached)
      
      config = load_config_from_db()
      cache.setex('config', 300, json.dumps(config))  # 5分钟过期
      return config
  ```

- **内存缓存**: 小数据集使用内存缓存
  ```python
  from functools import lru_cache
  
  @lru_cache(maxsize=128)
  def get_device_capabilities():
      return load_capabilities()
  ```

### 3. WebSocket 优化

- **消息批处理**: 批量发送状态更新
  ```python
  async def batch_broadcast():
      while True:
          await asyncio.sleep(1)  # 每秒发送一次
          if pending_updates:
              await manager.broadcast({
                  'type': 'batch_update',
                  'data': pending_updates,
                  'timestamp': int(time.time() * 1000)
              })
              pending_updates.clear()
  ```

- **消息压缩**: 大消息使用 gzip 压缩
  ```python
  import gzip
  compressed = gzip.compress(json.dumps(data).encode())
  ```

### 4. API 响应优化

- **字段选择**: 允许客户端指定需要的字段
  ```http
  GET /api/tasks?fields=id,title,completed
  ```

- **ETag 缓存**: 使用 ETag 减少重复传输
  ```python
  from hashlib import md5
  
  @router.get("/config")
  async def get_config(request: Request):
      config = get_config_data()
      etag = md5(json.dumps(config).encode()).hexdigest()
      
      if request.headers.get('If-None-Match') == etag:
          return Response(status_code=304)
      
      return Response(
          content=json.dumps(config),
          headers={'ETag': etag}
      )
  ```

### 5. 并发处理

- **异步处理**: 使用异步 I/O 提升并发能力
  ```python
  @router.post("/chat")
  async def chat(request: ChatRequest):
      # 异步调用 AI 服务
      response = await ai_service.send_message(request.text)
      return response
  ```

- **任务队列**: 长时间操作使用后台任务
  ```python
  from fastapi import BackgroundTasks
  
  @router.post("/device/restart")
  async def restart_device(background_tasks: BackgroundTasks):
      background_tasks.add_task(perform_restart)
      return {"status": "restart scheduled"}
  ```

### 6. 监控和日志

- **性能监控**: 记录 API 响应时间
  ```python
  import time
  from starlette.middleware.base import BaseHTTPMiddleware
  
  class TimingMiddleware(BaseHTTPMiddleware):
      async def dispatch(self, request, call_next):
          start = time.time()
          response = await call_next(request)
          duration = time.time() - start
          response.headers['X-Process-Time'] = str(duration)
          return response
  
  app.add_middleware(TimingMiddleware)
  ```

- **结构化日志**: 使用 JSON 格式日志
  ```python
  import logging
  import json
  
  logger = logging.getLogger(__name__)
  logger.info(json.dumps({
      'event': 'task_created',
      'task_id': task.id,
      'user': 'app',
      'timestamp': datetime.utcnow().isoformat()
  }))
  ```

---

## 附录

### A. 完整 API 端点列表

| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/api/config` | 获取配置 |
| PUT | `/api/config` | 更新配置 |
| GET | `/api/device/status` | 获取设备状态 |
| POST | `/api/device/mute` | 静音设备 |
| POST | `/api/device/led/toggle` | 切换 LED |
| POST | `/api/device/restart` | 重启设备 |
| GET | `/api/history` | 获取聊天历史 |
| POST | `/api/chat` | 发送聊天消息 |
| GET | `/api/tasks` | 获取所有任务 |
| POST | `/api/tasks` | 创建任务 |
| PUT | `/api/tasks/{id}` | 更新任务 |
| DELETE | `/api/tasks/{id}` | 删除任务 |
| GET | `/api/events` | 获取所有事件 |
| POST | `/api/events` | 创建事件 |
| PUT | `/api/events/{id}` | 更新事件 |
| DELETE | `/api/events/{id}` | 删除事件 |
| GET | `/api/notifications` | 获取通知列表 |
| PUT | `/api/notifications/{id}/read` | 标记已读 |
| DELETE | `/api/notifications/{id}` | 删除通知 |
| GET | `/api/reminders` | 获取提醒列表 |
| POST | `/api/reminders` | 创建提醒 |
| PUT | `/api/reminders/{id}` | 更新提醒 |
| DELETE | `/api/reminders/{id}` | 删除提醒 |
| POST | `/api/commands/device` | 发送设备指令 |
| GET | `/api/commands/history` | 获取指令历史 |
| POST | `/api/voice/stt` | 语音转文本 |
| POST | `/api/voice/tts` | 文本转语音 |
| POST | `/api/voice/command` | 处理语音命令 |
| GET | `/api/smart-todos` | 获取智能任务 |
| POST | `/api/smart-todos/suggest` | AI 生成任务建议 |
| GET | `/api/discover` | 扫描设备 |

### B. WebSocket 消息类型列表

| 类型 | 方向 | 描述 |
|------|------|------|
| `device_status` | S→C | 设备状态更新 |
| `chat_message` | S↔C | 聊天消息 |
| `task_update` | S→C | 任务更新 |
| `event_update` | S→C | 事件更新 |
| `config_update` | S→C | 配置更新 |
| `notification` | S→C | 推送通知 |
| `reminder_trigger` | S→C | 提醒触发 |
| `voice_command` | S→C | 语音命令 |
| `command_status` | S→C | 指令状态更新 |
| `ping` | C→S | 心跳检测 |
| `pong` | S→C | 心跳响应 |
| `error` | S→C | 错误消息 |

**图例**: S=Server, C=Client, S→C=服务器到客户端, C→S=客户端到服务器, S↔C=双向

### C. 示例代码仓库

完整的后端实现示例（建议创建）：
- Python FastAPI: `github.com/your-repo/ai-assistant-backend-python`
- Node.js Express: `github.com/your-repo/ai-assistant-backend-nodejs`

### D. 联系方式

如有集成问题，请联系：
- 技术支持: support@example.com
- GitHub Issues: https://github.com/your-repo/issues
- 文档反馈: docs@example.com

---

## 更新日志

### v1.0.0 (2026-03-18)
- 初始版本发布
- 完整的 REST API 规范
- WebSocket 实时通信协议
- 8 大核心功能模块集成
- 数据模型和数据库 schema
- 集成步骤和测试指南

---

**文档版本**: 1.0.0  
**最后更新**: 2026-03-18  
**作者**: AI Assistant Development Team  
**许可证**: MIT
