# 设备 Avataaars 全屏脸与默认配色调整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将设备屏幕改为全屏 Avataaars 脸展示，使用接近官网默认的原始配色，去掉状态栏、底部文字区以及眨眼/说话动画。

**Architecture:** 固件继续使用离线生成的 Avataaars 静态资源，但资源尺寸从居中的 `168x168` 改为 `240x240` 全屏图，并调整生成参数回到默认风格颜色。`face_display` 改成纯静态状态图切换，不再叠加眨眼、说话或 processing 点点动画，也不再渲染顶部状态栏和底部文字区。

**Tech Stack:** DiceBear HTTP API, Python 3 + Pillow, Arduino / ESP32-S3, TFT_eSPI, existing `face_display` module

---

## 文件范围

- Modify: `firmware/arduino/demo/tools/generate_avataaars_faces.py`
- Modify: `firmware/arduino/demo/face_theme_assets.h`
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_config.h`
- Modify: `功能讨论区/TODO/todo.md`

## 约束

- 只改设备固件脸区，不调整后端接口和前端 UI。
- 全屏展示脸图，顶部状态栏和底部文字区本轮全部不显示。
- 不保留眨眼、说话和 processing 动画，只保留静态状态脸切换。
- 颜色方向以 Avataaars 官网原始风格为准，不再手动指定浅蓝/浅绿背景。
- 按当前用户约束，本轮不跑测试；仅做必要的脚本语法检查和固件编译验证。
- 本轮完成后先向用户汇报，不先 git；等用户确认文件后再提交并结束 subagent。

## 任务拆分

### Task 1: 调整 Avataaars 资源生成

**Files:**
- Modify: `firmware/arduino/demo/tools/generate_avataaars_faces.py`
- Modify: `firmware/arduino/demo/face_theme_assets.h`

- [x] 将资源尺寸从 `168x168` 改为 `240x240`。
- [x] 去掉自定义浅蓝/浅绿/浅紫等背景配色，改成接近官网默认的肤色系风格。
- [x] 重新生成 5 个静态状态脸资源头文件。

### Task 2: 调整全屏显示逻辑

**Files:**
- Modify: `firmware/arduino/demo/face_display.cpp`
- Modify: `firmware/arduino/demo/face_config.h`

- [x] 移除顶部状态栏和底部文字区的绘制逻辑。
- [x] 将脸图改为 `240x240` 全屏显示。
- [x] 去掉眨眼、说话和 processing 动画逻辑。
- [x] 保留状态切换接口，但只切换基础静态脸图。

### Task 3: 验证与记录

**Files:**
- Modify: `功能讨论区/TODO/todo.md`

- [x] 将本计划路径写入 `todo.md`。
- [x] 用当前正确板参做一次固件编译验证。
- [x] 完成后把本计划中的已完成任务打勾，并先向用户汇报结果。

## 本轮验证记录

- [x] `python3 -m py_compile firmware/arduino/demo/tools/generate_avataaars_faces.py`
- [x] `arduino-cli compile --fqbn 'esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,FlashMode=opi' firmware/arduino/demo`
