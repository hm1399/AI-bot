# JSON / JSONL 热路径迁移到 SQLite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把当前 `session/messages` 与 `task/event/reminder/notification` 这些高频 JSON / JSONL 持久化热路径迁到 SQLite，在不改前端 UI/UX 和不改现有 API 口径的前提下，解决“整份重写、全量读取、提醒全表扫、列表每次重算”的性能与一致性问题。

**Architecture:** 继续保持现有 `aiohttp + AgentLoop + AppRuntimeService` 单进程主干，不上 Redis、不上 PostgreSQL、不上微服务，也不引入 SQLAlchemy/Alembic 这类大框架。存储层新增一个轻量 SQLite 基础设施，先用“双写 + 影子校验 + 分阶段切读”完成平滑迁移；对外 API、事件流、会话行为、提醒语义保持不变。

**Tech Stack:** Python 3.9 `sqlite3` 标准库，SQLite 3.43.2，WAL 模式，`STRICT` tables，`PRAGMA user_version` 版本管理，现有 `aiohttp` / `SessionManager` / `AppResourceService` / `ReminderScheduler` / `AppRuntimeService`。

---

## 范围与约束

- 本轮只迁热路径：
  - `workspace/sessions/*.jsonl`
  - `workspace/runtime/tasks.json`
  - `workspace/runtime/events.json`
  - `workspace/runtime/notifications.json`
  - `workspace/runtime/reminders.json`
- 本轮不迁冷路径：
  - `app_settings.json`
  - `app_secrets.json`
  - `todo_summary.json`
  - `calendar_summary.json`
  - `MEMORY.md`
  - `HISTORY.md`
- 不改变前端页面结构，不顺手改 UI 风格。
- 不改变现有 HTTP / WebSocket 契约，不让 Flutter 端因为换库而跟着改接口。
- 不在第一阶段上搜索、统计、全文检索等“顺手增强”能力，先把读写和迁移稳定做完。
- 执行阶段按仓库规则推进：先汇报改动文件，等你确认后再跑测试、git 提交、关闭 subagent。

## 调研结论摘要

### 本地代码侧结论

- `SessionManager.save()` 现在每次会把 metadata 和全量消息重新写回一个 `.jsonl` 文件，消息越多，单次保存越重。
- `AppRuntimeService` 会反复从 JSON 集合文件全量读 `tasks / events / reminders / notifications`，再在 Python 里排序、过滤、汇总。
- `ReminderScheduler` 现在是固定间隔轮询，再把 reminders 全量扫一遍。
- `AppRuntimeService._list_app_sessions()` 现在会先枚举 session，再把每个 session 整个读进来重算 `summary / last_message_at / message_count`。
- `AgentLoop`、`AppRuntimeService`、`MemoryStore` 都依赖当前 session 的 append-only 语义、`last_consolidated` 语义和消息 metadata 完整透传。

### Web research 结论

- SQLite 官方建议本地并发读写场景优先用 WAL；WAL 模式下读写互相阻塞更少。
- `STRICT` tables 能更早发现脏数据类型，适合替换现在大量“静默吞错”的 JSON 读写。
- `PRAGMA user_version` 适合做轻量 schema migration 门禁，不需要一开始就上 Alembic。
- `PRAGMA quick_check`、`PRAGMA foreign_key_check` 适合放进导入校验门禁。
- Python 标准库 `sqlite3` 已自带 `backup()`，够用来做 cutover 前快照和回滚备份。

## 存储设计

### 数据库文件与基础策略

- 主库路径：`server/workspace/state.sqlite3`
- 保留 SQLite sidecar：`state.sqlite3-wal`、`state.sqlite3-shm`
- 连接初始化统一执行：
  - `PRAGMA journal_mode=WAL;`
  - `PRAGMA foreign_keys=ON;`
  - `PRAGMA busy_timeout=5000;`
  - `PRAGMA synchronous=NORMAL;`
  - `PRAGMA temp_store=MEMORY;`
- schema 版本由 `PRAGMA user_version` 管理。
- cutover 前用 `sqlite3.backup()` 生成 `state.sqlite3.bak`。

### Session 数据拆分

#### `sessions`

- 作用：只放会话级元数据和列表页热字段，避免“列会话列表时再翻整本聊天记录”。
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

- 作用：保存真实消息流，按 session 内顺序查询，不再整份读写。
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

#### Session 设计要点

- `raw_json` 保留完整消息，避免丢 `tool_calls`、`tool_call_id`、`tool_results`、`name` 这类 AgentLoop 真实依赖字段。
- 同时把列表页和分页热字段单独拉平，避免每次反序列化整条消息 JSON。
- `last_consolidated` 不再只靠 Python list index，内部改成 `last_consolidated_seq`；对旧 `Session` 接口继续兼容当前语义。
- `summary_preview`、`last_message_at`、`message_count` 在写入事务里同步更新，列表页不再重扫。

