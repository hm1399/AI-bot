# waitlist

## 说明

- 只记录本轮调研或文档同步时发现、但未在当前任务内处理的问题。
- 每条使用 checkpoint 记录，等待主线程确认后再决定是否立项或回填。

### Checkpoint 2026-04-14-01 `arduino-cli` 默认板参会把 demo 固件误编成 4MB / 1.2MB APP

- 发现来源：本轮设备 Avataaars 脸区替换与固件编译验证。
- 当前状态：直接运行 `arduino-cli compile --fqbn esp32:esp32:esp32s3 firmware/arduino/demo` 时，CLI 默认使用 `FlashSize=4M`、`PartitionScheme=default`、`PSRAM=disabled`；而当前硬件实际是 `ESP32-S3-WROOM-1-N16R8`，需要按 `16MB Flash + OPI PSRAM` 的口径验证。
- 影响：如果继续按 CLI 默认板参验证，固件会被误判成“程序超 Flash”，也会掩盖真实的可烧录配置，后续任何资源类 UI 改动都容易得到错误结论。
- 建议动作：后续单独立项补一份 demo 固件明确板参说明，至少固定 `FlashSize / PartitionScheme / PSRAM / FlashMode` 的推荐组合，避免 Arduino IDE 与 CLI 口径漂移。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-01 `app/DESIGN.md` 的壳层口径已落后于当前产品结构

- 发现来源：本轮 Chat 页面桌面化改版调研。
- 当前状态：`app/DESIGN.md` 仍写着保留“五个主区”，并建议不要把主壳层换成左侧 Linear 式 sidebar；但当前产品实际已经有 `Agenda`，且 `app/lib/widgets/common/app_scaffold.dart` 也已经采用桌面左侧导航。
- 影响：后续如果机械照抄 `DESIGN.md`，容易把“视觉规范”与“现有产品 IA”混为一谈，导致实现时错误回退导航结构。
- 建议动作：后续单独立项更新 `app/DESIGN.md`，把现有壳层与 `Agenda` 纳入正式口径；在当前 Chat 任务中，应只沿用其视觉/密度/控件风格约束，不回退整体 IA。
- 本轮处理：未处理。

### Checkpoint 2026-04-06-01 验收文档路径尚未登记到 `todo.md`

- 发现来源：本轮文档并发检查。
- 当前状态：`功能讨论区/TODO/todo.md` 已有并发修改，且本轮按指令不允许触碰；新建的验收文档路径目前只写入了总 TODO 和本轮计划文件。
- 影响：后续如果只查看 `todo.md`，可能漏掉新增的语音闭环验收文档。
- 建议动作：由主线程在文档收口时决定是否把验收文档路径补登记到 `todo.md`，或明确约定该类验收文档只通过总 TODO/计划文件引用。
- 本轮处理：未处理。

### Checkpoint 2026-04-06-02 P0 文档勾选仍依赖主线程回传实现实况

- 发现来源：总 TODO 与本轮计划文件的回填位整理。
- 当前状态：`P0-1` 的正式输出方式、`P0-3` 的正式接入方式、`P0-4` 的联调结论、`P0-5` 的实际设备角色确认，当前都只能预留回填位，不能由文档 worker 独立确认。
- 影响：即使代码侧后续落地，文档侧如果没有主线程回传实际结果，仍可能出现漏勾或误勾。
- 建议动作：主线程回传 `接入方案 A/B`、`输出方案 A/B`、`联调日期`、`最终结论`、`证据路径` 后，再统一更新总 TODO 与计划文件。
- 本轮处理：未处理。

### Checkpoint 2026-04-06-03 `app/lib/providers/app_providers.dart` 已继续膨胀

- 发现来源：本轮前端可操作化改造。
- 当前状态：聊天、会话、任务、事件、通知、提醒、设备命令、实时事件同步全部继续堆在 `AppController` 中，单文件已明显承担过多页面和状态职责。
- 影响：后续再加语音联调、测试或多页面行为时，改动面会继续扩大，单点回归风险高。
- 建议动作：后续单独立项，把会话/任务/提醒/设备控制拆成独立 controller 或 notifier，降低 `app_providers.dart` 的耦合度。
- 本轮处理：未处理。

