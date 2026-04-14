# 设备 m5stack-avatar 脸恢复眨眼说话与 processing 动画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在当前全屏 `m5stack-avatar` 风格设备脸基础上，恢复 `blink`、`speaking mouth` 和 `processing dots` 三类状态动画，同时保持无状态栏、无底部文案的全屏脸体验。

**Architecture:** 继续由 `face_display` 模块统一管理设备屏幕绘制，不引入 `M5Unified / M5GFX` 整包运行时依赖，而是在现有 `TFT_eSPI` 路径中补齐轻量动画状态机。`blink` 与 `speaking mouth` 参照 `m5stack-avatar` 的语义实现，`processing dots` 继续作为设备态特效叠加在全屏脸上。

**Tech Stack:** Arduino / ESP32-S3, TFT_eSPI, existing `face_display` module, `m5stack-avatar` visual language

---

## 文件范围

- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_display.h`
- Modify: `firmware/arduino/demo/face_config.h`
- Modify: `功能讨论区/TODO/todo.md`
- Modify: `功能讨论区/TODO/2026-04-14-设备m5stack-avatar脸恢复眨眼说话与processing动画实施计划.md`

## 约束

- 只改设备固件脸显示，不改前端、后端协议和状态机。
- 保持 `240x240` 全屏脸，不恢复状态栏与底部文案。
- `blink` 与 `speaking mouth` 需要尽量贴近 `m5stack-avatar` 默认语义。
- `processing dots` 允许作为设备态特效保留，但不能破坏当前全屏脸整体风格。
- 按当前用户约束，本轮不跑测试；仅做必要固件编译验证。
- 完成后先向用户汇报进度，等用户确认文件后再 git。

## 任务拆分

### Task 1: 明确动画语义并补齐 face_display 动画状态

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_display.h`
- Modify: `firmware/arduino/demo/face_config.h`

- [x] 盘点当前 `faceUpdate()` 调用频率和 `FaceState` 切换入口，确认动画只在显示层实现。
- [x] 为 `blink / speaking mouth / processing dots` 增加最小动画状态机与时间参数。
- [x] 确保状态切换时会重置对应动画，避免跨状态残留。

### Task 2: 恢复 blink 与 speaking mouth 视觉行为

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_config.h`

- [x] 恢复 `blink`，让全屏脸在运行态具备轻量自动眨眼行为。
- [x] 恢复 `speaking mouth`，让 `FACE_SPEAKING` 在保持风格一致的前提下有口型开合变化。
- [x] 保持 `m5stack-avatar` 风格的几何五官，不重新引入贴图资源。

### Task 3: 恢复 processing dots 并验证编译

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `功能讨论区/TODO/2026-04-14-设备m5stack-avatar脸恢复眨眼说话与processing动画实施计划.md`

- [x] 为 `FACE_PROCESSING` 恢复点点动画，并保证和当前脸风格兼容。
- [x] 用正确板参完成一次固件编译验证。
- [x] 回填本计划完成状态，并先向用户汇报结果。

## 本轮验证记录

- [x] 已新增本实施计划文档。
- [x] 已将本计划路径登记到 `功能讨论区/TODO/todo.md`。
- [x] 已用板参 `esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,FlashMode=opi` 完成固件编译。
- [x] 编译结果：`Sketch uses 1257275 bytes (39%)`，`Global variables use 49432 bytes (15%)`。
- [ ] 真机烧录与动态观感确认待用户侧验收。