### Runtime 资源拆分

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

- 保留当前公开字段与 planning metadata。
- 索引：
  - `(start_at, end_at)`
  - `(updated_at DESC)`

#### `notifications`

- 保留显式字段：
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
  - `created_at`
  - `updated_at`
  - `metadata_json`
- 索引：
  - `(read, updated_at DESC)`
  - `(reminder_id)`

#### `reminders`

- 放相对静态字段：
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

#### Runtime 设计要点

- `task / event / notification / reminder` 继续维持现有 payload 口径，不让 `AppResourceService` 的 public API 大改。
- `notifications.metadata` 仍保留 JSON 文本，但 linked id 和 source 字段必须拉平成列，避免每次读都解 JSON。
- reminder 拆成“静态定义”和“运行状态”两张表，避免每次触发/贪睡都重写整条 reminder。

### 第一阶段继续保留 JSON 的内容

- `app_settings.json`
- `app_secrets.json`
- `todo_summary.json`
- `calendar_summary.json`
- `MEMORY.md`
- `HISTORY.md`

原因：

- 这些不是当前最热的写路径。
- 先把最重的会话和 planning 资源迁完，收益最大，风险也最容易控。
- summary 文件目前继续作为派生缓存保留，先不在本轮把所有派生逻辑 SQL 化。

## 迁移策略

### 总体切换策略

- 默认先加双配置，而不是“一步到位切主”：
  - `session_storage_mode = json | dual | sqlite`
  - `resource_storage_mode = json | dual | sqlite`
- 第一阶段：
  - 读继续走 JSON / JSONL
  - 写变成 `JSON primary + SQLite shadow`
- 第二阶段：
  - 切成 `SQLite primary + JSON shadow`
- 第三阶段：
  - 稳定后关掉 JSON shadow，只保留 SQLite

### 导入策略

- 会话导入源：
  - `server/workspace/sessions/*.jsonl`
  - `~/.nanobot/sessions/*.jsonl`
- runtime 导入源：
  - `server/workspace/runtime/tasks.json`
  - `server/workspace/runtime/events.json`
  - `server/workspace/runtime/notifications.json`
  - `server/workspace/runtime/reminders.json`
- 导入过程：
  1. 先建临时库 `state.sqlite3.tmp`
  2. 导入全部源数据
  3. 写入 `import_manifest`
  4. 运行计数校验、字段校验、`quick_check`、`foreign_key_check`
  5. 全部通过后原子替换为正式库

### 导入门禁

- 不能只用 `list_sessions()` 做源扫描，因为它会跳过坏 JSONL。
- 对坏源文件，本轮迁移门禁建议 fail-closed：
  - 校验不过就不切读
  - 不允许“静默吞掉坏数据后继续切库”
- manifest 最少记录：
  - schema 版本
  - 源文件路径
  - 文件计数
  - mtime / checksum
  - 导入时间
  - 导入记录数

### 回退策略

- 切到 `sqlite primary` 后，稳定期内继续保留 JSON shadow 写。
- 回退只切配置，不重新导入。
- cutover 前保留 `state.sqlite3.bak`。
- 执行期遇到以下任一情况立即回退到 JSON primary：
  - shadow diff 不为 0
  - reminder 重复触发
  - 会话分页 cursor 异常
  - `last_consolidated` 偏移
  - session metadata 丢失

## 文件落点总览

### 新增

- `server/nanobot/storage/sqlite_db.py`
- `server/nanobot/storage/migrations.py`
- `server/nanobot/session/sqlite_backend.py`
- `server/nanobot/session/jsonl_importer.py`
- `server/services/app_api/sqlite_store.py`
- `server/services/app_api/json_importer.py`
- `server/tests/test_session_sqlite_backend.py`
- `server/tests/test_runtime_sqlite_store.py`
- `server/tests/test_storage_migration.py`

### 修改

- `server/bootstrap.py`
- `server/nanobot/session/manager.py`
- `server/nanobot/agent/loop.py`
- `server/nanobot/agent/memory.py`
- `server/services/app_runtime.py`
- `server/services/app_api/resource_service.py`
- `server/services/reminder_scheduler.py`
- `server/tests/test_session_manager_atomic.py`
- `server/tests/test_app_api_services.py`
- `server/tests/test_app_runtime.py`
- `server/tests/test_reminder_scheduler.py`
- `功能讨论区/TODO/todo.md`

## Subagent 分工建议

