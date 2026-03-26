# AI-Bot Flutter 本地局域网 API 与实时事件模型草案

> 创建日期：2026-03-25  
> 适用阶段：Phase C 前置设计  
> 适用范围：运行在用户电脑上的本地后端 + 局域网内 Flutter App  
> 当前定位：**只定义接口与事件模型，不在本文件中直接实现代码**

---

## 1. 设计目标

这份草案要解决的是：

1. 让 Flutter App 在**不依赖设备 WebSocket 协议**的前提下接入本地后端。
2. 让 App 能看到**独立的 App 会话**，同时感知**全局共享状态**。
3. 让 App 能实时看到：
   - 当前 AI 任务进度
   - 设备在线 / 离线与状态变化
   - 当前任务与任务队列
   - 后续 Todo / 日历摘要变化
4. 保持和当前后端方向一致：
   - 本地单机
   - 局域网接入
   - 单人单设备、单人多端
   - App / 设备 / WhatsApp 会话彼此独立，但共享系统运行态

---

## 2. 本轮范围边界

### 本轮明确纳入

- Flutter App 查询会话列表
- Flutter App 查询单会话消息历史
- Flutter App 发送文本消息
- Flutter App 查询设备状态 / 服务健康状态 / 系统能力
- Flutter App 查询“当前任务 / 任务队列 / Todo 摘要 / 日历摘要”
- Flutter App 建立单独实时事件通道

### 本轮明确不纳入

- 公网远程接入
- 多用户 / 多租户
- App 直接复用设备音频协议
- 完整 Todo / 日历 CRUD 细节
- Flutter 端直接控制底层 ESP32 音频流

---

## 3. 核心建模原则

### 3.1 双域模型

后端对 Flutter 暴露两类状态：

#### A. 会话域（Session Domain）

用于保存某个通道自己的聊天上下文。

例如：

- `app:main`
- `app:notes`
- `device:esp32`
- `whatsapp:<chat_id>`

这些会话**彼此独立**，不共用消息历史。

#### B. 全局运行域（Runtime Domain）

用于保存所有通道都需要感知的共享状态。

包括：

- 当前执行中的任务
- 任务队列
- 当前设备状态
- Todo 摘要
- 日历摘要
- 服务健康状态

也就是说：

> Flutter App 不需要和设备共享同一个聊天线程，但必须能看到设备当前在忙什么、AI 当前在处理什么。

---

## 4. 接口风格总原则

### 4.1 协议拆分

建议采用：

- **REST API**：查询 + 控制 + 消息发送
- **WebSocket 事件通道**：实时状态推送

原因：

- App 查询和控制语义清晰
- 历史数据和当前快照适合 REST
- 实时状态、进度、事件广播适合 WebSocket
- Flutter 对 WebSocket 支持成熟

### 4.2 基础前缀

建议统一前缀：

- HTTP：`/api/app/v1/...`
- WebSocket：`/ws/app/v1/events`

### 4.3 鉴权方式（局域网第一版）

本地局域网阶段建议使用：

- `Authorization: Bearer <APP_AUTH_TOKEN>`

说明：

- 第一版不做复杂登录系统
- App 与后端同属单用户本地环境
- 后续若要扩展到远程接入，再升级为配对码 / 短期令牌 / 设备绑定

### 4.4 通用返回结构

建议所有 HTTP 响应统一为：

```json
{
  "ok": true,
  "data": {},
  "request_id": "req_xxx",
  "ts": "2026-03-25T18:00:00+08:00"
}
```

错误时：

```json
{
  "ok": false,
  "error": {
    "code": "SESSION_NOT_FOUND",
    "message": "session does not exist"
  },
  "request_id": "req_xxx",
  "ts": "2026-03-25T18:00:00+08:00"
}
```

### 4.5 推荐错误码

