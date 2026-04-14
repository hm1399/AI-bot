# JSON / JSONL 热路径迁移到 SQLite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把当前后端仍然落在 JSON / JSONL 的高频源数据与关键运行态对象分层迁到 SQLite，在不改前端 UI/UX、不改现有 HTTP / WebSocket 契约的前提下，解决“整份重写、全量扫描、派生摘要反复重算、运行态对象写入互相覆盖”的性能与一致性问题。

**Architecture:** 不上 Redis / PostgreSQL / ORM，大体仍保持 `aiohttp + SessionManager + AppRuntimeService + ExperienceService + ComputerControlService + ReminderScheduler` 这一套本地单进程结构。存储层新增轻量 SQLite 基础设施，并按“源数据表 + 运行态文档表 + 双写影子校验 + 分域切读”的方式推进；派生摘要和设置文件先不激进迁库，但其上游输入、事件流和回退门禁必须纳入计划。

**Tech Stack:** Python 3.9 `sqlite3` 标准库，SQLite 3.43.2，WAL 模式，`STRICT` tables，`PRAGMA user_version` 版本管理，现有 `aiohttp` / `SessionManager` / `AppResourceService` / `ReminderScheduler` / `ExperienceService` / `ComputerControlService` / Flutter App runtime/event-stream。

---

## 本次计划更新

- [x] 2026-04-14：重新调研前后端，补齐 `experience_state.json`、`computer_control_actions.json`、`app_settings.json` / `app_secrets.json`、`todo_summary.json` / `calendar_summary.json`、`planning.changed` / `todo.summary.changed` / `calendar.summary.changed` 以及 Flutter `Agenda / Tasks / Home / Control Center / Chat / Settings` 依赖面。

## 范围与约束

### 本计划的分层范围

- **Layer A: 主线热路径，必须迁库**
  - `server/workspace/sessions/*.jsonl`
  - `server/workspace/runtime/tasks.json`
  - `server/workspace/runtime/events.json`
  - `server/workspace/runtime/reminders.json`
  - `server/workspace/runtime/notifications.json`
  - reminder 当前混在 reminder payload 里的 runtime 字段：`next_trigger_at / last_triggered_at / last_error / snoozed_until / completed_at / status`

- **Layer B: 关键运行态对象，纳入同一轮计划，不再遗漏**
  - `server/workspace/runtime/experience_state.json`
  - `server/workspace/runtime/computer_control_actions.json`

- **Layer C: 派生缓存与配置，不作为第一批 source-of-truth 迁移目标，但必须纳入兼容设计**
  - `server/workspace/runtime/todo_summary.json`
  - `server/workspace/runtime/calendar_summary.json`
  - `server/workspace/runtime/app_settings.json`
  - `server/workspace/runtime/app_secrets.json`

- **Layer D: 明确保留文件形态，不在本计划内迁库**
  - `server/workspace/memory/MEMORY.md`
  - `server/workspace/memory/HISTORY.md`

### 关键约束

- 不改变前端页面结构，不顺手改 UI 风格。
- 不改变现有 HTTP / WebSocket payload 口径，不让 Flutter 端为了换存储而被迫改接口。
- 不把所有 JSON 一次性灭掉，而是按数据域拆分切换节奏。
- `todo_summary.json` / `calendar_summary.json` 第一阶段继续作为派生缓存存在，但其上游输入必须改成走 SQLite 读取链路。
- `app_settings.json` / `app_secrets.json` 第一阶段继续保持 JSON object store，原因是这两者不属于当前最热写路径，且 `app_secrets` 需要单独安全策略评审。
- 执行阶段按仓库规则推进：先汇报修改文件，等你确认后再跑测试、再 git。

## 调研结论摘要

### 后端现状

- `server/nanobot/session/manager.py`
  - `SessionManager.save()` 每次都重写 metadata + 全量消息到单个 `.jsonl`。
  - `list_sessions()` / `get()` / `_load()` 仍是文件级读写模型。

- `server/services/app_api/json_store.py`
  - `JsonCollectionStore` / `JsonObjectStore` 都是“整份读 -> 内存改 -> 整份写回”。
  - `tasks / events / notifications / reminders / app_settings / app_secrets / experience_state` 全都复用了这套模式。

- `server/services/app_api/resource_service.py`
  - `tasks / events / notifications / reminders` 目前还是 JSON collection store。
  - reminder runtime 字段直接混在 reminder 主记录里。
  - `notifications.metadata` 仍以 JSON 对象嵌套保存，linked id / source 字段只是写入 metadata，没有实体化索引。

