# 2026-04-01 app 改造为 Flutter 工程实施

## 目标

- 将 `AI-bot/app` 从现有 React/Vite 工程重建为标准 Flutter 工程
- 按 `2026-04-01-flutter-frontend-implementation-plan.md` 迁移核心页面与协议底座
- 保持与 `server/services/app_runtime.py` 的 `app-v1` 协议对齐

## 待执行事项

- [x] 确认实施计划、当前 `app/` 目录与 Flutter SDK 可用
- [x] 梳理 React 页面能力与后端协议映射
- [x] 在 `app/` 创建标准 Flutter 工程骨架
- [x] 迁移 Connect / Home / Chat / Control Center / Settings
- [x] 写好 Tasks / Events / Notifications / Reminders 占位与 service
- [x] 保留 Demo Mode 并完成 real/demo 切换
- [x] 运行构建与测试验证
- [x] 提交 git commit
