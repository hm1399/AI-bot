# 2026-04-01 Appbuilder 迁移到 AI-bot/app 目录

## 背景

- 源目录固定为 `D:\workspace\apppppp\Appbuilder`
- 目标目录固定为 `D:\桌面\3070\AI-bot\AI-bot\app`
- 目标是把现有前端工程迁入 AI-bot 仓库根目录下的 `app/`
- 后续前端根目录统一以 `AI-bot/app` 为准

## 待执行事项

- [x] 在 `AI-bot` 根目录创建 `app/`
- [x] 复制 `Appbuilder` 前端项目到 `AI-bot/app`
- [x] 排除源目录 `.git` 与构建产物，避免污染目标仓库
- [x] 校验迁移后目录结构与关键文件完整
- [x] 在 `AI-bot/app` 下验证可构建
- [x] 提交 git commit