- `UNAUTHORIZED`
- `FORBIDDEN`
- `INVALID_ARGUMENT`
- `SESSION_NOT_FOUND`
- `DEVICE_OFFLINE`
- `TASK_NOT_FOUND`
- `TASK_NOT_CANCELLABLE`
- `SERVICE_UNAVAILABLE`
- `INTERNAL_ERROR`

---

## 5. Flutter 侧需要的核心对象

## 5.1 AppSession

```json
{
  "session_id": "app:main",
  "channel": "app",
  "title": "主对话",
  "summary": "最近一次是在问天气和任务安排",
  "last_message_at": "2026-03-25T17:30:00+08:00",
  "message_count": 12,
  "pinned": true,
  "archived": false
}
```

## 5.2 AppMessage

```json
{
  "message_id": "msg_001",
  "session_id": "app:main",
  "role": "user",
  "content": "今天还有什么安排？",
  "content_type": "text",
  "status": "completed",
  "created_at": "2026-03-25T17:31:00+08:00",
  "metadata": {}
}
```

补充说明：

- `role`：`user` / `assistant` / `system`
- `content_type`：`text` / `progress` / `tool_hint` / `event_note`
- `status`：`pending` / `streaming` / `completed` / `failed`

## 5.3 RuntimeState

```json
{
  "current_task": {
    "task_id": "task_001",
    "kind": "chat",
    "source_channel": "device",
    "source_session_id": "device:esp32",
    "stage": "thinking",
    "summary": "正在处理设备语音提问",
    "started_at": "2026-03-25T17:32:00+08:00",
    "cancellable": true
  },
  "task_queue": [
    {
      "task_id": "task_002",
      "kind": "chat",
      "source_channel": "app",
      "source_session_id": "app:main",
      "summary": "等待处理 App 文本提问"
    }
  ],
  "device": {
    "connected": true,
    "state": "IDLE",
    "battery": 82,
    "wifi_rssi": -48,
    "charging": false
  },
  "todo_summary": {
    "enabled": false,
    "pending_count": 0,
    "overdue_count": 0,
    "next_due_at": null
  },
  "calendar_summary": {
    "enabled": false,
    "today_count": 0,
    "next_event_at": null,
    "next_event_title": null
  }
}
```

---

## 6. HTTP API 草案

## 6.1 启动引导接口

### `GET /api/app/v1/bootstrap`

用途：

- Flutter 启动后一次性获取首页所需的最小快照

返回内容建议包含：

- 服务版本
- 能力开关
- 设备快照
- 当前任务 / 任务队列
- Todo / 日历摘要
- 默认 App 会话列表
- 实时事件通道地址

建议返回：

```json
{
  "ok": true,
  "data": {
    "server_version": "0.6.0",
    "capabilities": {
      "chat": true,
      "device_control": true,
      "whatsapp_bridge": true,
      "todo_summary": false,
      "calendar_summary": false
    },
    "runtime": {},
    "sessions": [],
    "event_stream": {
      "type": "websocket",
      "path": "/ws/app/v1/events"
    }
  }
}
```

---

## 6.2 会话接口

### `GET /api/app/v1/sessions`

用途：

- 查询 Flutter App 自己的会话列表

默认只返回 `channel=app` 的会话，不直接返回设备 / WhatsApp 会话全文。

支持参数：

- `limit`
- `archived`
- `pinned_first`

### `POST /api/app/v1/sessions`

用途：

- 新建一个 App 会话

请求体建议：

```json
{
  "title": "新对话"
}
```

### `GET /api/app/v1/sessions/{session_id}`

用途：

- 获取单会话信息

### `GET /api/app/v1/sessions/{session_id}/messages`

用途：

- 获取单会话消息历史

参数建议：

- `before`
- `after`
- `limit`

### `POST /api/app/v1/sessions/{session_id}/messages`

用途：

- 向指定 App 会话发送文本消息

请求体建议：

```json
{
  "content": "今天还有什么安排？",
  "client_message_id": "flutter_local_001"
}
```

返回内容建议：

- 已接收的用户消息对象
- 当前生成的 `task_id`
- 是否已进入队列