### Checkpoint 2026-04-08-01 `firmware/arduino/demo/demo.ino` 未输出 WebSocket 目标地址，容易误判 IP 是否生效

- 发现来源：本轮 demo 固件 IP 地址排查。
- 当前状态：草图会打印 `WiFi.localIP()`，但不会打印 `WS_HOST` / `WS_PORT` / `WS_PATH`；当设备本机地址刚好与历史服务端地址相同或相似时，串口信息容易让人误以为“修改的 IP 没生效”。
- 影响：后续联调时，无法仅凭串口首屏快速判断当前固件究竟在连哪个 WebSocket 目标，排错成本高。
- 建议动作：后续如需提升可观测性，可单独立项为 demo 固件补一条启动日志，明确打印 `WS_HOST:WS_PORT` 与路径。
- 本轮处理：未处理。

### Checkpoint 2026-04-08-02 `server/tools/desktop_voice_client.py` 已退化为兼容/调试入口

- 发现来源：本轮 main 单进程桌面麦克风收口。
- 当前状态：正常联调已经改成只运行 `python3 main.py`，但旧的 `/ws/desktop-voice` 客户端工具和对应文档口径仍需长期并存。
- 影响：后续如果有人继续按旧文档把它当成必跑进程，会增加第三个终端和额外排障噪音；如果未来忘了它只是调试工具，也容易让主流程和兼容流程混在一起。
- 建议动作：后续可单独立项，决定是继续长期保留这个调试客户端，还是在 UI/文档/启动日志里把它明确标注为 debug-only。
- 本轮处理：未处理。

### Checkpoint 2026-04-08-03 `whatsapp.enabled` 默认开启会给 main-only 联调带来额外噪音

- 发现来源：本轮 main-only 工作流复核。
- 当前状态：`server/config.yaml` 默认启用 WhatsApp bridge，哪怕当前只是本地硬件语音链路验证，`main.py` 也会尝试连接桥接服务。
- 影响：如果用户只是单测“硬件触摸 -> 电脑麦克风 -> 硬件喇叭”，WhatsApp bridge 不在线时会出现额外重连日志，干扰主问题定位。
- 建议动作：后续可单独立项，为 main-only 联调加一个更明确的“关闭 WhatsApp”配置口径，或在文档里把 WhatsApp 标成可选辅助通道。
- 本轮处理：未处理。

### Checkpoint 2026-04-08-04 当前 Python/LibreSSL 环境会持续打印 `urllib3` 警告

- 发现来源：本轮 ASR 依赖补齐与导入验证。
- 当前状态：`server/.venv` 建在 Xcode 自带 Python 3.9 上，运行时会看到 `urllib3 v2 only supports OpenSSL 1.1.1+` 与 `LibreSSL 2.8.3` 的警告。
- 影响：这条警告当前不会直接阻断 ASR / TTS 主链路，但会污染启动日志，也可能在后续依赖升级时带来更多兼容问题。
- 建议动作：后续可单独立项，把服务端虚拟环境迁到 Homebrew / python.org 的较新 Python（自带 OpenSSL 1.1.1+），减少网络库兼容噪音。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-01 `app/README.md` 对前端能力描述已落后于实际 UI

- 发现来源：本轮 `app/DESIGN.md` 设计约束调研。
- 当前状态：`app/README.md` 仍把 tasks/events/notifications/reminders 概括成 placeholders，但当前 `app/lib/screens/tasks/tasks_screen.dart` 与 `app/lib/screens/control_center/control_center_screen.dart` 已经存在完整的增删改、已读切换、启停等交互。
- 影响：后续如果只读 README，容易低估当前 Flutter 前端已具备的页面能力，也会影响后续设计和文档判断。
- 建议动作：后续单独立项更新 `app/README.md` 的功能描述，使其与实际 UI 对齐。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-02 `/demo` 独立页面与当前 demo 主路径已有脱节

