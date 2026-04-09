class RuntimeTaskModel {
  const RuntimeTaskModel({
    required this.taskId,
    required this.kind,
    required this.sourceChannel,
    required this.sourceSessionId,
    required this.summary,
    required this.stage,
    required this.cancellable,
    required this.startedAt,
  });

  final String taskId;
  final String kind;
  final String sourceChannel;
  final String sourceSessionId;
  final String summary;
  final String stage;
  final bool cancellable;
  final String? startedAt;

  factory RuntimeTaskModel.fromJson(Map<String, dynamic> json) {
    return RuntimeTaskModel(
      taskId: json['task_id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'chat',
      sourceChannel: json['source_channel']?.toString() ?? 'app',
      sourceSessionId: json['source_session_id']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      stage: json['stage']?.toString() ?? 'queued',
      cancellable: json['cancellable'] == true,
      startedAt: json['started_at']?.toString(),
    );
  }
}

class DeviceStatusModel {
  const DeviceStatusModel({
    required this.connected,
    required this.state,
    required this.battery,
    required this.wifiRssi,
    required this.wifiSignal,
    required this.charging,
    required this.reconnectCount,
  });

  final bool connected;
  final String state;
  final int battery;
  final int wifiRssi;
  final int wifiSignal;
  final bool charging;
  final int reconnectCount;

  factory DeviceStatusModel.fromJson(Map<String, dynamic> json) {
    final wifiRssi = json['wifi_rssi'] is int
        ? json['wifi_rssi'] as int
        : int.tryParse(json['wifi_rssi']?.toString() ?? '') ?? 0;
    final normalized = wifiRssi == 0
        ? 0
        : (((wifiRssi + 100) / 60) * 100).round().clamp(0, 100);
    return DeviceStatusModel(
      connected: json['connected'] == true,
      state: (json['state']?.toString() ?? 'unknown').toLowerCase(),
      battery: json['battery'] is int
          ? json['battery'] as int
          : int.tryParse(json['battery']?.toString() ?? '') ?? -1,
      wifiRssi: wifiRssi,
      wifiSignal: normalized,
      charging: json['charging'] == true,
      reconnectCount: json['reconnect_count'] is int
          ? json['reconnect_count'] as int
          : int.tryParse(json['reconnect_count']?.toString() ?? '') ?? 0,
    );
  }

  factory DeviceStatusModel.empty() {
    return const DeviceStatusModel(
      connected: false,
      state: 'unknown',
      battery: -1,
      wifiRssi: 0,
      wifiSignal: 0,
      charging: false,
      reconnectCount: 0,
    );
  }
}

class VoiceStatusModel {
  const VoiceStatusModel({
    required this.reportedByBackend,
    required this.desktopBridgeReady,
    required this.deviceFeedbackReady,
    required this.backendPipelineReady,
    required this.inputMode,
    required this.outputMode,
    required this.status,
    required this.statusMessage,
    required this.lastError,
  });

  final bool reportedByBackend;
  final bool desktopBridgeReady;
  final bool deviceFeedbackReady;
  final bool backendPipelineReady;
  final String inputMode;
  final String outputMode;
  final String status;
  final String? statusMessage;
  final String? lastError;

  factory VoiceStatusModel.fromParentJson(Map<String, dynamic> json) {
    final payload = _extractVoicePayload(json);
    if (payload == null) {
      return VoiceStatusModel.empty();
    }
    return VoiceStatusModel.fromJson(payload);
  }

  factory VoiceStatusModel.fromJson(Map<String, dynamic> json) {
    final bridge = json['desktop_bridge'] is Map<String, dynamic>
        ? json['desktop_bridge'] as Map<String, dynamic>
        : json;
    return VoiceStatusModel(
      reportedByBackend: true,
      desktopBridgeReady: _readBool(bridge, const <String>[
        'desktop_bridge_ready',
        'desktop_mic_bridge_ready',
        'bridge_ready',
        'desktop_ready',
        'ready',
      ]),
      deviceFeedbackReady: _readBool(json, const <String>[
        'device_feedback_ready',
        'device_ready',
      ]),
      backendPipelineReady: _readBool(json, const <String>[
        'backend_pipeline_ready',
        'pipeline_ready',
        'ready',
      ]),
      inputMode: _readString(json, const <String>[
        'input_mode',
        'capture_mode',
      ], fallback: 'device_press_desktop_mic'),
      outputMode: _readString(json, const <String>[
        'output_mode',
        'response_mode',
      ], fallback: 'device_text_feedback'),
      status: _readString(bridge, const <String>[
        'status',
        'bridge_state',
      ], fallback: 'unknown'),
      statusMessage: _readNullableString(bridge, const <String>[
        'status_message',
        'note',
        'message',
      ]),
      lastError: _readNullableString(bridge, const <String>[
        'last_error',
        'error',
      ]),
    );
  }

  factory VoiceStatusModel.empty() {
    return const VoiceStatusModel(
      reportedByBackend: false,
      desktopBridgeReady: false,
      deviceFeedbackReady: false,
      backendPipelineReady: false,
      inputMode: 'device_press_desktop_mic',
      outputMode: 'device_text_feedback',
      status: 'unknown',
      statusMessage: null,
      lastError: null,
    );
  }

  static Map<String, dynamic>? _extractVoicePayload(Map<String, dynamic> json) {
    for (final key in <String>[
      'voice',
      'voice_status',
      'voice_bridge',
      'desktop_voice',
    ]) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }
    return null;
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      final normalized = value?.toString().trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return false;
  }

  static String _readString(
    Map<String, dynamic> json,
    List<String> keys, {
    required String fallback,
  }) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  static String? _readNullableString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class TodoSummaryModel {
  const TodoSummaryModel({
    required this.enabled,
    required this.pendingCount,
    required this.overdueCount,
    required this.nextDueAt,
  });

  final bool enabled;
  final int pendingCount;
  final int overdueCount;
  final String? nextDueAt;

  factory TodoSummaryModel.fromJson(Map<String, dynamic> json) {
    return TodoSummaryModel(
      enabled: json['enabled'] == true,
      pendingCount: json['pending_count'] is int
          ? json['pending_count'] as int
          : int.tryParse(json['pending_count']?.toString() ?? '') ?? 0,
      overdueCount: json['overdue_count'] is int
          ? json['overdue_count'] as int
          : int.tryParse(json['overdue_count']?.toString() ?? '') ?? 0,
      nextDueAt: json['next_due_at']?.toString(),
    );
  }

  factory TodoSummaryModel.empty() {
    return const TodoSummaryModel(
      enabled: false,
      pendingCount: 0,
      overdueCount: 0,
      nextDueAt: null,
    );
  }
}

class CalendarSummaryModel {
  const CalendarSummaryModel({
    required this.enabled,
    required this.todayCount,
    required this.nextEventAt,
    required this.nextEventTitle,
  });

  final bool enabled;
  final int todayCount;
  final String? nextEventAt;
  final String? nextEventTitle;

  factory CalendarSummaryModel.fromJson(Map<String, dynamic> json) {
    return CalendarSummaryModel(
      enabled: json['enabled'] == true,
      todayCount: json['today_count'] is int
          ? json['today_count'] as int
          : int.tryParse(json['today_count']?.toString() ?? '') ?? 0,
      nextEventAt: json['next_event_at']?.toString(),
      nextEventTitle: json['next_event_title']?.toString(),
    );
  }

  factory CalendarSummaryModel.empty() {
    return const CalendarSummaryModel(
      enabled: false,
      todayCount: 0,
      nextEventAt: null,
      nextEventTitle: null,
    );
  }
}

class ReminderRuntimeStateModel {
  const ReminderRuntimeStateModel({
    this.reportedByBackend = false,
    this.schedulerRunning = false,
    this.nextTriggerAt,
    this.lastTriggeredAt,
    this.lastError,
    this.metadata = const <String, dynamic>{},
  });

  final bool reportedByBackend;
  final bool schedulerRunning;
  final String? nextTriggerAt;
  final String? lastTriggeredAt;
  final String? lastError;
  final Map<String, dynamic> metadata;

  factory ReminderRuntimeStateModel.fromParentJson(Map<String, dynamic> json) {
    final payload = _extractNestedRuntimePayload(json, const <String>[
      'reminders',
      'reminder_runtime',
    ]);
    if (payload.isEmpty) {
      return const ReminderRuntimeStateModel();
    }
    return ReminderRuntimeStateModel.fromJson(payload);
  }

  factory ReminderRuntimeStateModel.fromJson(Map<String, dynamic> json) {
    return ReminderRuntimeStateModel(
      reportedByBackend: true,
      schedulerRunning: _runtimeReadBool(json, const <String>[
        'scheduler_running',
        'running',
      ]),
      nextTriggerAt: _runtimeReadNullableString(json, const <String>[
        'next_trigger_at',
        'next_due_at',
      ]),
      lastTriggeredAt: _runtimeReadNullableString(json, const <String>[
        'last_triggered_at',
      ]),
      lastError: _runtimeReadNullableString(json, const <String>['last_error']),
      metadata: Map<String, dynamic>.from(json),
    );
  }
}

class PlanningRuntimeStateModel {
  const PlanningRuntimeStateModel({
    this.reportedByBackend = false,
    this.available = false,
    this.overviewReady = false,
    this.timelineReady = false,
    this.conflictsReady = false,
    this.conflictCount = 0,
    this.generatedAt,
    this.metadata = const <String, dynamic>{},
  });

  final bool reportedByBackend;
  final bool available;
  final bool overviewReady;
  final bool timelineReady;
  final bool conflictsReady;
  final int conflictCount;
  final String? generatedAt;
  final Map<String, dynamic> metadata;

  factory PlanningRuntimeStateModel.fromParentJson(Map<String, dynamic> json) {
    final payload = _extractNestedRuntimePayload(json, const <String>[
      'planning',
      'planning_runtime',
    ]);
    if (payload.isEmpty) {
      return const PlanningRuntimeStateModel();
    }
    return PlanningRuntimeStateModel.fromJson(payload);
  }

  factory PlanningRuntimeStateModel.fromJson(Map<String, dynamic> json) {
    return PlanningRuntimeStateModel(
      reportedByBackend: true,
      available:
          _runtimeReadBool(json, const <String>['available', 'enabled']) ||
          json.isNotEmpty,
      overviewReady: _runtimeReadBool(json, const <String>['overview_ready']),
      timelineReady: _runtimeReadBool(json, const <String>['timeline_ready']),
      conflictsReady: _runtimeReadBool(json, const <String>['conflicts_ready']),
      conflictCount: _runtimeReadInt(json, const <String>[
        'conflict_count',
        'pending_conflicts',
      ]),
      generatedAt: _runtimeReadNullableString(json, const <String>[
        'generated_at',
        'updated_at',
        'last_updated_at',
      ]),
      metadata: Map<String, dynamic>.from(json),
    );
  }
}

class RuntimeStateModel {
  const RuntimeStateModel({
    required this.currentTask,
    required this.taskQueue,
    required this.device,
    required this.voice,
    required this.todoSummary,
    required this.calendarSummary,
    this.reminders = const ReminderRuntimeStateModel(),
    this.planning = const PlanningRuntimeStateModel(),
  });

  final RuntimeTaskModel? currentTask;
  final List<RuntimeTaskModel> taskQueue;
  final DeviceStatusModel device;
  final VoiceStatusModel voice;
  final TodoSummaryModel todoSummary;
  final CalendarSummaryModel calendarSummary;
  final ReminderRuntimeStateModel reminders;
  final PlanningRuntimeStateModel planning;

  RuntimeStateModel copyWithCurrentTask(RuntimeTaskModel? currentTask) {
    return RuntimeStateModel(
      currentTask: currentTask,
      taskQueue: taskQueue,
      device: device,
      voice: voice,
      todoSummary: todoSummary,
      calendarSummary: calendarSummary,
      reminders: reminders,
      planning: planning,
    );
  }

  factory RuntimeStateModel.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['task_queue'] is List
        ? json['task_queue'] as List<dynamic>
        : const <dynamic>[];
    return RuntimeStateModel(
      currentTask: json['current_task'] is Map<String, dynamic>
          ? RuntimeTaskModel.fromJson(
              json['current_task'] as Map<String, dynamic>,
            )
          : null,
      taskQueue: rawQueue
          .map(
            (dynamic item) => RuntimeTaskModel.fromJson(
              item is Map<String, dynamic> ? item : <String, dynamic>{},
            ),
          )
          .toList(),
      device: DeviceStatusModel.fromJson(
        json['device'] is Map<String, dynamic>
            ? json['device'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      voice: VoiceStatusModel.fromParentJson(json),
      todoSummary: TodoSummaryModel.fromJson(
        json['todo_summary'] is Map<String, dynamic>
            ? json['todo_summary'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      calendarSummary: CalendarSummaryModel.fromJson(
        json['calendar_summary'] is Map<String, dynamic>
            ? json['calendar_summary'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      reminders: ReminderRuntimeStateModel.fromParentJson(json),
      planning: PlanningRuntimeStateModel.fromParentJson(json),
    );
  }

  factory RuntimeStateModel.empty() {
    return RuntimeStateModel(
      currentTask: null,
      taskQueue: const <RuntimeTaskModel>[],
      device: DeviceStatusModel.empty(),
      voice: VoiceStatusModel.empty(),
      todoSummary: TodoSummaryModel.empty(),
      calendarSummary: CalendarSummaryModel.empty(),
      reminders: const ReminderRuntimeStateModel(),
      planning: const PlanningRuntimeStateModel(),
    );
  }
}

Map<String, dynamic> _extractNestedRuntimePayload(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key];
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
  }
  return <String, dynamic>{};
}

bool _runtimeReadBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return false;
}

int _runtimeReadInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return 0;
}

String? _runtimeReadNullableString(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
