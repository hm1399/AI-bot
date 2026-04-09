class AppEventModel {
  AppEventModel({
    required this.eventId,
    required this.eventType,
    required this.scope,
    required this.occurredAt,
    required this.sessionId,
    required this.taskId,
    required this.payload,
    this.resourceType,
    this.resourceId,
    this.isPlanningEvent = false,
    this.shouldRefreshPlanning = false,
    this.bundleId,
    this.createdVia,
    this.normalizedTime,
    this.normalizedTimes = const <String, dynamic>{},
    this.linkedTaskId,
    this.linkedEventId,
    this.linkedReminderId,
    this.conflictSummaries = const <String>[],
    this.planningMetadata = const <String, dynamic>{},
  });

  final String eventId;
  final String eventType;
  final String scope;
  final String occurredAt;
  final String? sessionId;
  final String? taskId;
  final Map<String, dynamic> payload;
  final String? resourceType;
  final String? resourceId;
  final bool isPlanningEvent;
  final bool shouldRefreshPlanning;
  final String? bundleId;
  final String? createdVia;
  final String? normalizedTime;
  final Map<String, dynamic> normalizedTimes;
  final String? linkedTaskId;
  final String? linkedEventId;
  final String? linkedReminderId;
  final List<String> conflictSummaries;
  final Map<String, dynamic> planningMetadata;

  factory AppEventModel.fromJson(Map<String, dynamic> json) {
    final eventType = json['event_type']?.toString() ?? '';
    final payload = _asMap(json['payload']);
    final resourcePayload = _extractPrimaryResourcePayload(payload);
    final resourceType = _extractResourceType(payload, resourcePayload);
    final planningMetadata = _extractPlanningMetadata(
      json,
      payload,
      resourcePayload,
    );
    final isPlanningEvent =
        eventType.startsWith('planning.') ||
        json['scope']?.toString() == 'planning' ||
        resourceType == 'planning' ||
        payload.containsKey('planning') ||
        planningMetadata.isNotEmpty;
    return AppEventModel(
      eventId: json['event_id']?.toString() ?? '',
      eventType: eventType,
      scope: json['scope']?.toString() ?? 'global',
      occurredAt:
          json['occurred_at']?.toString() ?? DateTime.now().toIso8601String(),
      sessionId: json['session_id']?.toString(),
      taskId: json['task_id']?.toString(),
      payload: payload,
      resourceType: resourceType,
      resourceId: _readResourceId(
        resourcePayload.isEmpty ? payload : resourcePayload,
        resourceType,
      ),
      isPlanningEvent: isPlanningEvent,
      shouldRefreshPlanning:
          _readBool(json, const <String>[
            'should_refresh_planning',
            'refresh_planning',
          ]) ||
          _readBool(payload, const <String>[
            'should_refresh_planning',
            'refresh_planning',
          ]) ||
          _readBool(planningMetadata, const <String>[
            'should_refresh_planning',
            'refresh_planning',
            'should_refresh',
          ]) ||
          eventType.startsWith('planning.'),
      bundleId: _readNullableString(planningMetadata, const <String>[
        'bundle_id',
      ]),
      createdVia: _readNullableString(planningMetadata, const <String>[
        'created_via',
      ]),
      normalizedTime: _readNullableString(planningMetadata, const <String>[
        'normalized_time',
      ]),
      normalizedTimes: _asMap(planningMetadata['normalized_times']),
      linkedTaskId: _readNullableString(planningMetadata, const <String>[
        'linked_task_id',
      ]),
      linkedEventId: _readNullableString(planningMetadata, const <String>[
        'linked_event_id',
      ]),
      linkedReminderId: _readNullableString(planningMetadata, const <String>[
        'linked_reminder_id',
      ]),
      conflictSummaries: _readConflictSummaries(planningMetadata),
      planningMetadata: planningMetadata,
    );
  }
}

Map<String, dynamic> _extractPrimaryResourcePayload(
  Map<String, dynamic> payload,
) {
  for (final key in const <String>[
    'planning',
    'task',
    'event',
    'reminder',
    'notification',
    'resource',
  ]) {
    final value = payload[key];
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
  }
  return <String, dynamic>{};
}

String? _extractResourceType(
  Map<String, dynamic> payload,
  Map<String, dynamic> resourcePayload,
) {
  final explicit = _readNullableString(payload, const <String>[
    'resource_type',
    'kind',
    'type',
  ]);
  if (explicit != null) {
    return explicit;
  }
  for (final key in const <String>[
    'planning',
    'task',
    'event',
    'reminder',
    'notification',
  ]) {
    if (payload[key] is Map<String, dynamic>) {
      return key;
    }
  }
  final resourceKind = _readNullableString(resourcePayload, const <String>[
    'resource_type',
    'kind',
    'type',
  ]);
  return resourceKind;
}

String? _readResourceId(Map<String, dynamic> json, String? resourceType) {
  if (resourceType == null) {
    return _readNullableString(json, const <String>['resource_id', 'id']);
  }
  return _readNullableString(json, <String>[
    '${resourceType}_id',
    'resource_id',
    'id',
  ]);
}

Map<String, dynamic> _extractPlanningMetadata(
  Map<String, dynamic> json,
  Map<String, dynamic> payload,
  Map<String, dynamic> resourcePayload,
) {
  final metadata = <String, dynamic>{};
  final sources = <Map<String, dynamic>>[
    _asMap(json['planning']),
    _asMap(json['planning_metadata']),
    _asMap(payload['planning']),
    _asMap(payload['planning_metadata']),
    _asMap(resourcePayload['planning']),
    _asMap(resourcePayload['planning_metadata']),
    _asMap(resourcePayload['metadata']),
  ];

  for (final source in sources) {
    if (source.isNotEmpty) {
      metadata.addAll(source);
    }
  }

  for (final key in const <String>[
    'bundle_id',
    'created_via',
    'normalized_time',
    'normalized_times',
    'source_channel',
    'source_message_id',
    'source_session_id',
    'linked_task_id',
    'linked_event_id',
    'linked_reminder_id',
    'conflict_summary',
    'conflict_summaries',
    'should_refresh_planning',
    'refresh_planning',
    'should_refresh',
  ]) {
    if (!metadata.containsKey(key) && resourcePayload.containsKey(key)) {
      metadata[key] = resourcePayload[key];
    }
    if (!metadata.containsKey(key) && payload.containsKey(key)) {
      metadata[key] = payload[key];
    }
    if (!metadata.containsKey(key) && json.containsKey(key)) {
      metadata[key] = json[key];
    }
  }

  return metadata;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
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

String? _readNullableString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

List<String> _readConflictSummaries(Map<String, dynamic> json) {
  final summaries = <String>[];
  for (final key in const <String>['conflict_summaries', 'conflicts']) {
    final value = json[key];
    if (value is List) {
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) {
          summaries.add(item.trim());
          continue;
        }
        if (item is Map<String, dynamic>) {
          final summary = _readNullableString(item, const <String>[
            'summary',
            'title',
            'message',
          ]);
          if (summary != null) {
            summaries.add(summary);
          }
        }
      }
    }
  }

  final single = _readNullableString(json, const <String>['conflict_summary']);
  if (single != null) {
    summaries.insert(0, single);
  }
  return summaries.toSet().toList();
}