- 发现来源：本轮 `app/DESIGN.md` 设计约束调研。
- 当前状态：`app/lib/config/routes.dart` 仍保留 `/demo` 路由与 `app/lib/screens/demo_mode/demo_mode_screen.dart`，但真实 demo 入口已经更多通过 `app/lib/screens/connect/connect_screen.dart` 里的 `connectDemo()` 直接进入主壳层。
- 影响：后续继续扩 UI 时，可能会把一个不再处于主路径的页面误当成需要重点维护的体验入口，增加信息架构噪音。
- 建议动作：后续单独立项决定 `/demo` 是继续保留为独立说明页，还是收敛到连接页主流程。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-03 `SettingsForm` 在 `build()` 中反复创建 controller

- 发现来源：本轮 `app/DESIGN.md` 设计约束调研。
- 当前状态：`app/lib/widgets/settings/settings_form.dart` 在 `build()` 内多次使用 `TextEditingController(text: ...)`，这不是稳定的输入组件模式。
- 影响：后续如果设置页继续复杂化，可能出现输入光标、值同步和细小性能问题，也容易误导后续 agent 继续复制这种写法。
- 建议动作：后续单独立项，将设置表单的 controller 生命周期收回到 stateful 层或更稳定的表单状态管理中。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-04 `server/services/app_runtime.py` 已成为后端单点热点

- 发现来源：本轮 `P1 智能待办 / 提醒 / 日历` 前后端调研。
- 当前状态：`server/services/app_runtime.py` 同时承担 app API 路由、任务事件观察、WebSocket replay、runtime summary、device bridge、reminder observer 等职责。
- 影响：后续只要做 planning route、summary 自动派生、scheduler 联动或 agent 回显，几乎都会落到这个单文件，极易形成并发修改冲突和回归热点。
- 建议动作：后续单独立项，把 planning 查询、summary 派生、realtime event 组装进一步下沉到独立 service，减少 `AppRuntimeService` 继续膨胀。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-05 `JsonCollectionStore` 仍是整文件读写且缺少进程内锁

- 发现来源：本轮 `P1 智能待办 / 提醒 / 日历` 后端存储链路调研。
- 当前状态：`server/services/app_api/json_store.py` 对集合资源的 `create/update/delete/clear` 都是整文件读取后再整文件写回，目前没有显式进程内锁或更细粒度并发保护。
- 影响：在当前数据量很小时问题不大，但后续如果 planning 资源种类和联动写入继续增加，容易出现性能抖动、并发覆盖与跨资源一致性风险。
- 建议动作：后续单独立项评估是否给 JSON store 增加最小锁保护、批量写接口，或在合适时机迁移到更稳的持久层。
- 本轮处理：未处理。

### Checkpoint 2026-04-09-06 reminder `repeat` 的校验与调度口径不一致

- 发现来源：本轮 `P1 智能待办 / 提醒 / 日历` reminder 调度调研。
- 当前状态：`server/services/app_api/resource_service.py` 对 reminder `repeat` 只要求“非空字符串”，但 `server/services/reminder_scheduler.py` 对未知值会静默降级成 `daily`。
- 影响：前端、agent 或未来脚本一旦写入拼错的 `repeat` 值，后端不会在创建阶段报错，却会在运行阶段按 `daily` 执行，容易造成口径偏差和误触发。
- 建议动作：后续单独立项统一 `repeat` 的允许枚举、错误返回和前端/agent 侧契约，避免“创建成功但语义被静默改写”。
- 本轮处理：未处理。

### Checkpoint 2026-04-10-01 `app/lib/providers/control_center_provider.dart` 已退化为未使用的兼容层

- 发现来源：本轮 `P0 剩余硬件协同与设备控制闭环` 调研。
- 当前状态：`app/lib/providers/control_center_provider.dart` 只保留两个透传 `appControllerProvider` 的 Provider，仓库内已没有任何引用。
- 影响：后续继续扩设备控制或通知提醒时，容易让人误以为 Control Center 还有独立 provider 分层，增加阅读噪音和错误落点。
- 建议动作：后续单独立项决定是删除该兼容文件，还是恢复成真实的 Control Center 状态封装；在当前任务中不应顺手处理。
- 本轮处理：未处理。