- `server/services/reminder_scheduler.py`
  - `sync_all()` 和 `_process_due_reminders()` 都会把 `reminder_store.list_items()` 整份读出来再逐条判断。
  - reminder 触发后要同时写 notification 和 reminder 状态，但当前没有真正的数据库事务边界。

- `server/services/app_runtime.py`
  - `_planning_inputs()` 直接读 `self.resources.task_store / event_store / reminder_store / notification_store` 的底层实现。
  - `refresh_planning_state()` 会基于全量输入重算 overview / timeline / conflicts，再把 `todo_summary.json` 和 `calendar_summary.json` 整份重写。
  - 运行态事件流依赖这些数据源持续广播：
    - `task.*`
    - `event.*`
    - `notification.*`
    - `reminder.*`
    - `planning.changed`
    - `todo.summary.changed`
    - `calendar.summary.changed`

- `server/services/experience/store.py`
  - `experience_state.json` 是一个整对象存储。
  - 包含 `runtime_override`、`last_interaction_result`、`interaction_history`、`interaction_throttle`、`daily_shake_state`。
  - 这条链虽然不是海量数据，但每次交互、节流触发、shake 状态更新都可能整对象写回。

- `server/services/computer_control/store.py`
  - `computer_control_actions.json` 是一个整集合存储。
  - `save()`、`list_recent()`、`list_pending()` 都依赖全量加载和排序。
  - `trim` 逻辑还要求保留 pending action，不能只按时间粗暴截断。

- `server/services/app_api/settings_service.py`
  - `app_settings.json` 与 `app_secrets.json` 仍是 JsonObjectStore。
  - 这条链会影响 bootstrap / settings 页面，但不属于当前最高频写路径。

- `server/nanobot/agent/memory.py`
  - 长期记忆仍写 `MEMORY.md` / `HISTORY.md`。
  - 这条链不适合和本轮热路径迁库混做。

### 当前磁盘实际情况

- `server/workspace/runtime/` 当前已存在：
  - `app_settings.json`
  - `calendar_summary.json`
  - `computer_control_actions.json`
  - `events.json`
  - `experience_state.json`
  - `tasks.json`
  - `todo_summary.json`
- `notifications.json` 和 `reminders.json` 当前目录里没看到，但 `AppResourceService` 仍定义了这两个 store。
- 结论：这两类文件是“逻辑上存在、运行时按需创建”的 lazy file，不应因为当前文件不存在就被计划漏掉。

### 前端依赖面

- `app/lib/models/connect/bootstrap_model.dart`
  - bootstrap 已经解析 `planning`、`desktop_voice`、`computer_control`、`computer_actions`、`experience` 等能力位。

- `app/lib/models/home/runtime_state_model.dart`
  - runtime state 已经解析：
    - 当前任务与任务队列
    - 设备状态与语音 runtime
    - `experience`
    - `todo_summary`
    - `calendar_summary`
    - reminders runtime 视图

- `app/lib/providers/app_providers.dart`
  - 通过 WebSocket 消费并增量合并：
    - `runtime.task.*`
    - `task.*`
    - `event.*`
    - `notification.*`
    - `reminder.*`
    - `planning.changed`
    - `todo.summary.changed`
    - `calendar.summary.changed`
    - `runtime.experience.updated`
    - `computer.action.*`
  - 也就是说，后端不只是要“存进去”，还要保证实时事件与 payload 形状稳定。

- `app/lib/models/planning/planning_agenda_entry_model.dart`
  - Agenda 不是单独一套后端存储，而是前端把 `tasks / events / reminders / planningTimeline` 再拼成 `PlanningAgendaDataset`。
  - 只要 `task/event/reminder` 的字段或时序错了，`Agenda` 页面就会直接失真。

- 直接受影响的前端页面：
  - `app/lib/screens/agenda/agenda_screen.dart`
  - `app/lib/screens/tasks/tasks_screen.dart`
  - `app/lib/screens/home/home_screen.dart`
  - `app/lib/screens/control_center/control_center_screen.dart`
  - `app/lib/screens/chat/chat_screen.dart`
  - `app/lib/services/settings/settings_service.dart`

## 迁移目标与成功判据

