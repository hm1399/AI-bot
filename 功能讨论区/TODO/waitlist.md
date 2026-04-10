# waitlist

## 说明

- 只记录本轮调研或文档同步时发现、但未在当前任务内处理的问题。
- 每条使用 checkpoint 记录，等待主线程确认后再决定是否立项或回填。

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
