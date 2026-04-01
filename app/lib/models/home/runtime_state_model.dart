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

class RuntimeStateModel {
  const RuntimeStateModel({
    required this.currentTask,
    required this.taskQueue,
    required this.device,
    required this.todoSummary,
    required this.calendarSummary,
  });

  final RuntimeTaskModel? currentTask;
  final List<RuntimeTaskModel> taskQueue;
  final DeviceStatusModel device;
  final TodoSummaryModel todoSummary;
  final CalendarSummaryModel calendarSummary;

  RuntimeStateModel copyWithCurrentTask(RuntimeTaskModel? currentTask) {
    return RuntimeStateModel(
      currentTask: currentTask,
      taskQueue: taskQueue,
      device: device,
      todoSummary: todoSummary,
      calendarSummary: calendarSummary,
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
    );
  }

  factory RuntimeStateModel.empty() {
    return RuntimeStateModel(
      currentTask: null,
      taskQueue: const <RuntimeTaskModel>[],
      device: DeviceStatusModel.empty(),
      todoSummary: TodoSummaryModel.empty(),
      calendarSummary: CalendarSummaryModel.empty(),
    );
  }
}