### Checkpoint 2026-04-10-02 `ControlCenterScreen` 仍在 `build()` 中回写设备控制草稿值

- 发现来源：本轮 `P0 剩余硬件协同与设备控制闭环` 前端收口。
- 当前状态：`app/lib/screens/control_center/control_center_screen.dart` 目前会在 runtime token 变化时，于 `build()` 内同步 `_volume`、`_brightness` 和 `_colorController.text`。
- 影响：当前实现能满足“优先显示 runtime 真读回”，但如果后续设备状态刷新更频繁，用户在编辑 LED 颜色时仍可能遇到输入被回写、光标跳动或草稿被覆盖的问题。
- 建议动作：后续单独立项，把 runtime -> 表单草稿同步收敛到更稳定的表单状态策略，例如按焦点/提交态区分自动回填时机。
- 本轮处理：未处理。

### Checkpoint 2026-04-10-03 demo 固件的 `battery / charging` 仍是占位遥测

- 发现来源：本轮天气真实性与首页 `Device Snapshot` 排查。
- 当前状态：`firmware/arduino/demo/demo.ino` 仍写死 `battery = -1`、`charging = false`，因此首页当前只能通过前端文案把它标成 `Unknown / Demo placeholder`，不能当成真实硬件电源状态。
- 影响：在固件未接入真实电量/充电检测前，任何 `Battery / Charging` 验收都只能算 UI 语义正确，不能算硬件遥测闭环已打通。
- 建议动作：后续单独立项接入真实电量与充电检测，并同步定义“未接通/读取失败/真实数值”的上报契约。
- 本轮处理：未处理。

### Checkpoint 2026-04-10-04 后端全量 `unittest` 仍有 bootstrap 测试漂移

- 发现来源：本轮提交前自动化测试。
- 当前状态：执行 `server/.venv/bin/python -m unittest discover -s tests -q` 时，`test_bootstrap_cors` 仍按旧签名调用 `create_http_app()`，`test_bootstrap_provider_timeout` 仍在无事件循环环境下直接触发 `ReminderScheduler()`；这 3 个失败与本轮 `device_channel / Device Snapshot` 改动无直接关系。
- 影响：后续如果继续把 “后端全量 unittest 全绿” 当成提交通道，会被这组既有 bootstrap 测试阻塞，也不利于区分“本轮回归”与“历史测试债务”。
- 建议动作：后续单独立项修正 bootstrap 测试夹具，使其和当前 `create_http_app()` / `create_agent()` 的依赖契约对齐，再恢复全量后端 suite 作为稳定门禁。
- 本轮处理：未处理。

### Checkpoint 2026-04-10-05 移动端底部 dock 在新增 `Agenda` 后已接近拥挤上限

- 发现来源：本轮 `P1-1` 新增 `/app/agenda` 导航入口。
- 当前状态：`app/lib/widgets/common/app_bottom_dock.dart` 仍是等宽平铺；现在主壳层已存在 `Home / Chat / Agenda / Tasks / Control / Settings` 六个入口。
- 影响：在更窄的手机宽度下，底部图标加文案的可读性会继续下降，后续如果再新增主入口或做多语言文案，拥挤问题会更明显。
- 建议动作：后续单独立项评估移动端是否需要改成“图标优先 + 精简文案”、可横向滚动 dock，或把低频入口收进 `More`。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-01 `SessionManager` 仍是整份 JSONL 重写，后续会成为聊天性能热点

- 发现来源：本轮任务调度与性能优化调研。
- 当前状态：`server/nanobot/session/manager.py` 的 `save()` 仍按整个 session 文件重写，聊天消息越多，单次保存越重。
- 影响：会话历史增长后，消息写入、会话切换和 session 列表衍生统计都会更容易出现耗时抖动；并发写入策略也会越来越脆弱。
- 建议动作：后续单独立项，把聊天热路径从 JSONL 迁到更稳的持久层，优先评估 `SQLite + WAL`，并把会话列表依赖的摘要字段改成增量维护。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-02 `MessageBus` 仍是无界队列且 observer 在入队前同步执行