- 后端对外接口保持兼容：
  - `GET/POST/PATCH/DELETE /api/app/v1/tasks`
  - `GET/POST/PATCH/DELETE /api/app/v1/events`
  - `GET/PATCH/DELETE /api/app/v1/notifications`
  - `GET/POST/PATCH/DELETE /api/app/v1/reminders`
  - `GET /api/app/v1/runtime/state`
  - `GET /api/app/v1/bootstrap`
  - WebSocket `event_type` 与 payload 结构

- 热路径切到 SQLite 后，下面这些行为不能退化：
  - session list 不再整会话重读，但 `summary / last_message_at / message_count` 结果与当前一致。
  - reminder 不重复触发、不漏触发，`snoozed_until / completed_at / overdue` 语义保持不变。
  - `todo_summary` / `calendar_summary` 仍然会随着 task / event / reminder 变化实时刷新。
  - Control Center 的 recent / pending computer actions 保持排序与 pending 保留语义。
  - Experience runtime state 的 `runtime_override / last_interaction_result / interaction_history / daily_shake_state` 不丢字段。

- 切库上线门禁：
  - 导入计数一致。
  - `PRAGMA quick_check` 通过。
  - `PRAGMA foreign_key_check` 通过。
  - dual 模式 shadow diff 为 0。
  - 关键 API 响应与关键事件流 payload 对比通过。

## 存储设计

### SQLite 文件与基础策略

- 主库路径：`server/workspace/state.sqlite3`
- sidecar：`state.sqlite3-wal`、`state.sqlite3-shm`
- 连接初始化统一执行：
  - `PRAGMA journal_mode=WAL;`
  - `PRAGMA foreign_keys=ON;`
  - `PRAGMA busy_timeout=5000;`
  - `PRAGMA synchronous=NORMAL;`
  - `PRAGMA temp_store=MEMORY;`
- schema 版本由 `PRAGMA user_version` 管理。
- cutover 前用 `sqlite3.backup()` 生成 `state.sqlite3.bak`。

### 表设计总览

#### `sessions`

- 作用：会话列表热字段。
- 推荐字段：
  - `session_id TEXT PRIMARY KEY`
  - `channel TEXT NOT NULL`
  - `created_at TEXT NOT NULL`
  - `updated_at TEXT NOT NULL`
  - `title TEXT NOT NULL`
  - `title_source TEXT NOT NULL`
  - `pinned INTEGER NOT NULL`
  - `archived INTEGER NOT NULL`
  - `message_count INTEGER NOT NULL`
  - `last_message_at TEXT`
  - `summary_preview TEXT`
  - `last_consolidated_seq INTEGER`
  - `metadata_json TEXT NOT NULL`

#### `session_messages`

