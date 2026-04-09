# app DESIGN.md Linear 风格制作计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `app/` 这个 Flutter 前端子项目制作一份 `DESIGN.md`，以 Linear 风格为主要视觉参考，同时写入当前 AI-bot 前端已有的信息架构、状态提示和 UI 约束。

**Architecture:** 先完成 Linear 风格与现有 Flutter 前端结构的只读映射，再在 `app/` 范围内沉淀成项目自有的 `DESIGN.md`。本轮只新增设计规范文档，不修改现有 UI 代码，不跑测试。

**Tech Stack:** Markdown、Flutter、Material 3、hooks_riverpod、go_router、GitHub/getdesign.md 调研

---

### Task 1: 任务登记与范围确认

**Files:**
- Create: `功能讨论区/TODO/2026-04-09-app-DESIGN-md-Linear风格制作计划.md`
- Modify: `功能讨论区/TODO/todo.md`

- [x] Step 1: 记录本轮目标、范围、约束和输出文件。
- [x] Step 2: 将本轮计划文件路径登记到 `功能讨论区/TODO/todo.md`。
- [x] Step 3: 明确 `DESIGN.md` 只服务于 `app/`，不外溢到 `server/`、硬件和其他目录。

### Task 2: 风格来源调研

**Files:**
- Research: `https://getdesign.md/linear.app/design-md`
- Research: `https://github.com/VoltAgent/awesome-design-md/tree/main`

- [x] Step 1: 提炼 Linear 风格的视觉主题、排版、颜色、密度、组件气质。
- [x] Step 2: 区分“借用 DESIGN.md 结构”和“照搬品牌网页视觉”的边界。
- [x] Step 3: 记录只适合网页营销页、不适合当前 Flutter 桌面工具的部分。

### Task 3: 项目约束调研

**Files:**
- Research: `app/README.md`
- Research: `app/pubspec.yaml`
- Research: `app/lib/main.dart`
- Research: `app/lib/config/routes.dart`
- Research: `app/lib/widgets/common/app_scaffold.dart`

- [x] Step 1: 确认当前前端是 Flutter 桌面工具，不是单页网页营销站。
- [x] Step 2: 梳理不能被 Linear 风格覆盖掉的既有结构，如连接状态条、底部导航、任务与控制页面语义。
- [x] Step 3: 归纳适合写入 `DESIGN.md` 的项目级 UI 约束。

### Task 4: 生成 DESIGN.md

**Files:**
- Create: `app/DESIGN.md`

- [x] Step 1: 用 Linear 气质组织 `DESIGN.md` 章节。
- [x] Step 2: 写入 AI-bot 当前 Flutter 前端的真实页面和组件约束。
- [x] Step 3: 明确禁止事项，避免后续 agent 误把桌面控制台改成网页营销页。
- [ ] Step 4: 向用户汇报文件内容，等待确认后再决定 git。