### Worker A: SQLite 基础设施与 Session Backend

- 负责文件：
  - `server/nanobot/storage/*`
  - `server/nanobot/session/*`
  - `server/tests/test_session_*`
- 目标：
  - 建库、schema、migrations、JSONL importer、Session SQLite backend、session 原子事务。

### Worker B: Runtime Resource SQLite Store

- 负责文件：
  - `server/services/app_api/sqlite_store.py`
  - `server/services/app_api/json_importer.py`
  - `server/services/app_api/resource_service.py`
  - `server/tests/test_runtime_sqlite_store.py`
  - `server/tests/test_app_api_services.py`
- 目标：
  - 把 `tasks / events / notifications / reminders` 的 CRUD 换成 SQLite 后端，并保留 payload 口径。

### Worker C: Reminder Scheduler 与事务语义

- 负责文件：
  - `server/services/reminder_scheduler.py`
  - `server/tests/test_reminder_scheduler.py`
- 目标：
  - 把 reminder runtime 独立成热表，改成索引查找到期项，保证提醒投递与状态更新在同一事务边界内。

### Main Thread: 集成与切读门禁

- 负责文件：
  - `server/bootstrap.py`
  - `server/services/app_runtime.py`
  - `server/nanobot/agent/loop.py`
  - `server/nanobot/agent/memory.py`
  - `server/tests/test_app_runtime.py`
  - `server/tests/test_storage_migration.py`
- 目标：
  - 接存储模式配置、双写逻辑、AppRuntime 集成、分页与 session list 切读、导入/回退门禁。

## 实施任务

### Task 1: 搭 SQLite 基础设施与迁移门禁

**Files:**
- Create: `server/nanobot/storage/sqlite_db.py`
- Create: `server/nanobot/storage/migrations.py`
- Modify: `server/bootstrap.py`
- Test: `server/tests/test_storage_migration.py`

- [ ] 定义统一连接工厂，集中配置 WAL、`foreign_keys`、`busy_timeout`、`user_version`。
- [ ] 建立 schema bootstrap 和 migration runner，不引入 ORM。
- [ ] 新增存储模式配置，默认保持 `json`，不改变当前运行行为。
- [ ] 新增 import manifest、数据库备份、校验 helper。

### Task 2: 实现 Session SQLite Backend 与 JSONL Importer

**Files:**
- Create: `server/nanobot/session/sqlite_backend.py`
- Create: `server/nanobot/session/jsonl_importer.py`
- Modify: `server/nanobot/session/manager.py`
- Test: `server/tests/test_session_sqlite_backend.py`
- Test: `server/tests/test_session_manager_atomic.py`

- [ ] 设计 `sessions`、`session_messages` 表和必要索引。
- [ ] 实现从 metadata-first JSONL 与 legacy `~/.nanobot/sessions` 导入的逻辑。
- [ ] 保留 `SessionManager` 公共接口不变，先接入 `json -> dual -> sqlite` 三种模式。
- [ ] 保证 `raw_json`、`tool_results`、`message_id`、`last_consolidated` 语义不丢。
- [ ] 补导入一致性、写失败回滚、legacy 路径兼容测试。

### Task 3: 切 Session 写热路径，再切读热路径

**Files:**
- Modify: `server/nanobot/agent/loop.py`
- Modify: `server/nanobot/agent/memory.py`
- Modify: `server/services/app_runtime.py`
- Modify: `server/nanobot/session/manager.py`
- Test: `server/tests/test_app_runtime.py`
- Test: `server/tests/test_agent_loop.py`

- [ ] 把“每轮消息保存”改成事务化 append，而不是全量重写。
- [ ] 写入事务里同步更新 `message_count`、`last_message_at`、`summary_preview`。
- [ ] 用 SQL 支撑 session list、session get、message pagination，避免整会话重读。
- [ ] 把 `last_consolidated` 内部改成更稳定的 seq 语义，同时对现有上层接口保持兼容。
- [ ] 补分页、metadata 回读、memory consolidation off-by-one 回归测试。

### Task 4: 实现 Runtime Resource SQLite Store

**Files:**
- Create: `server/services/app_api/sqlite_store.py`
- Create: `server/services/app_api/json_importer.py`
- Modify: `server/services/app_api/resource_service.py`
- Test: `server/tests/test_runtime_sqlite_store.py`
- Test: `server/tests/test_app_api_services.py`

- [ ] 设计 `tasks`、`events`、`notifications`、`reminders`、`reminder_runtime` 表。
- [ ] 保留 `AppResourceService` 现有 public API 与返回 payload。
- [ ] 从旧 JSON payload 导入时兼容 `{\"items\": [...]}` 和裸数组两种格式。
- [ ] 在 dual 模式下做 JSON primary + SQLite shadow，并记录 mismatch。
- [ ] 补 CRUD、一致性、shadow failure、notification alias 保留测试。

