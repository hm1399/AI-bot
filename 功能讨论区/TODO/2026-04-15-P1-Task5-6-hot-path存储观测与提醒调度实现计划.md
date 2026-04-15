# 2026-04-15 P1 Task 5/6 hot path 存储观测与提醒调度实现计划

## 范围

- 仅修改 `server/services/app_api/resource_service.py`
- 仅修改 `server/nanobot/session/manager.py`
- 仅修改 `server/services/reminder_scheduler.py`
- 如确有必要，允许修改直接耦合的 sqlite store
- 不修改 `server/config.py`
- 不修改 `server/services/app_runtime.py`
- 不跑测试
- 不做 git commit

## 实施任务

- [x] 为 planning resource store 补齐 dual/sqlite 运行态观测、影子状态与统计接口
- [x] 为 session store 补齐 mode/status/diag 最小侵入接口
- [x] 为 reminder store 增加 next-fire 查询 helper，避免 scheduler 依赖全量扫描
- [x] 将 ReminderScheduler 改成 next-fire 主循环 + 低频 reconcile
- [x] 让 reminder create/update/delete/snooze/complete 路径能触发 scheduler 重排
- [x] 复核本轮涉及代码并同步 waitlist 中需要后续单独立项的问题
