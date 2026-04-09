class PlanningOverviewModel {
  const PlanningOverviewModel({
    this.generatedAt,
    this.windowStart,
    this.windowEnd,
    this.bundleCount = 0,
    this.taskCount = 0,
    this.pendingTaskCount = 0,
    this.completedTaskCount = 0,
    this.overdueTaskCount = 0,
    this.eventCount = 0,
    this.todayEventCount = 0,
    this.reminderCount = 0,
    this.activeReminderCount = 0,
    this.conflictCount = 0,
    this.nextItemAt,
    this.nextItemTitle,
    this.nextConflictSummary,
    this.metadata = const <String, dynamic>{},
  });

  final String? generatedAt;
  final String? windowStart;
  final String? windowEnd;
  final int bundleCount;
  final int taskCount;
  final int pendingTaskCount;
  final int completedTaskCount;
  final int overdueTaskCount;
  final int eventCount;
  final int todayEventCount;
  final int reminderCount;
  final int activeReminderCount;
  final int conflictCount;
  final String? nextItemAt;
  final String? nextItemTitle;
  final String? nextConflictSummary;
  final Map<String, dynamic> metadata;

  factory PlanningOverviewModel.fromJson(Map<String, dynamic> json) {
    final source = _firstMap(<dynamic>[
      json['overview'],
      json['summary'],
      json,
    ]);
    final counts = _firstMap(<dynamic>[source['counts']]);
    final tasks = _firstMap(<dynamic>[source['tasks'], counts['tasks']]);
    final events = _firstMap(<dynamic>[source['events'], counts['events']]);
    final reminders = _firstMap(<dynamic>[
      source['reminders'],
      counts['reminders'],
    ]);
    final conflicts = _firstMap(<dynamic>[
      source['conflicts'],
      counts['conflicts'],
    ]);
    final nextItem = _firstMap(<dynamic>[
      source['next_item'],
      source['next'],
      source['upcoming_item'],
    ]);

    return PlanningOverviewModel(
      generatedAt: _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['generated_at', 'updated_at', 'last_updated_at'],
      ),
      windowStart: _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['window_start', 'timeline_window_start', 'start_at'],
      ),
      windowEnd: _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['window_end', 'timeline_window_end', 'end_at'],
      ),
      bundleCount: _readIntAny(
        <Map<String, dynamic>>[source, counts],
        const <String>['bundle_count'],
      ),
      taskCount: _readIntAny(
        <Map<String, dynamic>>[source, counts, tasks],
        const <String>['task_count', 'count', 'total'],
      ),
      pendingTaskCount: _readIntAny(
        <Map<String, dynamic>>[source, tasks],
        const <String>['pending_task_count', 'pending_count'],
      ),
      completedTaskCount: _readIntAny(
        <Map<String, dynamic>>[source, tasks],
        const <String>['completed_task_count', 'completed_count'],
      ),
      overdueTaskCount: _readIntAny(
        <Map<String, dynamic>>[source, tasks],
        const <String>['overdue_task_count', 'overdue_count'],
      ),
      eventCount: _readIntAny(
        <Map<String, dynamic>>[source, counts, events],
        const <String>['event_count', 'count', 'total'],
      ),
      todayEventCount: _readIntAny(
        <Map<String, dynamic>>[source, events],
        const <String>['today_event_count', 'today_count'],
      ),
      reminderCount: _readIntAny(
        <Map<String, dynamic>>[source, counts, reminders],
        const <String>['reminder_count', 'count', 'total'],
      ),
      activeReminderCount: _readIntAny(
        <Map<String, dynamic>>[source, reminders],
        const <String>[
          'active_reminder_count',
          'active_count',
          'enabled_count',
        ],
      ),
      conflictCount: _readIntAny(
        <Map<String, dynamic>>[source, conflicts],
        const <String>['conflict_count', 'count', 'total'],
      ),
      nextItemAt: _readStringAny(
        <Map<String, dynamic>>[source, nextItem],
        const <String>['next_item_at', 'at', 'sort_at', 'start_at'],
      ),
      nextItemTitle: _readStringAny(
        <Map<String, dynamic>>[source, nextItem],
        const <String>['next_item_title', 'title', 'summary'],
      ),
      nextConflictSummary: _readStringAny(
        <Map<String, dynamic>>[source, conflicts],
        const <String>['next_conflict_summary', 'summary', 'title', 'message'],
      ),
      metadata: source,
    );
  }
}

Map<String, dynamic> _firstMap(List<dynamic> values) {
  for (final value in values) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
  }
  return <String, dynamic>{};
}

int _readIntAny(List<Map<String, dynamic>> sources, List<String> keys) {
  for (final source in sources) {
    for (final key in keys) {
      final value = source[key];
      if (value is int) {
        return value;
      }
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return 0;
}

String? _readStringAny(List<Map<String, dynamic>> sources, List<String> keys) {
  for (final source in sources) {
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}