---

## 6.3 运行时状态接口

### `GET /api/app/v1/runtime/state`

用途：

- 查询当前共享运行态

返回内容：

- `current_task`
- `task_queue`
- `device`
- `todo_summary`
- `calendar_summary`

### `POST /api/app/v1/runtime/stop`

用途：

- 停止当前正在执行的任务

请求体建议：

```json
{
  "task_id": "task_001"
}
```

说明：

- 如果 `task_id` 为空，则默认停止当前前台任务
- 第一版只支持“停止当前任务”，不支持复杂队列重排

---

## 6.4 设备接口

### `GET /api/app/v1/device`

用途：

- 查询设备连接状态与当前设备信息

### `POST /api/app/v1/device/speak`

用途：

- 让设备主动播报一段文字

请求体建议：

```json
{
  "text": "请记得下午三点开会"
}
```

说明：

- 第一版只接受文本播报
- 若设备离线，返回 `DEVICE_OFFLINE`

---

## 6.5 系统能力接口

### `GET /api/app/v1/capabilities`

用途：

- 返回当前后端开启了哪些能力

建议返回：

- `device_control`
- `voice_pipeline`
- `whatsapp_bridge`
- `todo_summary`
- `calendar_summary`
- `app_events`

---

## 7. 实时事件通道草案

## 7.1 通道选择

第一版建议使用：

- `WebSocket /ws/app/v1/events`

原因：

- Flutter 支持成熟
- 后续如需加入客户端回执、订阅过滤、重连同步更容易扩展
- 当前服务端本身已有 WebSocket 使用经验

## 7.2 连接方式

建议：

- Header：`Authorization: Bearer <APP_AUTH_TOKEN>`
- 连接成功后由服务端下发 `hello` 事件

## 7.3 事件包统一结构

```json
{
  "event_id": "evt_001",
  "event_type": "runtime.task.current_changed",
  "scope": "global",
  "occurred_at": "2026-03-25T18:10:00+08:00",
  "session_id": null,
  "task_id": "task_001",
  "payload": {}
}
```

字段说明：

- `event_id`：事件唯一 ID
- `event_type`：事件名称
- `scope`：`global` / `session`
- `session_id`：若事件与某会话相关则填写
- `task_id`：若事件与某任务相关则填写
- `payload`：具体事件载荷

---

## 8. 事件类型定义

## 8.1 连接与系统类

### `system.hello`

建立连接后立即发送。

用途：

- 告知客户端连接成功
- 返回服务端时间
- 返回当前协议版本

### `system.health.changed`

服务健康状态变化时发送。

### `system.error`

用于推送非会话级系统错误。

---

## 8.2 会话消息类

### `session.message.created`

有新消息写入某个 App 会话时发送。

适用场景：

- 用户消息已入库
- AI 最终回复已完成

### `session.message.progress`

AI 处理中间态。

对应现有后端里的：

- `_progress`
- `_tool_hint`

建议 payload：

```json
{
  "message_id": "msg_progress_001",
  "kind": "thinking",
  "content": "正在思考",
  "tool_hint": false
}
```

`kind` 建议枚举：

- `listening`
- `transcribing`
- `thinking`
- `tool_hint`
- `replying`

### `session.message.completed`

AI 回复最终完成。

### `session.message.failed`

某次回复失败。

---

## 8.3 任务与队列类

### `runtime.task.current_changed`

当前前台任务变化时发送。

例如：

- 从无任务 → 有任务
- 从 `thinking` → `replying`
- 任务完成后恢复为空

### `runtime.task.queue_changed`

任务队列变化时发送。

第一版只要求能表达：

- 队列长度变化
- 新任务入队
- 某任务被取消 / 出队

---

## 8.4 设备状态类

### `device.connection.changed`

设备连接 / 断开时发送。

payload 示例：

```json
{
  "connected": true,
  "reconnect_count": 2
}
```

### `device.state.changed`

