class PlanningTimelineItemModel {
  const PlanningTimelineItemModel({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    required this.title,
    this.description,
    this.status,
    this.priority,
    this.sortAt,
    this.startAt,
    this.endAt,
    this.dueAt,
    this.nextTriggerAt,
    this.timeLabel,
    this.completed = false,
    this.allDay = false,
    this.overdue = false,
    this.bundleId,
    this.createdVia,
    this.normalizedTime,
    this.normalizedTimes = const <String, dynamic>{},
    this.linkedTaskId,
    this.linkedEventId,
    this.linkedReminderId,
    this.conflictSummaries = const <String>[],
    this.resource = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String resourceType;
  final String resourceId;
  final String title;
  final String? description;
  final String? status;
  final String? priority;
  final String? sortAt;
  final String? startAt;
  final String? endAt;
  final String? dueAt;
  final String? nextTriggerAt;
  final String? timeLabel;
  final bool completed;
  final bool allDay;
  final bool overdue;
  final String? bundleId;
  final String? createdVia;
  final String? normalizedTime;
  final Map<String, dynamic> normalizedTimes;
  final String? linkedTaskId;
  final String? linkedEventId;
  final String? linkedReminderId;
  final List<String> conflictSummaries;
  final Map<String, dynamic> resource;
  final Map<String, dynamic> metadata;

  DateTime? get sortAtDateTime => _tryParseDateTime(sortAt);

  DateTime? get startAtDateTime => _tryParseDateTime(startAt);

  DateTime? get endAtDateTime => _tryParseDateTime(endAt);

  DateTime? get dueAtDateTime => _tryParseDateTime(dueAt);

  DateTime? get nextTriggerDateTime => _tryParseDateTime(nextTriggerAt);

  factory PlanningTimelineItemModel.fromJson(Map<String, dynamic> json) {
    final source = _firstMap(<dynamic>[json['item'], json]);
    final resource = _firstMap(<dynamic>[source['resource']]);
    final effectiveResource = resource.isEmpty ? source : resource;
    final resourceType =
        _readStringAny(
          <Map<String, dynamic>>[source, effectiveResource],
          const <String>['resource_type', 'kind', 'type'],
        ) ??
        _inferResourceType(effectiveResource);
    final planningMetadata = _extractPlanningMetadata(
      source,
      effectiveResource,
    );
    final resourceId =
        _readStringAny(
          <Map<String, dynamic>>[source, effectiveResource],
          <String>['resource_id', '${resourceType}_id', 'id'],
        ) ??
        '';

    return PlanningTimelineItemModel(
      id:
          _readStringAny(
            <Map<String, dynamic>>[source],
            const <String>['timeline_item_id', 'id'],
          ) ??
          (resourceId.isEmpty ? resourceType : '$resourceType:$resourceId'),
      resourceType: resourceType,
      resourceId: resourceId,
      title:
          _readStringAny(
            <Map<String, dynamic>>[source, effectiveResource],
            const <String>['title', 'summary'],
          ) ??
          '',
      description: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['description', 'message'],
      ),
      status: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['status', 'stage'],
      ),
      priority: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['priority'],
      ),
      sortAt: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>[
          'sort_at',
          'scheduled_at',
          'start_at',
          'next_trigger_at',
          'due_at',
        ],
      ),
      startAt: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['start_at'],
      ),
      endAt: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['end_at'],
      ),
      dueAt: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['due_at'],
      ),
      nextTriggerAt: _readStringAny(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['next_trigger_at'],
      ),
      timeLabel: _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['time_label'],
      ),
      completed:
          _readBool(
            <Map<String, dynamic>>[source, effectiveResource],
            const <String>['completed'],
          ) ||
          _readStringAny(
                <Map<String, dynamic>>[source, effectiveResource],
                const <String>['status'],
              ) ==
              'completed',
      allDay: _readBool(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['all_day'],
      ),
      overdue: _readBool(
        <Map<String, dynamic>>[source, effectiveResource],
        const <String>['overdue', 'is_overdue'],
      ),
      bundleId: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['bundle_id'],
      ),
      createdVia: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['created_via'],
      ),
      normalizedTime: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['normalized_time'],
      ),
      normalizedTimes: _firstMap(<dynamic>[
        planningMetadata['normalized_times'],
      ]),
      linkedTaskId: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['linked_task_id'],
      ),
      linkedEventId: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['linked_event_id'],
      ),
      linkedReminderId: _readStringAny(
        <Map<String, dynamic>>[planningMetadata],
        const <String>['linked_reminder_id'],
      ),
      conflictSummaries: _readConflictSummaries(source, planningMetadata),
      resource: effectiveResource,
      metadata: source,
    );
  }
}

Map<String, dynamic> _extractPlanningMetadata(
  Map<String, dynamic> source,
  Map<String, dynamic> resource,
) {
  final metadata = <String, dynamic>{};
  for (final candidate in <dynamic>[
    source['planning'],
    source['planning_metadata'],
    resource['planning'],
    resource['planning_metadata'],
    resource['metadata'],
  ]) {
    final map = _firstMap(<dynamic>[candidate]);
    if (map.isNotEmpty) {
      metadata.addAll(map);
    }
  }

  for (final key in const <String>[
    'bundle_id',
    'created_via',
    'linked_task_id',
    'linked_event_id',
    'linked_reminder_id',
    'normalized_time',
    'normalized_times',
    'conflict_summary',
    'conflict_summaries',
  ]) {
    if (!metadata.containsKey(key) && resource.containsKey(key)) {
      metadata[key] = resource[key];
    }
    if (!metadata.containsKey(key) && source.containsKey(key)) {
      metadata[key] = source[key];
    }
  }

  return metadata;
}

String _inferResourceType(Map<String, dynamic> resource) {
  if (resource.containsKey('event_id')) {
    return 'event';
  }
  if (resource.containsKey('reminder_id')) {
    return 'reminder';
  }
  if (resource.containsKey('task_id')) {
    return 'task';
  }
  return 'planning';
}

Map<String, dynamic> _firstMap(List<dynamic> values) {
  for (final value in values) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
  }
  return <String, dynamic>{};
}

bool _readBool(List<Map<String, dynamic>> sources, List<String> keys) {
  for (final source in sources) {
    for (final key in keys) {
      final value = source[key];
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
  }
  return false;
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

DateTime? _tryParseDateTime(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

List<String> _readConflictSummaries(
  Map<String, dynamic> source,
  Map<String, dynamic> planningMetadata,
) {
  final summaries = <String>[];
  for (final candidate in <dynamic>[
    planningMetadata['conflict_summaries'],
    source['conflict_summaries'],
    planningMetadata['conflicts'],
    source['conflicts'],
  ]) {
    if (candidate is List) {
      for (final item in candidate) {
        if (item is String && item.trim().isNotEmpty) {
          summaries.add(item.trim());
          continue;
        }
        if (item is Map<String, dynamic>) {
          final summary = _readStringAny(
            <Map<String, dynamic>>[item],
            const <String>['summary', 'title', 'message'],
          );
          if (summary != null) {
            summaries.add(summary);
          }
        }
      }
    }
  }

  final single = _readStringAny(
    <Map<String, dynamic>>[planningMetadata, source],
    const <String>['conflict_summary'],
  );
  if (single != null) {
    summaries.insert(0, single);
  }

  return summaries.toSet().toList();
}