### Task 5: 重做 Reminder 热路径与调度查询

**Files:**
- Modify: `server/services/reminder_scheduler.py`
- Modify: `server/services/app_api/resource_service.py`
- Test: `server/tests/test_reminder_scheduler.py`
- Test: `server/tests/test_storage_migration.py`

- [ ] 把 reminder 的静态定义与 runtime 状态拆开存。
- [ ] 把“每轮全表扫描”改成“按索引查到期且启用的 reminder”。
- [ ] 保证 `create_notification + reminder status update` 同事务完成。
- [ ] 保持现有语义不变：`snoozed_until` 优先、`once` 触发后仍可回到 `overdue`、重复 reminder 正确重排期。
- [ ] 补重启去重、snooze/completed 状态保留、重复触发保护测试。

### Task 6: 集成 Planning 读取与切读门禁

**Files:**
- Modify: `server/services/app_runtime.py`
- Modify: `server/bootstrap.py`
- Modify: `server/services/app_api/resource_service.py`
- Test: `server/tests/test_app_runtime.py`
- Test: `server/tests/test_storage_migration.py`

- [ ] 让 `planning overview / timeline / conflicts` 的输入改从 SQLite 读。
- [ ] `todo_summary.json`、`calendar_summary.json` 暂时继续保留为派生缓存，不在本轮推翻。
- [ ] 先上线 dual 模式，观察 shadow diff 为 0 后再切 `sqlite primary`。
- [ ] 切库门禁至少覆盖：导入计数一致、`quick_check` 通过、`foreign_key_check` 通过、关键 API 对比通过。
- [ ] 保留 JSON shadow 直到稳定期结束，确保一键回退。

### Task 7: 收尾、观测与清理

**Files:**
- Modify: `server/bootstrap.py`
- Modify: `server/services/app_runtime.py`
- Modify: `功能讨论区/TODO/todo.md`

- [ ] 增加最小观测：当前存储模式、shadow failure 计数、mismatch 计数、导入时间、schema version。
- [ ] 明确稳定期结束条件，再决定是否移除 JSON shadow。
- [ ] 只在稳定后再考虑移除旧 JSON / JSONL 写路径，不在第一轮就删干净。
- [ ] 把执行中确认完成的任务改成 `- [x]`。

## 验证策略

- 当前这轮只写计划，不跑测试。
- 真正执行时，先等你确认代码文件，再跑下面这些验证：

```bash
cd /Users/mandy/Documents/GitHub/AI-bot/server
python3 -m unittest \
  tests.test_session_manager_atomic \
  tests.test_session_sqlite_backend \
  tests.test_app_api_services \
  tests.test_runtime_sqlite_store \
  tests.test_reminder_scheduler \
  tests.test_app_runtime \
  tests.test_storage_migration
```

- 手工验收重点：
  - session list 的 `summary / last_message_at / message_count` 是否与旧行为一致
  - `before / after` 分页是否稳定
  - `tool_results`、`source_channel`、`capture_source`、`app_session_id` 是否完整保留
  - reminder 是否会重复触发、漏触发、snooze 状态丢失
  - `JSON primary + SQLite shadow` 和 `SQLite primary + JSON shadow` 两个阶段都能正常回退

## 风险清单

- 最大风险不是“SQLite 不够快”，而是迁移过程把现有语义搞丢，尤其是：
  - `last_consolidated`
  - session 分页 cursor
  - session metadata
  - reminder 去重与重排期
  - notification metadata alias
- 所以这次计划刻意不追求“把所有 JSON 一次性灭掉”，而是先把热路径迁稳，再看冷路径值不值得继续迁。

## 执行建议

- 推荐执行顺序：
  1. Task 1
  2. Task 2
  3. Task 3
  4. Task 4
  5. Task 5
  6. Task 6
  7. Task 7
- 推荐并行方式：
  - Worker A 与 Worker B 可以先并行做各自新 backend 和测试
  - Main Thread 最后集中接 `app_runtime.py`、`bootstrap.py`、`loop.py`
  - ReminderScheduler 等到 runtime store 落稳后再接，避免三方同时改调度语义

## 参考资料

- SQLite WAL: `https://sqlite.org/wal.html`
- SQLite STRICT Tables: `https://sqlite.org/stricttables.html`
- SQLite PRAGMA / `user_version` / `foreign_key_check`: `https://www.sqlite.org/pragma.html`
- Python `sqlite3` / `backup()`: `https://docs.python.org/3/library/sqlite3.html`