设备状态机变化时发送。

状态值沿用现有定义：

- `IDLE`
- `LISTENING`
- `PROCESSING`
- `SPEAKING`
- `ERROR`

### `device.status.updated`

设备上报信息变化时发送。

例如：

- 电量
- WiFi RSSI
- 是否充电

---

## 8.5 Todo / 日历摘要类

这两类是为后续功能预留，但接口模型现在就要占位。

### `todo.summary.changed`

仅推送摘要，不推送完整 Todo 列表。

### `calendar.summary.changed`

仅推送摘要，不推送完整日历事件表。

这样可以保证：

- Phase C 第一版先把“共享状态模型”定下来
- 后面真正做 Todo / 日历时不需要推翻 App 架构

---

## 9. Flutter 推荐启动流程

建议 Flutter App 启动顺序固定为：

1. 读取本地保存的局域网服务地址和 `APP_AUTH_TOKEN`
2. 调用 `GET /api/app/v1/bootstrap`
3. 渲染首页快照
4. 建立 `WebSocket /ws/app/v1/events`
5. 接收 `system.hello`
6. 用户进入某会话页时，再调用 `GET /sessions/{id}/messages`
7. 用户发送消息时走 `POST /sessions/{id}/messages`
8. 回复过程和设备状态变化统一从事件通道接收

这样做的好处是：

- REST 负责“取快照和历史”
- WebSocket 负责“看实时变化”
- App 不需要自己推断任务状态

---

## 10. 与当前本地后端的映射关系

这份草案是基于当前本地后端现实约束写的：

- 现有 HTTP 只有 `/api/health` 与 `/api/device`
- 现有主消息流是 `MessageBus inbound/outbound`
- 现有设备状态来源于 `DeviceChannel`
- 现有 AI 处理中间态已经有 `_progress` / `_tool_hint`
- 现有会话存储仍是 `SessionManager + JSONL`

因此 Phase C 第一版不应一上来做成“大而全”的平台 API，而应按下面方式落地：

- 先补 App 查询 / 发消息 / 看进度
- 再补共享运行态
- 最后再补 Todo / 日历细节

---

## 11. 推荐实现顺序

### 第 1 步：最小可用 App API

- `GET /api/app/v1/bootstrap`
- `GET /api/app/v1/sessions`
- `GET /api/app/v1/sessions/{session_id}/messages`
- `POST /api/app/v1/sessions/{session_id}/messages`

### 第 2 步：最小实时事件流

- `system.hello`
- `session.message.progress`
- `session.message.completed`
- `device.connection.changed`
- `device.state.changed`

### 第 3 步：共享运行态

- `GET /api/app/v1/runtime/state`
- `runtime.task.current_changed`
- `runtime.task.queue_changed`

### 第 4 步：设备控制

- `GET /api/app/v1/device`
- `POST /api/app/v1/device/speak`
- `POST /api/app/v1/runtime/stop`

### 第 5 步：Todo / 日历摘要占位接入

- `todo.summary.changed`
- `calendar.summary.changed`

---

## 12. 本草案的关键结论

一句话总结：

> Flutter App 第一版应该被定义成“本地局域网里的独立聊天客户端 + 全局运行态观察器”，而不是“设备协议的镜像端”。

这意味着：

- 聊天历史按 App 自己的会话保存
- 设备、WhatsApp、App 不共用一个聊天线程
- 但三者都围绕同一个本地运行中枢工作
- App 必须能看到当前任务、任务队列、设备状态，以及后续 Todo / 日历摘要变化

---

## 13. 建议下一步

完成这份草案后，下一步最合理的是：

1. 在后端代码中补 `AppSession` / `RuntimeState` 数据结构
2. 先实现 `GET /api/app/v1/bootstrap`
3. 再实现 `GET /api/app/v1/sessions` 与 `POST /api/app/v1/sessions/{id}/messages`
4. 最后实现 `WebSocket /ws/app/v1/events` 的最小事件集
