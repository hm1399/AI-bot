# waitlist

## 说明

- 只记录本轮复核后仍未解决、且值得继续跟踪的问题。
- 2026-04-15 已清理已修复 / 已失效 checkpoint，并按当前影响重新排序。
- 每条继续使用 checkpoint 记录，等待主线程确认后再决定是否单独立项。

## P0：高优先级（运行路径 / 权限边界 / 数据源准确性）

- 当前无未解决 checkpoint；2026-04-15 P0 方案 A 已完成代码落地与目标验证，等待用户确认文件后提交。

## P1：中优先级（热点文件 / 性能风险 / 用户可见行为偏差）

### Checkpoint 2026-04-15-01 后端全量 unittest 仍被 `device_channel` 长按记录模式用例阻塞

- 发现来源：本轮执行 `server/.venv/bin/python -m unittest discover server/tests`。
- 当前状态：`server/tests/test_device_channel.py::DeviceChannelTests.test_long_press_routes_hold_through_structured_handler_in_record_only_mode` 失败；测试期望 `channel.send_json.assert_not_awaited()`，实际已 await 2 次。
- 影响：后端全量回归暂时不能绿灯；`record_only` 长按路径的当前行为与测试契约存在偏差，可能是测试预期过期，也可能是设备通道行为漂移。
- 建议动作：后续单独立项按 `server/channels/device_channel.py` 长按事件流做根因调查，再决定修正实现还是更新测试契约。
- 本轮处理：仅记录；该问题不属于本次 P0 运行路径 / 权限边界 / 数据源准确性范围，未修改。

### Checkpoint 2026-04-15-02 前端全量 `flutter test` 仍有 Control Center / app boots 旧用例失败

- 发现来源：本轮执行 Flutter 全量测试。
- 当前状态：`app/test/control_center/physical_interaction_panel_test.dart` 有两个失败：一个调试按钮 tap 命中视口外导致请求未发出，一个 `Newest` 文案匹配到 2 个 widget；`app/test/widget_test.dart` 仍期望旧标题 `AI Bot Workspace`。
- 影响：前端全量回归暂时不能绿灯；Control Center 测试与当前布局 / 文案契约存在偏差，app smoke test 仍保留旧 UI 口径。
- 建议动作：后续单独立项更新这些测试的滚动 / 精确 finder / 当前启动页文案契约，避免继续污染全量测试结果。
- 本轮处理：仅记录；本次只修复 Settings 目标测试与 P0 相关链路，未顺手修改无关 UI 测试。

### Checkpoint 2026-04-09-04 `server/services/app_runtime.py` 仍是后端单点热点

- 发现来源：本轮后端静态复核。
- 当前状态：`server/services/app_runtime.py` 仍有约 3600+ 行，持续同时承担 app API、事件广播、runtime summary、device / desktop voice / planning 串联等职责。
- 影响：后续只要做 planning、语音、realtime 或 runtime 汇总改动，都容易继续堆到这个单文件，形成并发修改与回归热点。
- 建议动作：后续单独立项把 planning 查询 / runtime projection / websocket 广播等职责继续下沉到独立 service。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-06-03 `app/lib/providers/app_providers.dart` 仍明显过载

- 发现来源：本轮前端静态复核。
- 当前状态：`app/lib/providers/app_providers.dart` 仍有约 3500+ 行，聊天、规划、设备控制、通知、提醒、配网与事件消费继续集中在单一 provider/controller 中。
- 影响：前端任何跨页面行为调整都会扩大改动面，后续多人并行或继续产品化时冲突风险高。
- 建议动作：后续单独立项把会话、planning、设备控制、配网等状态拆成更聚焦的 controller / notifier。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-09-05 `JsonCollectionStore` 仍是整文件读写，且默认 planning 存储仍走 JSON