- 发现来源：本轮任务调度与性能优化调研。
- 当前状态：`server/nanobot/bus/queue.py` 中 `inbound` / `outbound` 仍是无界 `asyncio.Queue()`，并且 `publish_inbound()` / `publish_outbound()` 会先同步 `await _notify()` 再真正 `put()`。
- 影响：流量波峰时缺少背压保护；一旦 observer 变慢，消息甚至还没入队就先被拖住，容易放大延迟。
- 建议动作：后续单独立项，为消息队列补 `maxsize`、优先级和观测指标，并把“补 task_id/message_id”与“重型 observer 逻辑”分层，减少入队前阻塞。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-03 App 事件广播仍会被慢 WebSocket 客户端拖住

- 发现来源：本轮任务调度与性能优化调研。
- 当前状态：`server/services/app_runtime.py` 的 `_broadcast_event()` 仍是逐个 `await ws.send_json(event)` 广播，没有每客户端独立发送队列。
- 影响：只要某个前端连接特别慢、挂起或网络抖动，就可能拖慢整轮事件广播，影响其他正常客户端的实时体验。
- 建议动作：后续单独立项，为每个 WebSocket 客户端增加独立发送队列和 writer task，并对高频 progress 类事件增加合并/丢弃策略。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-04 `UnifiedOutboundRouter` 单消费者模型容易形成出站串行堵塞

- 发现来源：本轮任务调度与性能优化调研。
- 当前状态：`server/services/outbound_router.py` 目前用单个 consumer 统一处理 `device / desktop_voice / whatsapp / app` 出站消息。
- 影响：任一慢通道都会形成 head-of-line blocking，例如设备回放或外部渠道发送变慢时，其他通道消息也会跟着排队。
- 建议动作：后续单独立项，把出站路由拆成至少 `app_realtime / device_voice / external_channels` 三条 lane，避免互相拖累。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-05 Reminder 调度仍是固定间隔全量轮询

- 发现来源：本轮任务调度与性能优化调研。
- 当前状态：`server/services/reminder_scheduler.py` 仍按固定 `poll_interval_s=15.0` 周期醒来，并对全部 reminder 做检查。
- 影响：提醒数量增长后会出现无谓空转，且到点精度受轮询间隔限制，不利于后续扩展更复杂的日程/提醒体系。
- 建议动作：后续单独立项，把 reminder 调度改成基于 `next_trigger_at` 的最小堆或等价 next-fire 调度模型；如果未来进入多进程/多实例阶段，再评估 APScheduler / Redis Streams。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-06 `voice_handoff_card.dart` 已退化为 Chat 改版后的兼容旧组件

- 发现来源：本轮 Chat 页面桌面化重构。
- 当前状态：新的 Chat 页面已经把语音状态收敛为轻量 `ChatStatusStrip`，不再使用 `app/lib/widgets/chat/voice_handoff_card.dart` 这类右侧大卡。
- 影响：后续如果继续把 `VoiceHandoffCard` 当成 Chat 主路径组件维护，容易让桌面聊天页再次回到 dashboard 式布局，也会增加阅读噪音。
- 建议动作：后续单独立项决定是删除该旧组件，还是明确保留为其他场景的兼容卡片；当前任务不顺手清理。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-07 `chat_session_panel.dart` 已降级为兼容外壳，主路径实际改用 dialog/list 组合

- 发现来源：本轮 Chat 页面桌面化重构。
- 当前状态：会话管理主交互已经迁到 `ChatSessionDialog + ChatSessionList`；`app/lib/widgets/chat/chat_session_panel.dart` 目前更像兼容旧调用形态的外壳层。
- 影响：后续如果不明确这层的新定位，后续 agent 容易在 `panel`、`dialog`、`list` 三处重复加能力，重新制造分叉。
- 建议动作：后续单独立项决定是否彻底删掉 `panel` 兼容层，或明确只保留一个唯一主入口组件。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-06 `desktop_voice.*` 事件已发出，但 Flutter 端仍未消费细粒度语音事件

