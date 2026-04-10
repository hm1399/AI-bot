# 2026-04-10 天气真实性与首页 Device Snapshot 字段排查及修改计划

## 目标

在不破坏现有首页 UI/UX 风格的前提下，先澄清当前天气数据是否为真实电脑侧数据，再补齐首页 `Device Snapshot` 对设备快照字段的表达与可信度提示，避免把“电脑侧天气拉取结果”和“硬件真实遥测”混为一谈。

## 排查结论

- [x] **天气 `25°C` 当前是真实电脑侧数据，不是前端写死，也不是设备硬件回传。**
  - 后端配置文件 [server/config.yaml](/Users/mandy/Documents/GitHub/AI-bot/server/config.yaml) 中城市是 `Hong Kong`，`OPENWEATHERMAP_API_KEY` 当前未配置。
  - 后端日志 [server/logs/server_2026-04-10.log](/Users/mandy/Documents/GitHub/AI-bot/server/logs/server_2026-04-10.log) 已明确记录 `天气 API Key 未配置，改用 fallback provider`，随后记录 `天气推送: 25°C`。
  - 本机在 2026-04-10 19:36:28 HKT 查询 `/api/app/v1/device` 返回 `status_bar.weather = "25°C"`、`weather_status = "ready"`。
  - 同时按后端当前逻辑直查 Open-Meteo：
    - geocoding: `https://geocoding-api.open-meteo.com/v1/search?name=Hong+Kong&count=1&language=en&format=json`
    - forecast: `https://api.open-meteo.com/v1/forecast?latitude=22.27832&longitude=114.17469&current=temperature_2m&temperature_unit=celsius`
  - 该 forecast 在 `2026-04-10T11:30` UTC 返回 `temperature_2m = 25.3`，后端按整型四舍五入显示为 `25°C`，与当前前端显示一致。

- [x] **当前天气数据路径是“电脑侧拉取 -> 后端状态栏缓存 -> 推送给设备与 App”，不是硬件主动回传天气。**
  - 天气抓取逻辑位于 [server/channels/device_channel.py](/Users/mandy/Documents/GitHub/AI-bot/server/channels/device_channel.py) 的 `_fetch_weather()` / `_fetch_weather_fallback()`。
  - 固件只会把已收到的 `status_bar.weather` 回带到 `device_status`，不会自行联网查天气。

- [x] **首页 `Device Snapshot` 的 `charging` 不是“前端没显示”，而是固件目前上报的值本身就是占位值。**
  - 固件 [firmware/arduino/demo/demo.ino](/Users/mandy/Documents/GitHub/AI-bot/firmware/arduino/demo/demo.ino#L265) 当前写死：
    - `battery = -1`
    - `charging = false`
  - 所以前端即使显示了 `Charging: No`，它也不是可信的真实硬件遥测。

- [x] **首页 `Device Snapshot` 目前已显示的字段有：**
  - `State`
  - `Battery`
  - `Wi-Fi`
  - `Charging`
  - `Connected`
  - `Reconnects`
  - `Volume`
  - `Audio`
  - `Power`
  - `LED`
  - `Clock`
  - `Weather`
  - `Last Command`

- [x] **首页 `Device Snapshot` 目前仍缺少或表达不充分的字段/语义有：**
  - 后端已返回但前端未解析、未展示：`last_seen_at`
  - 已被前端模型解析但未展示：`wifi_rssi` 原始 dBm、`status_bar.updated_at`、`last_command.updated_at`
  - 可信度语义缺失：
    - `weather` 没标明来源是电脑侧天气 provider
    - `battery / charging` 没标明当前仍是 demo 固件占位值
    - `Wi-Fi` 当前只显示归一化百分比，不显示原始 RSSI，调试价值不足

## 影响判断

- [x] **当前 `Weather` 可继续作为“电脑侧天气显示”使用。**
  - 现阶段不应再把它误解为“硬件天气传感器数据”。

- [x] **当前 `Battery / Charging` 不应作为验收硬件真实状态的依据。**
  - 这两项在固件未接入真实检测前，只能视为占位或未接通。

- [x] **当前首页快照的主要问题不是“字段完全没有”，而是“缺少 freshness / provenance / raw telemetry 的上下文”。**

## 修改计划

### A. 天气来源与可信度标注

- [x] 在后端运行态快照中补一个轻量 weather metadata：
  - `provider`：`openweather` / `open-meteo-fallback`
  - `city`
  - `fetched_at`
  - 可选：`source = "computer_fetch"`
- [x] 前端首页 `Device Snapshot` 的天气区域补充二级说明，但不改现有整体布局风格：
  - 明确这是电脑侧天气
  - 显示最近刷新时间
  - 当 provider 为 fallback 时给出非阻塞提示，而不是报错语气

### B. Device Snapshot 字段补齐

- [x] 前端 `DeviceStatusModel` 解析 `last_seen_at`
- [x] 首页补展示 `Last Seen`
- [x] 首页在 `Wi-Fi` 除百分比外再显示原始 `wifi_rssi`
- [x] 首页对 `Last Command` 增加 `updated_at` 辅助信息
- [x] 首页对 `Clock / Weather` 增加 `status_bar.updated_at` / `fetched_at` 辅助信息

### C. 占位遥测与真实遥测区分

- [ ] 固件层把 `battery = -1` / `charging = false` 的现状明确标记为“占位值未接通”，避免被误读为真实状态
- [x] 前端对 `battery = -1` 显示 `Unknown`
- [x] 前端对 `charging` 增加占位态文案策略：
  - 若仍是 demo 固件占位值，不显示肯定式 `No`
  - 改为更接近事实的 `Unknown` / `Not Wired`

### D. 验收标准

- [x] 用户在首页能区分：
  - 电脑侧天气数据
  - 硬件真实状态
  - demo 固件占位状态
- [x] 用户能在首页直接看到：
  - 最近设备上行时间
  - 最近天气刷新时间
  - 原始 Wi-Fi RSSI
  - 命令结果更新时间
- [x] `charging / battery` 在真实遥测未接通前，不再误导用户

## 相关代码范围

- 后端：
  - [server/channels/device_channel.py](/Users/mandy/Documents/GitHub/AI-bot/server/channels/device_channel.py)
  - [server/services/app_runtime.py](/Users/mandy/Documents/GitHub/AI-bot/server/services/app_runtime.py)
- 前端：
  - [app/lib/models/home/runtime_state_model.dart](/Users/mandy/Documents/GitHub/AI-bot/app/lib/models/home/runtime_state_model.dart)
  - [app/lib/widgets/home/device_card.dart](/Users/mandy/Documents/GitHub/AI-bot/app/lib/widgets/home/device_card.dart)
- 固件：
  - [firmware/arduino/demo/demo.ino](/Users/mandy/Documents/GitHub/AI-bot/firmware/arduino/demo/demo.ino)

## 本轮输出范围

- [x] 完成天气真实性核验
- [x] 完成首页字段覆盖排查
- [x] 完成后续修改计划整理
- [x] 完成后端 weather metadata 与前端 Device Snapshot 实现
- [x] 已跑新的自动化测试
