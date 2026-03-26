# 2026-03-26 计划 05A / W1-A TODO

> 负责人：Wave 1 implementer W1-A
> 范围：`server/nanobot/session/manager.py`、`server/nanobot/utils/` 原子写工具、`server/tests/` 相关测试
> 禁改：`server/services/app_runtime.py`、`server/nanobot/bus/queue.py`、`server/config.py`、`server/config.yaml`、`server/bootstrap.py`、`server/nanobot/providers/*`

## 目标

1. 抽出共享原子写工具，采用“临时文件 + 原子替换”。
2. `SessionManager.save()` 改用共享工具。
3. 测试覆盖：
   - 原子写成功
   - 写失败保留旧文件
   - Session 保存后可重新加载
   - `list_sessions()` 遇坏文件不崩溃
4. 如有必要，在当前边界内增强坏文件日志。

## TDD 执行步骤

- [ ] 新增原子写与 SessionManager 定向测试
- [ ] 运行定向测试，确认先失败
- [ ] 实现共享原子写工具
- [ ] 改造 `SessionManager.save()`
- [ ] 运行定向测试直到通过
- [ ] 检查 diff 并单独提交 git commit