- 发现来源：本轮 `AI 电脑端能力调研`。
- 当前状态：`server/services/app_runtime.py` 已广播 `desktop_voice.state.changed / transcript / response / error` 事件，但 `app/lib/providers/app_providers.dart` 当前没有对应 case；前端主要只通过 `refreshRuntime()` 的聚合状态感知桌面语音桥是否 ready。
- 影响：桌面麦克风链路虽然已经存在，但 App 内目前缺少实时 transcript / response / error 的细粒度可视反馈，语音联调和用户理解成本偏高。

### Checkpoint 2026-04-11-08 Robot Pairing 仍是纯手填 LAN host，缺少本机网卡候选提示

- 发现来源：本轮“机器人首次配对与前端配网”实施收口。
- 当前状态：`app/lib/widgets/connect/device_pairing_panel.dart` 已实现 loopback 防呆和后端 host 校验闭环，但仍要求用户手动填写 `LAN Host`，没有展示当前电脑可选的本机网卡 IPv4 列表。
- 影响：对熟悉网络的用户已经够用，但首次部署时仍可能出现“后端能连 localhost，机器人却连不上”的理解成本；特别是在多网卡机器上，手填体验不够强引导。
- 建议动作：后续单独立项为 `Robot Pairing` 面板补“本机候选地址”提示或一键带入能力，明确这只是本机网卡候选，不是 LAN scan / device discovery。
- 本轮处理：未处理。
- 建议动作：后续单独立项，为 Chat 或 Control Center 增加 Voice Activity 视图，直接消费 `desktop_voice.*` 事件，而不是只看 runtime 摘要。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-07 Agent 工具基础设施与当前 runtime 接线范围已有口径偏差

- 发现来源：本轮 `AI 电脑端能力调研`。
- 当前状态：代码层已经有 `CronTool`、MCP 包装层和 `web_search` 支持，但当前 `server/bootstrap.py` 没把 `cron_service`、`mcp_servers`、`brave_api_key`、`restrict_to_workspace` 接进 `AgentLoop` 启动路径。
- 影响：后续如果只看工具代码，容易高估“当前 build 已开放给 AI 的电脑端能力”；反过来，`read_file / write_file / edit_file / exec` 的实际边界又比“只限 workspace”更宽，产品口径和安全口径都容易漂移。
- 建议动作：后续单独立项，明确一份“当前 runtime 已启用工具矩阵 + 权限边界”文档，或把 bootstrap 接线补齐并补前端权限提示。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-08 `server/workspace/skills/computer-control/SKILL.md` 与 `server/workspace/SOUL.md` 仍把电脑控制等同于 raw `exec`

- 发现来源：本轮 `P1-3 设备控制产品化 / 电脑控制产品化` 调研。
- 当前状态：`server/workspace/skills/computer-control/SKILL.md` 仍标记 `always: true`，并直接指导使用 `exec` 打开应用、操作文件和查进程；`server/workspace/SOUL.md` 也把“控制电脑”直接表述为 `exec` 能力。
- 影响：即使后续补出结构化 `computer_control` 服务层，agent 仍可能绕过未来的白名单、确认和审计链路，导致产品口径和实际执行边界不一致。
- 建议动作：后续实现 `P1-3` 时，同步把这两处口径改成“结构化 `computer_control` 优先、raw `exec` 仅限调试/后备”，并明确高风险外发动作必须走确认流。
- 本轮处理：未处理。

### Checkpoint 2026-04-13-01 WeChat `experimental_ui` 仍是占位开关