- 发现来源：本轮后端存储链路复核。
- 当前状态：仓库已具备 `SQLitePlanningStore` 与 `json/dual/sqlite` 三态能力，但默认配置仍是 `planning_storage_mode = json`，`JsonCollectionStore` 仍保持整文件读写与无显式进程内锁。
- 影响：在默认运行口径下，planning 写入热点仍会受到整文件 IO 和并发覆盖风险影响。
- 建议动作：后续单独立项决定默认切到 `dual/sqlite` 的迁移节奏，或在 JSON 模式下补最小锁保护与更清晰的使用边界。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-01 `SessionManager` 默认仍以 JSONL 整份重写为主

- 发现来源：本轮会话存储链路复核。
- 当前状态：`SessionManager` 已支持 `json / dual / sqlite`，但默认 `session_storage_mode` 仍是 `json`，会话热路径仍以 JSONL 整份保存为主。
- 影响：聊天历史增长后，消息写入、切会话与摘要派生仍会继续受整文件重写影响。
- 建议动作：后续单独立项评估把默认会话存储切到 `dual/sqlite`，并同步收口摘要字段的增量维护策略。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-02 `MessageBus` 仍是无界队列，observer 仍在入队前同步执行

- 发现来源：本轮任务调度与总线复核。
- 当前状态：`server/nanobot/bus/queue.py` 仍使用无界 `asyncio.Queue()`，`publish_inbound()` / `publish_outbound()` 依旧先 `await _notify()` 再 `put()`。
- 影响：慢 observer 仍会放大入队延迟，且高峰流量下没有背压上限。
- 建议动作：后续单独立项补 `maxsize`、分层 observer 与观测指标，减少入队前阻塞。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-03 App 事件广播仍会被慢 WebSocket 客户端拖住

- 发现来源：本轮 app realtime 广播复核。
- 当前状态：`AppRuntimeService._broadcast_event()` 仍逐个 `await ws.send_json(event)`，尚未给每个客户端拆独立发送队列。
- 影响：任一慢客户端仍会拖慢整轮广播，影响其他正常客户端的实时体验。
- 建议动作：后续单独立项为每个客户端增加 writer task / queue，并对高频事件做合并或丢弃策略。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-04 `UnifiedOutboundRouter` 仍是单消费者串行出站

- 发现来源：本轮出站路由复核。
- 当前状态：`server/services/outbound_router.py` 仍由单个 consumer 统一串行处理 `device / desktop_voice / whatsapp / app` 出站消息。
- 影响：慢通道仍会形成 head-of-line blocking，拖累其他通道。
- 建议动作：后续单独立项把出站路由拆成更清晰的 lanes，至少区分 `app_realtime / device_voice / external_channels`。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-05 Reminder 调度仍是固定间隔全量轮询

- 发现来源：本轮 reminder 调度复核。
- 当前状态：`server/services/reminder_scheduler.py` 仍按固定 `poll_interval_s=15.0` 周期轮询全部 reminder。
- 影响：提醒数量增长后仍会出现无谓空转，到点精度也继续受轮询间隔限制。
- 建议动作：后续单独立项改成基于 `next_trigger_at` 的 next-fire 调度模型。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-10-02 `ControlCenterScreen` 仍在 `build()` 中回写设备控制草稿值

- 发现来源：本轮前端控制页复核。
- 当前状态：`app/lib/screens/control_center/control_center_screen.dart` 仍在 `build()` 内根据 runtime token 回写 `_volume`、`_brightness` 与 `_colorController.text`。
- 影响：设备状态刷新更频繁时，用户编辑中的草稿仍可能被覆盖，产生光标跳动或输入被抢写的问题。
- 建议动作：后续单独立项把 runtime -> 表单草稿同步迁到更稳定的状态策略，至少按焦点 / 提交态区分自动回填时机。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-06 `desktop_voice.*` 事件已发出，但 Flutter 端仍未消费细粒度语音事件

