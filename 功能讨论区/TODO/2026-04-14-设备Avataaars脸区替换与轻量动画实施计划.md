# 设备 Avataaars 脸区替换与轻量动画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将设备中间脸区替换为 `DiceBear Avataaars Neutral` 风格的 5 状态基础脸，并补充轻量眨眼与说话覆盖动画，同时保留现有状态栏和底部文字区。

**Architecture:** 通过离线生成 `Avataaars Neutral` 状态资源图并转为固件可直接使用的 `RGB565` 静态数组，设备运行时只在 `face_display` 中切换基础图和叠加轻量覆盖动画，不在 ESP32 上实时解析 SVG/PNG。状态栏、底部文字、现有连接与语音状态机保持不变，只替换脸区的视觉实现。

**Tech Stack:** DiceBear HTTP API, Python 3 + Pillow, Arduino / ESP32-S3, TFT_eSPI, existing `face_display` module

---

## 文件范围

- Create: `firmware/arduino/demo/tools/generate_avataaars_faces.py`
- Create: `firmware/arduino/demo/face_theme_assets.h`
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_display.h`
- Modify: `firmware/arduino/demo/face_config.h`
- Modify: `功能讨论区/TODO/todo.md`

## 约束

- 只改设备固件脸区，不调整前端 UI 和后端接口。
- 保留 `240x240` 设备的现有 `status bar + face area + text area` 三段式布局。
- `Avataaars` 脸图区使用浅色背景；状态栏和底部文字区继续沿用现有深色风格。
- 轻量动画只做：
  - `idle / active / listening` 眨眼覆盖
  - `speaking` 嘴型开合覆盖
  - `processing` 基础脸 + 点点动画
- 按当前用户约束，本轮不跑测试；验证只做资源生成和代码静态检查级别自查。

## 任务拆分

### Task 1: 生成 Avataaars 状态资源

**Files:**
- Create: `firmware/arduino/demo/tools/generate_avataaars_faces.py`
- Create: `firmware/arduino/demo/face_theme_assets.h`

- [x] 固定 5 个状态的 `eyebrows / eyes / mouth / backgroundColor` 参数组合。
- [x] 拉取 DiceBear PNG 资源并转换为 `168x168` 的状态资源。
- [x] 输出固件可直接引用的头文件与生成脚本，包含尺寸、背景色和状态资源表。

### Task 2: 接入固件脸区渲染

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_display.h`
- Modify: `firmware/arduino/demo/face_config.h`

- [x] 将当前几何图元脸改为基于资源图的状态切换。
- [x] 保留现有状态栏与底部文字渲染逻辑。
- [x] 为 `idle / active / listening` 增加眨眼覆盖动画。
- [x] 为 `speaking` 增加说话嘴型覆盖动画。
- [x] 为 `processing` 适配新脸区背景下的点点动画。

### Task 3: 记录与收尾

**Files:**
- Modify: `功能讨论区/TODO/todo.md`

- [x] 将本计划路径写入 `todo.md`。
- [x] 完成后把本计划中的已完成任务打勾。
- [ ] 按用户要求在任务完成后进行一次 git 提交。

## 本轮验证记录

- [x] `python3 -m py_compile firmware/arduino/demo/tools/generate_avataaars_faces.py`
- [x] `arduino-cli compile --fqbn 'esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,FlashMode=opi' firmware/arduino/demo`
- [x] 记录默认 `arduino-cli` 4MB 板参会误判“程序超 Flash”的发现到 `waitlist.md`