- 发现来源：本轮 `P1-5 / P1-6` 与微信发送边界调研。
- 当前状态：`server/services/computer_control/policies.py` 仍保留 `wechat_experimental_ui` 配置，但 `server/services/computer_control/adapters/wechat.py` 里这个开关只会改变返回文案，不会开启真实 UI 自动化或发送能力。
- 影响：后续如果只看配置层，容易误以为“打开 experimental_ui 就能自动化发送微信”，从而高估当前产品能力边界。
- 建议动作：后续单独立项决定是删掉这个占位开关，还是补一套真正可验证的专用 UI 自动化适配器；在当前任务中不顺手处理。
- 本轮处理：未处理。

### Checkpoint 2026-04-13-03 `./manager.sh backend-restart` 本轮出现“pid 已写入但服务口未稳定监听”

- 发现来源：本轮“陪伴模式”实时同步问题的联调验证。
- 当前状态：执行 `./manager.sh backend-restart` 后，`.manager/server.pid` 会更新并输出“后端已启动”，但本轮实测随即出现 `connection refused`，随后 `8765` 端口未监听，`server.pid` 对应进程也不再存在；最终只能改用 `server/.venv/bin/python main.py` 前台拉起完成验证。
- 影响：后续如果继续依赖 `backend-restart` 作为日常联调动作，容易误以为“代码没生效”或“前端没刷新”，实际是服务没有稳定跑住。
- 建议动作：后续单独立项排查 `manager.sh` 的后台启动与存活检测逻辑，至少补齐“启动后端口探测 / 进程存活二次确认 / 失败时清理过期 pid”的诊断闭环。
- 本轮处理：未处理。

### Checkpoint 2026-04-13-02 扬声器 DIN 引脚文档与当前固件口径不一致

- 发现来源：本轮 `P1-6 物理交互产品化` 固件调研。
- 当前状态：部分历史文档仍按 `IO8` 记录扬声器 DIN，引导口径与当前 `firmware/arduino/demo/demo.ino`、`test4`、`test4_tts` 使用的 `IO21` 不一致。
- 影响：后续做焊接、排障、装配或复现音频问题时，容易因为旧文档误导而走错接线或判断方向。
- 建议动作：后续单独立项统一 `CLAUDE.md`、硬件测试文档和固件注释里的音频引脚口径，避免继续积累硬件文档债。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-09 `computer_control.allowed_scripts` 的“字符串数组”口径与实际解析行为不一致

- 发现来源：本轮 `P1-3` 主线程静态代码复核。
- 当前状态：`server/config.py` 仍允许 `computer_control.allowed_scripts` 以“字符串数组”通过校验，但 `server/services/computer_control/policies.py` 的 `_parse_scripts()` 只有在每个脚本项能解析出 `command` 时才会真正纳入 allowlist；纯字符串数组在当前实现下会被静默丢弃。
- 影响：如果后续有人按“字符串数组”去配 `allowed_scripts`，配置层看起来合法，但运行时 `run_script` 仍会报未 allowlist，容易产生“配置已生效”的误判。
- 建议动作：后续单独立项，二选一收口这个契约：要么把 `allowed_scripts` 明确收紧为对象配置，要么补齐“字符串数组”的真实解析语义，并同步更新文档与示例。
- 本轮处理：未处理。

### Checkpoint 2026-04-11-10 `Connect` 连接配置与 `Settings` 里的 `server_url/server_port` 已形成双数据源

- 发现来源：本轮“机器人首次配对与前端配网”调研。
- 当前状态：`app/lib/models/connect/connection_config_model.dart` + `app/lib/services/storage/auth_storage_service.dart` 持久化的是 operator console 实际连接用的 `host/port/token`；同时 `app/lib/models/settings/settings_model.dart` / `server/services/app_api/settings_service.py` 还维护了一份 `server_url/server_port` 设置字段。
- 影响：后续一旦机器人 pairing 默认值、App 实际连接地址和 Settings 里的服务端地址三者不一致，用户可能会把机器人配到 A 地址，而 operator console 自己连在 B 地址，造成“App 在线、机器人离线”的隐性错配。
- 建议动作：后续单独立项统一“谁是前端侧唯一可信的服务端地址来源”，至少要明确 `Connect` 与 `Settings` 的职责边界，避免再叠第三套来源。
- 本轮处理：未处理。