- 发现来源：本轮桌面语音链路复核。
- 当前状态：后端已广播 `desktop_voice.state.changed / transcript / response / error`，但 `app/lib/providers/app_providers.dart` 的事件分发仍未处理这组事件，前端主要只看聚合 runtime 摘要。
- 影响：桌面语音联调与用户理解成本仍偏高，缺少实时 transcript / response / error 的可视反馈。
- 建议动作：后续单独立项为 Chat 或 Control Center 增加 Voice Activity 视图，直接消费 `desktop_voice.*` 事件。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-09 `computer_control.allowed_scripts` 的“字符串数组”口径与实际解析行为仍不一致

- 发现来源：本轮电脑控制配置复核。
- 当前状态：`server/config.py` 仍允许 `allowed_scripts` 用字符串数组通过校验，但 `server/services/computer_control/policies.py` 对 list 形式仍只把字符串当作 `script_id`，不会生成实际 `command`，运行时依旧会被静默丢弃。
- 影响：配置层“看起来合法”，运行时却不会真正进入 allowlist，容易造成误判。
- 建议动作：后续单独立项统一契约：要么收紧成对象配置，要么补齐字符串数组的真实解析语义。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-14-02 设备显示协议仍保留部分旧状态栏链路

- 发现来源：本轮固件与设备显示链路复核。
- 当前状态：`demo.ino` 仍会接收 `status_bar_update / display_update` 并调用 `faceSetStatusBar()`、`faceSetBattery()`、`faceSetWeather()`；但 `face_display.cpp` 中这三项实现依旧是空函数，当前真正可见的主要还是回复字幕与状态 hint。
- 影响：设备显示协议与实际屏幕能力仍未完全收口，后续排查“为什么设备没显示时间 / 电量 / 天气”时仍容易被旧协议心智误导。
- 建议动作：后续单独立项明确设备屏幕当前真正消费的字段，并决定哪些协议继续保留、哪些彻底下线。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-14-04 `device_channel.py` 仍会在 `display_update` 路径截断长文本

- 发现来源：本轮设备长字幕链路复核。
- 当前状态：`server/channels/device_channel.py` 的 `_send_display_update()` 仍默认按 `DISPLAY_MAX_CHARS` 截断；即使固件已支持滚动，`display_update` 路径也只能滚动被截断后的文本。
- 影响：设备端长文滚动只对“已完整下发的文本”有效，上游若先裁剪，设备端仍无法展示完整内容。
- 建议动作：后续单独立项梳理 `display_update` 与 `text_reply` 的职责，明确哪些消息允许完整下发。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-10-03 demo 固件的 `battery / charging` 仍是占位遥测

- 发现来源：本轮固件遥测复核。
- 当前状态：`firmware/arduino/demo/demo.ino` 发送设备状态时仍写死 `battery = -1`、`charging = false`，尚未接入真实电量 / 充电检测。
- 影响：当前前端上的 `Battery / Charging` 仍只能视为 UI 语义占位，不能当成真实硬件闭环验收。
- 建议动作：后续单独立项补真实电量 / 充电检测，并定义“读取失败 / 未接入 / 真实值”的统一上报契约。
- 本轮处理：仅复核，未处理。

## P2：低优先级（文档、兼容层、工具链与 UI 清理）

### Checkpoint 2026-04-11-01 `app/DESIGN.md` 的壳层口径仍落后于当前产品结构

- 发现来源：本轮前端文档复核。
- 当前状态：`app/DESIGN.md` 仍写着“五个主区”，且明确不建议采用左侧 Linear 风格 sidebar；但当前产品已经包含 `Agenda`，主壳层也已采用左侧导航。
- 影响：后续如果机械照抄该文档，仍可能把视觉规范与现有 IA 混淆，导致错误回退壳层结构。
- 建议动作：后续单独立项更新 `app/DESIGN.md`，把现有壳层与 `Agenda` 纳入正式口径。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-09-01 `app/README.md` 对前端能力描述仍落后于实际 UI