- 作用：真实消息流，不再整份重写。
- 推荐字段：
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE`
  - `message_seq INTEGER NOT NULL`
  - `message_id TEXT`
  - `role TEXT NOT NULL`
  - `created_at TEXT NOT NULL`
  - `visible INTEGER NOT NULL`
  - `content_text TEXT`
  - `task_id TEXT`
  - `client_message_id TEXT`
  - `source_channel TEXT`
  - `interaction_surface TEXT`
  - `capture_source TEXT`
  - `app_session_id TEXT`
  - `raw_json TEXT NOT NULL`
- 索引：
  - `UNIQUE(session_id, message_seq)`
  - `INDEX(session_id, created_at DESC)`
  - `INDEX(session_id, message_id)`

#### `tasks`

- 保留当前公开字段与 planning metadata：
  - `task_id`
  - `title`
  - `description`
  - `priority`
  - `completed`
  - `due_at`
  - `bundle_id`
  - `created_via`
  - `source_channel`
  - `source_message_id`
  - `source_session_id`
  - `interaction_surface`
  - `capture_source`
  - `voice_path`
  - `linked_task_id`
  - `linked_event_id`
  - `linked_reminder_id`
  - `created_at`
  - `updated_at`
- 索引：
  - `(completed, priority, updated_at DESC)`
  - `(due_at)`

#### `events`

- 保留当前公开字段与 planning metadata：
  - `event_id`
  - `title`
  - `start_at`
  - `end_at`
  - `description`
  - `location`
  - 同一套 planning metadata
  - `created_at`
  - `updated_at`
- 索引：
  - `(start_at, end_at)`
  - `(updated_at DESC)`

#### `notifications`

- 推荐字段：
  - `notification_id`
  - `type`
  - `priority`
  - `title`
  - `message`
  - `read`
  - `task_id`
  - `event_id`
  - `reminder_id`
  - `bundle_id`
  - `source_channel`
  - `source_message_id`
  - `source_session_id`
  - `interaction_surface`
  - `capture_source`
  - `voice_path`
  - `metadata_json`
  - `created_at`
  - `updated_at`
- 设计要点：
  - 继续兼容 `metadata` 返回格式。
  - 但 linked id / source 字段必须实体化列，避免每次都解整个 metadata JSON。

#### `reminders`

- 放静态字段：
  - `reminder_id`
  - `title`
  - `message`
  - `time`
  - `repeat`
  - `enabled`
  - 全套 planning metadata
  - `created_at`
  - `updated_at`

#### `reminder_runtime`

- 单独放高频变化字段：
  - `reminder_id TEXT PRIMARY KEY REFERENCES reminders(reminder_id) ON DELETE CASCADE`
  - `next_trigger_at TEXT`
  - `last_triggered_at TEXT`
  - `last_error TEXT`
  - `snoozed_until TEXT`
  - `completed_at TEXT`
  - `status TEXT`
- 索引：
  - `(next_trigger_at)`
  - `(status, next_trigger_at)`
  - `(snoozed_until)`

#### `computer_actions`

- 作用：承接 `computer_control_actions.json` 的 recent / pending 查询。
- 推荐字段：
  - `action_id TEXT PRIMARY KEY`
  - `kind TEXT NOT NULL`
  - `status TEXT NOT NULL`
  - `risk_level TEXT NOT NULL`
  - `requires_confirmation INTEGER NOT NULL`
  - `requested_via TEXT NOT NULL`
  - `source_session_id TEXT`
  - `summary TEXT`
  - `confirmed_at TEXT`
  - `created_at TEXT NOT NULL`
  - `updated_at TEXT NOT NULL`
  - `payload_json TEXT NOT NULL`
- 索引：
  - `(status, updated_at DESC)`
  - `(updated_at DESC)`

#### `runtime_documents`

- 作用：承接对象型运行态，不强行过度表结构化。
- 推荐字段：
  - `namespace TEXT PRIMARY KEY`
  - `payload_json TEXT NOT NULL`
  - `updated_at TEXT NOT NULL`
- 第一批 namespace：
  - `experience_state`
- 预留但第一阶段不启用的 namespace：
  - `todo_summary`
  - `calendar_summary`
  - `app_settings_overlay`
  - `app_secrets`

#### `import_manifest`

- 记录：
  - `schema_version`
  - `domain`
  - `source_path`
  - `source_mtime`
  - `source_checksum`
  - `source_count`
  - `imported_count`
  - `imported_at`

### 服务边界调整

- `SessionManager` 保持 public API 不变，但内部改为 `json | dual | sqlite` 可切换 backend。
- `AppResourceService` 不能再让 `AppRuntimeService` 直接摸 `task_store / event_store / reminder_store / notification_store` 这种具体实现。
  - 需要新增明确的 store-agnostic 读取接口，例如：
    - `list_task_items()`
    - `list_event_items()`
    - `list_reminder_items()`
    - `list_notification_items()`
    - 或 `planning_inputs()`
- `ExperienceStore` 保持现有方法签名，后端实现从 JsonObjectStore 切成 SQLite document store。
- `ComputerActionStore` 保持 `save / get / list_recent / list_pending` 语义不变，底层切到 SQLite。
- `todo_summary.json` / `calendar_summary.json` 第一阶段仍由 `AppRuntimeService` 写文件，但输入源统一改成新的 store-agnostic 接口。

## 迁移策略

### 分域切换，而不是一个总开关

- `session_storage_mode = json | dual | sqlite`
- `planning_storage_mode = json | dual | sqlite`
- `experience_storage_mode = json | dual | sqlite`
- `computer_action_storage_mode = json | dual | sqlite`

原因：

- session 与 planning 是最高风险主线，必须先收敛。
- experience / computer action 虽然也该纳入计划，但它们的切换节奏不应该和 session 完全绑死。
- settings / secrets 暂不加入这一组切换开关。

### 导入源

- session：
  - `server/workspace/sessions/*.jsonl`
  - `~/.nanobot/sessions/*.jsonl`
- planning resources：
  - `server/workspace/runtime/tasks.json`
  - `server/workspace/runtime/events.json`
  - `server/workspace/runtime/reminders.json`
  - `server/workspace/runtime/notifications.json`
- operational runtime：
  - `server/workspace/runtime/experience_state.json`
  - `server/workspace/runtime/computer_control_actions.json`

### 导入方式

1. 建临时库 `state.sqlite3.tmp`
2. 导入各 domain 数据
3. 写 `import_manifest`
4. 跑 `quick_check`、`foreign_key_check`、计数对账
5. 校验通过后原子替换正式库

### Dual 模式策略

- 第一阶段：
  - 读继续走 JSON / JSONL
  - 写变成 `JSON primary + SQLite shadow`
- 第二阶段：
  - 先切 `planning` / `session` 到 `SQLite primary + JSON shadow`
  - `experience` / `computer_action` 单独按域切换
- 第三阶段：
  - shadow diff 稳定为 0 后关闭 JSON shadow

### 回退策略

- 切换期间保留 JSON shadow 写。
- 回退只切配置，不重新导入。
- 任一 domain 出现以下问题立即回退该 domain：
  - shadow diff 非 0
  - reminder 重复触发 / 漏触发
  - session 分页 cursor 异常
  - session metadata 丢失
  - `runtime.experience.updated` payload 丢字段
  - computer action recent / pending 排序错乱

## 文件落点总览

### 新增

- `server/nanobot/storage/sqlite_db.py`
- `server/nanobot/storage/migrations.py`
- `server/nanobot/storage/sqlite_documents.py`
- `server/nanobot/session/sqlite_backend.py`
- `server/nanobot/session/jsonl_importer.py`
- `server/services/app_api/sqlite_store.py`
- `server/services/app_api/json_importer.py`
- `server/services/computer_control/sqlite_store.py`
- `server/services/experience/sqlite_store.py`
- `server/tests/test_session_sqlite_backend.py`
- `server/tests/test_runtime_sqlite_store.py`
- `server/tests/test_storage_migration.py`
- `server/tests/test_experience_store_sqlite.py`
- `server/tests/test_computer_control_sqlite_store.py`

### 修改

- `server/bootstrap.py`
- `server/nanobot/session/manager.py`
- `server/nanobot/agent/loop.py`
- `server/nanobot/agent/memory.py`
- `server/services/app_runtime.py`
- `server/services/app_api/resource_service.py`
- `server/services/app_api/settings_service.py`
- `server/services/reminder_scheduler.py`
- `server/services/experience/store.py`
- `server/services/experience/service.py`
- `server/services/computer_control/store.py`
- `server/services/computer_control/service.py`
- `server/tests/test_session_manager_atomic.py`
- `server/tests/test_app_api_services.py`
- `server/tests/test_app_runtime.py`
- `server/tests/test_reminder_scheduler.py`
- `server/tests/test_experience_service.py`
- `server/tests/test_computer_control_service.py`

### 只做兼容验证，不预期修改

- `app/lib/models/connect/bootstrap_model.dart`
- `app/lib/models/home/runtime_state_model.dart`
- `app/lib/models/planning/planning_agenda_entry_model.dart`
- `app/lib/providers/app_providers.dart`
- `app/lib/screens/agenda/agenda_screen.dart`
- `app/lib/screens/tasks/tasks_screen.dart`
- `app/lib/screens/control_center/control_center_screen.dart`
- `app/lib/services/home/runtime_service.dart`
- `app/lib/services/settings/settings_service.dart`

## Subagent 分工建议

### Worker A: SQLite 基础设施与 Session Backend

- 负责文件：
  - `server/nanobot/storage/*`
  - `server/nanobot/session/*`
  - `server/tests/test_session_*`
  - `server/tests/test_storage_migration.py`
- 目标：
  - 建库、schema、migration runner、JSONL importer、Session SQLite backend。

### Worker B: Planning Resource Store 与 Reminder Runtime

- 负责文件：
  - `server/services/app_api/sqlite_store.py`
  - `server/services/app_api/json_importer.py`
  - `server/services/app_api/resource_service.py`
  - `server/services/reminder_scheduler.py`
  - `server/tests/test_runtime_sqlite_store.py`
  - `server/tests/test_app_api_services.py`
  - `server/tests/test_reminder_scheduler.py`
- 目标：
  - `tasks / events / notifications / reminders / reminder_runtime` 切库。

### Worker C: Experience / Computer Control 运行态存储

- 负责文件：
  - `server/nanobot/storage/sqlite_documents.py`
  - `server/services/experience/store.py`
  - `server/services/experience/service.py`
  - `server/services/experience/sqlite_store.py`
  - `server/services/computer_control/store.py`
  - `server/services/computer_control/service.py`
  - `server/services/computer_control/sqlite_store.py`
  - `server/tests/test_experience_service.py`
  - `server/tests/test_experience_store_sqlite.py`
  - `server/tests/test_computer_control_service.py`
  - `server/tests/test_computer_control_sqlite_store.py`
- 目标：
  - 让 `experience_state` 与 `computer_control_actions` 也进入 SQLite 主线。

### Main Thread: AppRuntime 集成、契约门禁与切读

- 负责文件：
  - `server/bootstrap.py`
  - `server/services/app_runtime.py`
  - `server/nanobot/agent/loop.py`
  - `server/nanobot/agent/memory.py`
  - `server/services/app_api/settings_service.py`
  - `server/tests/test_app_runtime.py`
  - `server/tests/test_storage_migration.py`
- 目标：
  - 统一切换开关、AppRuntime 读路径、summary 刷新、事件流兼容、bootstrap/runtime 契约门禁。

### 并行冲突控制

- `server/services/app_runtime.py` 只允许 Main Thread 改，避免和 Worker B / Worker C 冲突。
- `server/services/app_api/resource_service.py` 只允许 Worker B 改。
- `server/services/experience/service.py` 与 `server/services/computer_control/service.py` 只允许 Worker C 改。
- Subagent 不得互相回滚他人改动；发现冲突时只做兼容调整并汇报。

## 实施任务

### Task 0: 补齐最新数据链路调研

**Files:**
- Verify: `server/nanobot/session/manager.py`
- Verify: `server/services/app_api/resource_service.py`
- Verify: `server/services/app_runtime.py`
- Verify: `server/services/reminder_scheduler.py`
- Verify: `server/services/experience/store.py`
- Verify: `server/services/computer_control/store.py`
- Verify: `server/services/app_api/settings_service.py`
- Verify: `app/lib/models/home/runtime_state_model.dart`
- Verify: `app/lib/models/connect/bootstrap_model.dart`
- Verify: `app/lib/models/planning/planning_agenda_entry_model.dart`
- Verify: `app/lib/providers/app_providers.dart`

- [x] 确认旧计划遗漏了 `experience_state.json`、`computer_control_actions.json`、summary cache、settings object store 与前端 Agenda / runtime / bootstrap 依赖面。

### Task 1: 搭 SQLite 基础设施与 schema migration 门禁

**Files:**
- Create: `server/nanobot/storage/sqlite_db.py`
- Create: `server/nanobot/storage/migrations.py`
- Create: `server/nanobot/storage/sqlite_documents.py`
- Modify: `server/bootstrap.py`
- Test: `server/tests/test_storage_migration.py`

- [x] 定义统一连接工厂，集中配置 WAL、`foreign_keys`、`busy_timeout`、`user_version`。
- [x] 建立 schema bootstrap 和 migration runner，不引入 ORM。
- [x] 新增 import manifest、数据库备份、shadow diff 统计与校验 helper。
- [x] 配置层增加分域存储模式开关，默认仍保持 `json`，不改现有行为。

### Task 2: 实现 Session SQLite Backend 与 JSONL Importer

**Files:**
- Create: `server/nanobot/session/sqlite_backend.py`
- Create: `server/nanobot/session/jsonl_importer.py`
- Modify: `server/nanobot/session/manager.py`
- Test: `server/tests/test_session_sqlite_backend.py`
- Test: `server/tests/test_session_manager_atomic.py`

- [x] 设计 `sessions`、`session_messages` 表与索引。
- [x] 实现从 workspace + legacy `~/.nanobot/sessions` 导入。
- [x] 保留 `SessionManager` 公共接口不变，先接 `json -> dual -> sqlite` 三种模式。
- [x] 保证 `raw_json`、`tool_results`、`message_id`、`last_consolidated` 语义不丢。
- [x] 补导入一致性、写失败回滚、legacy 路径兼容测试。

### Task 3: 实现 Planning Resource SQLite Store，并切掉 AppRuntime 对底层 JSON store 的硬耦合

**Files:**
- Create: `server/services/app_api/sqlite_store.py`
- Create: `server/services/app_api/json_importer.py`
- Modify: `server/services/app_api/resource_service.py`
- Modify: `server/services/app_runtime.py`
- Test: `server/tests/test_runtime_sqlite_store.py`
- Test: `server/tests/test_app_api_services.py`
- Test: `server/tests/test_app_runtime.py`

- [x] 设计 `tasks`、`events`、`notifications`、`reminders`、`reminder_runtime` 表。
- [x] 保留 `AppResourceService` 现有 public API 与返回 payload。
- [x] 增加 store-agnostic planning input 接口，禁止 `AppRuntimeService` 继续直摸 `task_store / event_store / reminder_store / notification_store`。
- [x] 导入时兼容 `{\"items\": [...]}` 与裸数组两种 JSON 格式。
- [x] dual 模式下做 `JSON primary + SQLite shadow` 并记录 mismatch。

### Task 4: 重做 Reminder 热路径、派生摘要输入与事务边界

**Files:**
- Modify: `server/services/reminder_scheduler.py`
- Modify: `server/services/app_runtime.py`
- Modify: `server/services/app_api/resource_service.py`
- Test: `server/tests/test_reminder_scheduler.py`
- Test: `server/tests/test_app_runtime.py`
- Test: `server/tests/test_storage_migration.py`

- [x] 把 reminder 的静态定义与 runtime 状态拆表。
- [x] 把“每轮全表扫描 reminders.json”改成“按索引查到期 reminder_runtime”。
- [x] 保证 `create_notification + reminder status update` 在同一事务边界内完成。
- [x] `refresh_planning_state()` 的输入改走新的 planning store 接口。
- [x] `todo_summary.json` / `calendar_summary.json` 第一阶段继续写文件，但上游数据改为从 SQLite 读取。
- [x] 补 `snoozed_until / completed_at / overdue / repeat` 回归测试。

### Task 5: 切 Session 读写热路径，并修正列表 / 分页 / consolidation 语义

**Files:**
- Modify: `server/nanobot/agent/loop.py`
- Modify: `server/nanobot/agent/memory.py`
- Modify: `server/nanobot/session/manager.py`
- Modify: `server/services/app_runtime.py`
- Test: `server/tests/test_app_runtime.py`
- Test: `server/tests/test_session_sqlite_backend.py`

- [x] 把“每轮消息保存”改成事务化 append，不再整份重写。
- [x] 写入事务中同步维护 `message_count`、`last_message_at`、`summary_preview`。
- [x] 用 SQL 支撑 session list、session get、message pagination，避免整会话重读。
- [x] 把 `last_consolidated` 内部改成稳定的 seq 语义，并保持上层接口兼容。
- [x] 补分页 cursor、metadata 回读、memory consolidation off-by-one 回归测试。

### Task 6: 把 `computer_control_actions.json` 切到 SQLite

**Files:**
- Create: `server/services/computer_control/sqlite_store.py`
- Modify: `server/services/computer_control/store.py`
- Modify: `server/services/computer_control/service.py`
- Test: `server/tests/test_computer_control_sqlite_store.py`
- Test: `server/tests/test_computer_control_service.py`
- Test: `server/tests/test_app_runtime.py`

- [x] 用 `computer_actions` 表承接 recent / pending / get / trim 语义。
- [x] 保持 `save / get / list_recent / list_pending` 方法签名不变。
- [x] 保证 pending action 不会因为 trim 被误删。
- [x] 保持 `computer.action.*` 事件 payload 不变。
- [x] 补 recent 排序、pending 保留、awaiting confirmation 状态测试。

### Task 7: 把 `experience_state.json` 切到 SQLite document store

**Files:**
- Create: `server/services/experience/sqlite_store.py`
- Modify: `server/services/experience/store.py`
- Modify: `server/services/experience/service.py`
- Test: `server/tests/test_experience_store_sqlite.py`
- Test: `server/tests/test_experience_service.py`
- Test: `server/tests/test_app_runtime.py`

- [x] 用 `runtime_documents(namespace='experience_state')` 承接 ExperienceStore 当前整对象语义。
- [x] 保持 `runtime_override / last_interaction_result / interaction_history / interaction_throttle / daily_shake_state` 的现有读写接口。
- [x] 不在这一轮强行把 experience 对象拆成很多张表，先保住兼容与原子性。
- [x] 保持 `runtime.experience.updated` payload 结构不变。
- [x] 补 interaction history 截断、节流时间戳、daily shake reset/record 测试。

### Task 8: 切读门禁、前端契约校验与观测

**Files:**
- Modify: `server/bootstrap.py`
- Modify: `server/services/app_runtime.py`
- Modify: `server/services/app_api/settings_service.py`
- Test: `server/tests/test_app_runtime.py`
- Test: `server/tests/test_storage_migration.py`
- Verify: `app/lib/models/connect/bootstrap_model.dart`
- Verify: `app/lib/models/home/runtime_state_model.dart`
- Verify: `app/lib/models/planning/planning_agenda_entry_model.dart`
- Verify: `app/lib/providers/app_providers.dart`

- [x] 让 bootstrap / runtime state / WebSocket 继续输出相同 payload。
- [x] 增加最小观测：当前 schema version、各 domain storage mode、shadow failure 计数、mismatch 计数、最近导入时间。
- [ ] 切库门禁至少覆盖：导入计数一致、`quick_check`、`foreign_key_check`、关键 API diff、关键事件 diff。
- [ ] 明确 Agenda / Tasks / Home / Control Center 的手工验收清单。
- [ ] 稳定期结束前保留 JSON shadow，确保一键回退。

### Task 9: Settings / Secrets / Summary cache 的后续决策门

**Files:**
- Modify: `server/services/app_api/settings_service.py`
- Modify: `server/services/app_runtime.py`
- Modify: `功能讨论区/TODO/2026-04-11-JSON与JSONL热路径迁移到SQLite实施计划.md`

- [ ] P1 稳定后再决定是否把 `app_settings.json` 迁到 `runtime_documents`。
- [ ] `app_secrets.json` 是否迁库，必须先出单独安全方案；未评审前不动。
- [ ] `todo_summary.json` / `calendar_summary.json` 是否彻底去文件化，等 planning query 稳定后再决定。

## 验证策略

- 当前这轮只更新计划，不跑测试。
- 真正执行时，等你确认代码文件后再跑下面这些验证：

```bash
cd /Users/mandy/Documents/GitHub/AI-bot/server
python3 -m unittest \
  tests.test_session_manager_atomic \
  tests.test_session_sqlite_backend \
  tests.test_app_api_services \
  tests.test_runtime_sqlite_store \
  tests.test_reminder_scheduler \
  tests.test_computer_control_service \
  tests.test_computer_control_sqlite_store \
  tests.test_experience_service \
  tests.test_experience_store_sqlite \
  tests.test_app_runtime \
  tests.test_storage_migration
```

- 手工验收重点：
  - session list 的 `summary / last_message_at / message_count` 是否与旧行为一致。
  - `before / after` 分页是否稳定。
  - `tool_results`、`source_channel`、`capture_source`、`app_session_id` 是否完整保留。
  - reminder 是否会重复触发、漏触发、snooze 状态丢失。
  - `planning.changed`、`todo.summary.changed`、`calendar.summary.changed` 是否仍会驱动前端实时刷新。
  - Agenda 页面是否仍能从 `tasks / events / reminders / planningTimeline` 拼出一致数据。
  - Control Center 的 recent / pending computer actions 是否仍正确。
  - experience runtime 的 `last_interaction_result` 与 `daily_shake_state` 是否仍正确。

## 风险清单

- 最大风险不是 SQLite 本身，而是迁移时把“前端依赖的现有语义”弄丢，重点包括：
  - `last_consolidated`
  - session 分页 cursor
  - reminder 触发与重排期
  - summary cache 刷新节奏
  - `runtime.experience.updated` payload
  - `computer.action.*` recent / pending 语义
  - Agenda 对 `task / event / reminder` 时间字段的隐式依赖

- 所以这次计划不再写成“只迁 tasks/events/reminders/notifications 就算完”，而是把 source-of-truth、运行态对象、派生缓存、事件流与前端依赖面一起收进迁移边界。

## 执行建议

- 推荐执行顺序：
  1. Task 1
  2. Task 2
  3. Task 3
  4. Task 4
  5. Task 5
  6. Task 6
  7. Task 7
  8. Task 8
  9. Task 9

- 推荐并行方式：
  - Worker A 与 Worker B 先并行做基础设施和 planning store。
  - Worker C 在 A 的 `sqlite_documents.py` 基础设施落地后再接 experience / computer control。
  - Main Thread 最后集中接 `app_runtime.py`、`bootstrap.py`、切读门禁与回退逻辑。

## 参考资料

- SQLite WAL: `https://sqlite.org/wal.html`
- SQLite STRICT Tables: `https://sqlite.org/stricttables.html`
- SQLite PRAGMA / `user_version` / `foreign_key_check`: `https://www.sqlite.org/pragma.html`
- Python `sqlite3` / `backup()`: `https://docs.python.org/3/library/sqlite3.html`
