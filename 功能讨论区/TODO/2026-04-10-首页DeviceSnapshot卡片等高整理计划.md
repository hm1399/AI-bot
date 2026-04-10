# 2026-04-10 首页 Device Snapshot 卡片等高整理计划

## 目标

- 在不改现有首页整体风格的前提下，让 `Device Snapshot` 内部所有指标卡片保持统一高度，解决当前因为文案层级不同导致的卡片参差不齐问题。

## 现状

- `Device Snapshot` 当前使用 `Wrap` 布局。
- 每个 `_MetricChip` 高度由内容自然撑开。
- 当某些卡片有 `detail / caption`，而另一些只有 `value` 时，会出现同一组卡片高度不一致。

## 实施步骤

- [x] 先补一个 widget test，锁定“不同信息密度的卡片也必须等高”。
- [x] 给 `_MetricChip` 增加统一高度约束，避免随着 detail/caption 有无而变化。
- [x] 重新跑相关 Flutter 测试，确认视觉整理没有破坏现有展示逻辑。

## 验收标准

- [x] 首页 `Device Snapshot` 内所有小卡片边界整齐，不再出现明显高低不一。
- [x] `Weather / Last Command / Battery` 这类带补充文案的卡片，和 `State / Connected / Volume` 这类短卡片保持同高。
- [x] 现有文案信息不丢失，首页其它区域样式不被破坏。