- 发现来源：本轮前端 README 复核。
- 当前状态：`app/README.md` 仍把 tasks / events / notifications / reminders 写成 placeholders，但实际页面已具备较完整的 planning、控制与配网能力。
- 影响：新读者仅看 README 仍会低估当前 Flutter 前端的实际完成度。
- 建议动作：后续单独立项更新 README 的能力概览和页面口径。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-09-02 `/demo` 独立页面与当前 demo 主路径仍有脱节

- 发现来源：本轮路由与 demo 入口复核。
- 当前状态：`app/lib/config/routes.dart` 仍保留 `/demo` 路由与 `DemoModeScreen`，代码里也还留着 `connectDemo()` helper，但当前前端主路径并没有把这套 demo 入口作为核心流程显式暴露。
- 影响：后续继续扩 demo 体验时，仍可能把一个非主路径页面误当成核心入口维护。
- 建议动作：后续单独立项决定 `/demo` 是继续保留为独立说明页，还是收敛回连接页主流程。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-10-01 `app/lib/providers/control_center_provider.dart` 仍是未使用的兼容层

- 发现来源：本轮前端引用关系复核。
- 当前状态：该文件仍只透传 `appControllerProvider` 的通知 / 提醒列表，仓库内仍没有实际引用。
- 影响：继续保留会增加阅读噪音，也容易误导后续改动落点。
- 建议动作：后续单独立项决定删除，或恢复成真正的 Control Center 状态分层。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-10-05 移动端底部 dock 在六个主入口下仍接近拥挤上限

- 发现来源：本轮移动端导航复核。
- 当前状态：`app/lib/widgets/common/app_bottom_dock.dart` 仍是六个入口等宽平铺，窄宽度下依赖图标 + 单行省略文本勉强容纳。
- 影响：后续若继续新增入口或接入更长文案 / 多语言，拥挤问题会继续放大。
- 建议动作：后续单独立项评估“图标优先 + 精简文案”、可横向滚动，或 `More` 收纳方案。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-06 `voice_handoff_card.dart` 仍是未引用的旧 Chat 兼容组件

- 发现来源：本轮 Chat 组件引用复核。
- 当前状态：`app/lib/widgets/chat/voice_handoff_card.dart` 仍保留，但仓库内已无实际引用。
- 影响：旧组件继续留在主路径目录中，会增加阅读噪音，也容易误导后续把 Chat 再改回 dashboard 式布局。
- 建议动作：后续单独立项决定删除，或明确迁到兼容 / 归档区域。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-07 `chat_session_panel.dart` 仍是未引用的兼容外壳

- 发现来源：本轮 Chat 会话组件引用复核。
- 当前状态：`app/lib/widgets/chat/chat_session_panel.dart` 仍保留，但仓库内已无实际引用；主路径实际使用 `ChatSessionDialog + ChatSessionList`。
- 影响：后续如果不清理，会继续制造 panel / dialog / list 三套心智。
- 建议动作：后续单独立项决定删除该兼容壳，或明确唯一主入口组件。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-11-08 Robot Pairing 仍是纯手填 `LAN Host`

- 发现来源：本轮前端配网链路复核。
- 当前状态：`DevicePairingPanel` 仍没有本机 IPv4 网卡候选或一键带入能力；当前只是在已有 backend 连接时，会把已连接 host 当作默认值回填到草稿中。
- 影响：首次部署、尤其多网卡环境下，仍有一定理解成本。
- 建议动作：后续单独立项补“本机候选地址”提示或一键带入能力，并明确这不是局域网扫描。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-14-03 `app/lib/services/chat/voice_capture_service.dart` 仍是未接线占位服务

