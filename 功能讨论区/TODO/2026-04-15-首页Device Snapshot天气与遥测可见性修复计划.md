# 首页 Device Snapshot 天气与遥测可见性修复计划

> 仅覆盖本轮新增问题：主页 `Device Snapshot` 中天气、充电状态、电量的可见性与语义回归。要求保持现有首页 UI 风格，不擅自扩展其它页面，不伪造硬件真实遥测。

## 目标

- [x] 恢复首页 `Weather` 在 App 端的真实可见性，不再被设备状态栏硬件能力误伤成 `Unavailable`。
- [x] 恢复首页 `Battery / Charging` 的展示语义，区分 `Unknown` 与 `Not Wired`，避免误导用户把“未接线/未上报”看成前端漏渲染。
- [x] 保持现有首页 `Device Snapshot` 的布局与视觉语言，不做额外 UI 改版。

## 调研结论

- [x] 前端首页卡片 [app/lib/widgets/home/device_card.dart](/Users/mandy/Documents/GitHub/AI-bot/app/lib/widgets/home/device_card.dart) 当前把 `weather` 是否展示完全绑定在 `displayCapabilities.weatherAvailable` 上。
- [x] 后端快照 [server/channels/device_channel.py](/Users/mandy/Documents/GitHub/AI-bot/server/channels/device_channel.py) 当前把 `display_capabilities.weather_available` 绑定到设备 `status_bar.weather_capability`，而不是 App 端天气抓取能力。
- [x] 当前固件 [firmware/arduino/demo/demo.ino](/Users/mandy/Documents/GitHub/AI-bot/firmware/arduino/demo/demo.ino) 明确写死：
  - `STATUS_BAR_HARDWARE_AVAILABLE = false`
  - `BATTERY_TELEMETRY_AVAILABLE = false`
  - `CHARGING_TELEMETRY_AVAILABLE = false`
- [x] 因此，当前真实设备上报里 `battery/charging` 的 `capability=false`、`validity=unavailable` 是硬件/固件现状，不是前端凭空丢字段。
- [x] 同时，天气链路在后端被“状态栏天气能力”为 false 时直接跳过抓取，所以 App 首页也看不到天气，这属于后端回归，不是单纯 UI 渲染问题。

## 修复方案

- [x] 后端：
  - 为 App 运行态快照恢复独立的天气可见性判断，不再要求设备屏幕必须支持天气状态栏。
  - 天气轮询继续可服务于 App 快照；只有真正下发到设备屏幕时，才受设备状态栏硬件能力约束。
  - 快照返回中保留 `weather_status / weather_meta / fetched_at`，让前端能表达 `Waiting / Retry Needed / Ready`。
- [x] 前端：
  - 首页 `Weather` 的可见性增加兜底推断，优先展示后端运行态里已经存在的天气状态与来源。
  - 首页 `Battery / Charging` 恢复为更准确的用户语义：
    - 有能力但当前无有效值：`Unknown`
    - 设备明确未接线/不支持：`Not Wired`
  - 保留已有二级说明文案，不改首页整体布局。
- [x] 测试：
  - 补充后端 `device_channel` 单测，覆盖“设备无状态栏天气能力时，App 快照仍可暴露天气状态”的回归场景。
  - 补充/更新前端 `device_card` 组件测试，覆盖 `Unknown / Not Wired / Weather Ready` 语义。
  - 按当前用户约束，本轮先不执行测试，待你确认修改后再跑。

## 实施范围

- `server/channels/device_channel.py`
- `server/tests/test_device_channel.py`
- `app/lib/widgets/home/device_card.dart`
- `app/lib/models/home/runtime_state_model.dart`
- `app/test/device_card_test.dart`
- `功能讨论区/TODO/todo.md`
- `功能讨论区/TODO/2026-04-15-首页Device Snapshot天气与遥测可见性修复计划.md`

## 落地步骤

- [x] 完成前后端排查并确认根因。
- [x] 新增本轮计划文件并登记到 `todo.md`。
- [x] 修复后端天气快照能力判断与缓存暴露。
- [x] 修复首页 `Device Snapshot` 的天气/遥测文案语义。
- [x] 补充相关测试用例但暂不执行。
- [x] 完成静态复核；按当前用户约束，测试与 git 提交待确认后执行。

## 验收口径

- [x] 主页 `Device Snapshot` 中，天气在设备无状态栏天气硬件能力时仍可按 App 端真实状态显示。
- [x] 主页 `Battery / Charging` 不再模糊显示为 `Unavailable`，而是明确区分 `Unknown` 与 `Not Wired`。
- [x] 不改坏现有首页布局与其它卡片显示。

## 当前状态

- [x] 根因已定位。
- [x] 代码修改已完成。
- [ ] 按当前用户约束，测试尚未执行。
- [ ] 按当前用户约束，git 提交待你确认后执行。
