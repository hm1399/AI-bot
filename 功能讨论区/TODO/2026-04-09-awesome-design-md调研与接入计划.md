# awesome-design-md 调研与接入计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 调研 `VoltAgent/awesome-design-md` 的内容和使用方式，判断它是否适合作为 AI-bot 的设计规范输入，并给出当前仓库的低风险接入建议。

**Architecture:** 主线程只负责调研记录、结论汇总和路径登记，不修改前后端代码。外部仓库分析与本地项目适配分析拆分为并行子任务，避免上下文混杂和后续建议失真。

**Tech Stack:** GitHub 仓库调研、Markdown 规范文件、Flutter 前端结构、Codex skill 使用流程

---

### Task 1: 建立研究记录

**Files:**
- Create: `功能讨论区/TODO/2026-04-09-awesome-design-md调研与接入计划.md`
- Modify: `功能讨论区/TODO/todo.md`

- [ ] Step 1: 创建本轮调研文件并写入目标、范围、任务拆分。
- [ ] Step 2: 将本轮调研文件路径登记到 `功能讨论区/TODO/todo.md`。

### Task 2: 外部仓库调研

**Files:**
- Research: `https://github.com/VoltAgent/awesome-design-md/tree/main`

- [ ] Step 1: 确认仓库是否真的是 Codex skill，还是一组 `DESIGN.md` 模板集合。
- [ ] Step 2: 归纳仓库目录结构、主要模板来源和典型使用方式。
- [ ] Step 3: 找出最适合 AI-bot 项目参考的候选模板或接入模式。

### Task 3: 本地项目适配调研

**Files:**
- Research: `app/pubspec.yaml`
- Research: `app/lib/main.dart`
- Research: `app/README.md`

- [ ] Step 1: 确认当前前端技术栈和 UI 生成方式，避免给出错误的网页前端接入建议。
- [ ] Step 2: 判断 `DESIGN.md` 应放在仓库根目录、`app/` 目录，还是仅作为外部参考文档使用更稳妥。
- [ ] Step 3: 识别接入时需要规避的风险，尤其是现有 Flutter UI/UX 被错误重写的风险。

### Task 4: 结论汇总

**Files:**
- Modify: `功能讨论区/TODO/2026-04-09-awesome-design-md调研与接入计划.md`

- [ ] Step 1: 汇总外部仓库与本地项目的对应关系。
- [ ] Step 2: 给出“能不能直接当 skill 用”“如果要用，应该怎么用”的结论。
- [ ] Step 3: 如发现额外风险或后续建议，只记录到 `waitlist.md`，不擅自实施。
