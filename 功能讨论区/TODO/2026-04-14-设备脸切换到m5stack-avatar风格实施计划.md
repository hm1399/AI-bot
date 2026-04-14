# 设备脸切换到 m5stack-avatar 风格 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将设备当前基于 Avataaars 的脸展示切换为接近 `m5stack-avatar` 的全屏静态风格，并确保屏幕只显示脸本体，不显示状态栏、底部文案或眨眼/说话动画。

**Architecture:** 固件继续由 `face_display` 模块统一接管屏幕绘制，但视觉实现从当前 Avataaars 资源方案切到 `m5stack-avatar` 风格的简化脸状态渲染。运行时只保留基础状态脸切换，不再叠加顶部状态栏、底部文案或任何局部覆盖动画，避免新的视觉要求与现有三段式布局继续耦合。

**Tech Stack:** Arduino / ESP32-S3, TFT_eSPI, existing `face_display` module, `m5stack-avatar` visual language, local firmware face assets or lightweight geometry rendering

---

## 文件范围

- 本轮文档写入：`功能讨论区/TODO/2026-04-14-设备脸切换到m5stack-avatar风格实施计划.md`
- 本轮文档写入：`功能讨论区/TODO/todo.md`
- 后续实施预计修改：`firmware/arduino/demo/face_display.cpp`
- 后续实施预计修改：`firmware/arduino/demo/face_display.h`
- 后续实施预计修改：`firmware/arduino/demo/face_config.h`
- 后续实施预计修改或替换：`firmware/arduino/demo/face_theme_assets.h`
- 后续实施预计修改、替换或下线：`firmware/arduino/demo/tools/generate_avataaars_faces.py`

## 约束

- 目标视觉为 `m5stack-avatar` 风格，但本轮只规划设备脸显示，不扩前端、后端或控制协议。
- 屏幕输出必须是 `240x240` 全屏脸，不保留当前 `status bar + face area + bottom text` 三段式布局。
- 不显示状态栏，不显示底部文案，不保留眨眼、说话、processing 点点等覆盖动画。
- 运行时仍复用现有状态切换入口，只替换状态到脸表现的映射，不重做外围状态机。
- 不再依赖当前 Avataaars 的配色和人物细节语言；若保留离线资源流程，资源命名和参数也需要去 Avataaars 化。
- 计划执行阶段需要兼容并行开发，不回退其他 worker 的相邻改动。

## 任务拆分

### Task 1: 盘点当前脸渲染链路并确定 `m5stack-avatar` 落地方式

**Files:**
- Inspect/Modify: `firmware/arduino/demo/face_display.cpp`
- Inspect/Modify: `firmware/arduino/demo/face_display.h`
- Inspect/Modify: `firmware/arduino/demo/face_config.h`
- Inspect/Modify: `firmware/arduino/demo/tools/generate_avataaars_faces.py`

- [x] 盘点当前 Avataaars 资源、屏幕分区常量和状态切换入口，确认哪些逻辑必须保留。
- [x] 明确 `m5stack-avatar` 风格的落地方式，优先在现有 `face_display` 管线内完成，不额外引入难以维护的运行时依赖。
- [x] 约定状态映射表，只保留基础静态脸状态，不再设计眨眼、说话或 processing 覆盖层。

### Task 2: 将设备屏幕收敛为全屏脸渲染

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_display.h`
- Modify: `firmware/arduino/demo/face_config.h`

- [x] 移除顶部状态栏和底部文字区相关布局常量与绘制逻辑。
- [x] 将脸渲染区域改为 `240x240` 全屏输出，保证没有上下预留区域。
- [x] 清理眨眼、说话和 processing 动画入口，确保 `manual_step_required` 之外的设备行为边界不被顺手扩展。

### Task 3: 替换 Avataaars 资源方案为 `m5stack-avatar` 风格资源或绘制实现

**Files:**
- Modify: `firmware/arduino/demo/face_theme_assets.h`
- Modify/Replace: `firmware/arduino/demo/tools/generate_avataaars_faces.py`

- [x] 去掉现有 Avataaars 专属资源参数、配色和中心方图假设。
- [x] 生成或绘制新的 `m5stack-avatar` 风格静态脸资源，保证适配全屏显示。
- [x] 清理未再使用的旧资源引用，避免固件继续链接无效的 Avataaars 资产。

### Task 4: 验证显示效果与资源影响

**Files:**
- Verify: `firmware/arduino/demo/face_display.cpp`
- Verify: `firmware/arduino/demo/face_theme_assets.h`
- Verify: `firmware/arduino/demo/tools/generate_avataaars_faces.py`

- [x] 以正确板参完成一次固件编译，确认资源尺寸调整后仍能通过编译和链接。
- [ ] 在设备上确认开机与状态切换时只显示全屏脸，没有状态栏、底部文案和覆盖动画残留。
- [x] 复核资源尺寸、Flash/PSRAM 占用和刷屏性能，确认 `240x240` 全屏脸不会引入明显卡顿或超量风险。

## 本轮验证记录

- [x] 已新增本实施计划文档。
- [x] 已将本计划路径登记到 `功能讨论区/TODO/todo.md`。
- [x] 已用板参 `esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,FlashMode=opi` 完成固件编译。
- [x] 编译结果：`Sketch uses 1256703 bytes (39%)`，`Global variables use 49408 bytes (15%)`。
- [ ] 真机烧录与屏幕实际显示效果待用户侧确认。
