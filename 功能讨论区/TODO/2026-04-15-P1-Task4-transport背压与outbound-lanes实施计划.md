# P1 Task 4 transport 背压与 outbound lanes 实施计划

> 任务范围：仅实现 `server/nanobot/bus/queue.py`、`server/services/outbound_router.py`，以及按需新增 `server/services/app_event_fanout.py`、`server/services/outbound_lanes.py`。  
> 当前用户约束：不编辑 `server/services/app_runtime.py`、`server/main.py`；不跑测试；不做 git commit。

## 目标

- 为 `MessageBus` 建立第一版有界背压能力，避免普通流量把关键控制消息完全挤爆。
- 让 observer 不再阻塞主入队路径，同时补上最小可观测指标。
- 把 outbound router 从“单串行消费后立刻发送”改成“总线消费 + lane 分发 + lane 内串行发送”，隔离 `device / desktop_voice / external_channels` 的慢 transport。
- 预留 App WebSocket fanout 所需的通用 helper，但本轮不直接接到 `AppRuntimeService`。

## 设计摘要

### 1. MessageBus

- 入站 / 出站都改成“普通队列 + 关键控制保留队列”的双层结构。
- `consume_*()` 优先消费保留队列，再消费普通队列。
- `publish_*()` 在主路径上只做：
  - 判定消息是否属于关键控制类；
  - 写入对应队列；
  - 递增统计；
  - 异步调度 observer 通知。
- observer 失败只记录日志，不反向影响 publish。

### 2. outbound lanes

- 新增通用 lane worker，负责：
  - lane 本地有界队列；
  - backlog / drop / dispatch 计数；
  - lane 内串行处理；
  - 对外暴露 snapshot，供后续 runtime 接线。
- `UnifiedOutboundRouter.run()` 只保留“从 bus 取消息并投递到 lane”的职责。
- 具体 transport 发送仍沿用现有 `route()` 逻辑，确保接口向后兼容。

### 3. app ws fanout helper

- 只新增可复用 helper，不接入 runtime。
- helper 提供：
  - per-client writer queue；
  - fanout enqueue；
  - client 级 drop / closed 统计；
  - 保留关键事件与可丢弃事件的基础钩子。

## 任务清单

- [x] Task 1：在 `queue.py` 实现有界 bus、关键保留位、非阻塞 observer 与统计接口。
- [x] Task 2：新增 `outbound_lanes.py`，封装 lane 队列、worker、snapshot 与关闭逻辑。
- [x] Task 3：改造 `outbound_router.py`，将现有发送逻辑挂到 lane worker，保持 `route()` 兼容。
- [x] Task 4：新增 `app_event_fanout.py` 通用 helper，但不接入 `AppRuntimeService`。
- [x] Task 5：复核改动范围、记录主线程接线点、风险点与相邻脏改动适配情况。

## 主线程后续接线点

- `server/main.py`
  - 继续实例化 `UnifiedOutboundRouter`，但建议在关闭阶段显式等待其 lane 关闭完成。
- `server/services/app_runtime.py`
  - 后续可把 `_ws_clients` fanout 切换到 `app_event_fanout.py` 提供的 per-client queue/writer 模式。
  - 后续 runtime state 可读取 `MessageBus.metrics_snapshot()` 与 router lane snapshot 暴露到诊断字段。

## 本轮不做

- 不改 App busy 错误回传接口。
- 不改 `AppRuntimeService._broadcast_event()` 现有实现。
- 不改 `server/main.py` / `server/services/app_runtime.py`。
- 不跑测试、不 review、不提交。
