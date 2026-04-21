# 2026-04-21 ignore claude与manager并更新 README

## 任务目标

- [x] 将 `.claude/` 和 `.manager/` 作为本地目录收口到 ignore 策略
- [x] 若 `.claude/` 仍被 Git 跟踪，则仅取消跟踪，不删除本地文件
- [x] 更新 `README.md`，补充本地目录与当前仓库使用口径

## 调研范围

- [x] `.gitignore`
- [x] `.claude/` 与 `.manager/` 当前 Git 跟踪状态
- [x] `README.md` 中适合补充本地目录说明的位置

## 输出要求

- [x] 不跑测试，等待用户后续指示
- [x] 完成后先汇报变更，再执行 git 提交

## 状态

- [x] 2026-04-21 已完成 `.claude/`、`.manager/` ignore 收口；`.claude/` 已取消 Git 跟踪且本地保留，同时 `README.md` 已补充本地目录说明。测试按用户要求未执行。