- 发现来源：本轮语音前端链路复核。
- 当前状态：`voiceCaptureServiceProvider` 仍已注册，但 `voice_capture_service.dart` 依旧固定 `isAvailable = false`、`captureText()` 恒为 `null`，仓库内也没有实际调用。
- 影响：后续如果只看 provider，仍可能误判 Flutter 侧已经具备原生麦克风采集能力。
- 建议动作：后续单独立项决定删除该占位层，或把它升级为真实 Flutter 端录音入口。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-14-01 demo 固件板参知识仍分散在实施计划中，缺少统一入口

- 发现来源：本轮固件构建文档复核。
- 当前状态：多个 2026-04-14 实施计划已经记录正确的 `esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,FlashMode=opi` 板参，但仓库里仍缺少一个稳定、集中、面向日常使用的 demo 构建说明入口。
- 影响：后续如果只凭 `arduino-cli compile --fqbn esp32:esp32:esp32s3 ...` 之类默认命令操作，仍可能再次踩回默认板参误判。
- 建议动作：后续单独立项补一份正式的 demo 固件编译说明或脚本，统一 CLI / IDE 口径。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-14-03 macOS Pods 仍保留过低的 deployment target

- 发现来源：本轮 macOS 工程复核。
- 当前状态：`app/macos/Podfile` 已是 `platform :osx, '10.15'`，但 `app/macos/Pods/Pods.xcodeproj/project.pbxproj` 中 `libserialport` target 仍保留 `MACOSX_DEPLOYMENT_TARGET = 10.11`。
- 影响：这类警告虽然不是当前主链路阻塞项，但会持续污染构建输出，也可能在后续工具链升级时变成真实兼容问题。
- 建议动作：后续单独立项检查 pod target 的最低系统版本收口策略。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-08-04 当前 Python / LibreSSL 环境仍会打印 `urllib3` 警告

- 发现来源：本轮服务端环境复核。
- 当前状态：`server/.venv/bin/python` 仍是 `Python 3.9.6 + LibreSSL 2.8.3`；导入 `urllib3` 依旧会打印 `NotOpenSSLWarning`。
- 影响：当前虽然不直接阻断主链路，但会持续污染日志，并增加后续网络依赖升级的不确定性。
- 建议动作：后续单独立项把服务端虚拟环境迁到带较新 OpenSSL 的 Python 发行版。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-06-01 验收文档路径仍未登记到 `功能讨论区/TODO/todo.md`

- 发现来源：本轮文档链路复核。
- 当前状态：相关验收文档路径已经回填到总 TODO，但 `功能讨论区/TODO/todo.md` 当前仍主要登记计划文件，没有同步补录对应验收文档入口。
- 影响：如果有人只查看 `todo.md`，仍可能漏掉已存在的验收记录。
- 建议动作：后续单独立项决定是否把验收文档也纳入 `todo.md` 的统一登记规则。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-13-02 扬声器 DIN 引脚文档与当前固件口径仍不一致

- 发现来源：本轮硬件文档复核。
- 当前状态：当前 `demo/test4/test4_tts` 已按 `IO21` 走喇叭 DIN，但 `CLAUDE.md`、`功能讨论区/硬件测试.md`、`CHANGELOG.md` 等历史文档仍残留 `IO8` 口径。
- 影响：后续焊接、排障或复现实验时，仍可能被旧文档误导。
- 建议动作：后续单独立项统一硬件主文档、测试文档与 changelog 的引脚说明。
- 本轮处理：仅复核，未处理。

### Checkpoint 2026-04-13-01 WeChat `experimental_ui` 仍是占位开关

- 发现来源：本轮电脑控制适配器复核。
- 当前状态：`server/config.py` 与 policy 层仍暴露 `wechat.experimental_ui`，但 `server/services/computer_control/adapters/wechat.py` 仍只会改变返回文案，不会开启真实发送自动化。
- 影响：后续如果只看配置层，仍可能误判“打开 experimental_ui 就能自动化发送微信”。
- 建议动作：后续单独立项决定删除该占位开关，或补真正可验证的 UI 自动化适配器。
- 本轮处理：仅复核，未处理。
