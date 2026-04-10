class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.completed,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.bundleId,
    this.createdVia,
    this.sourceChannel,
    this.sourceSessionId,
    this.sourceMessageId,
    this.linkedTaskId,
    this.linkedEventId,
    this.linkedReminderId,
    this.normalizedTime,
    this.normalizedTimes = const <String, dynamic>{},
    this.conflictSummaries = const <String>[],
    this.planningMetadata = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String? description;
  final String priority;
  final bool completed;
  final String? dueAt;
  final String createdAt;
  final String? updatedAt;
  final String? bundleId;
  final String? createdVia;
  final String? sourceChannel;
  final String? sourceSessionId;
  final String? sourceMessageId;
  final String? linkedTaskId;
  final String? linkedEventId;
  final String? linkedReminderId;
  final String? normalizedTime;
  final Map<String, dynamic> normalizedTimes;
  final List<String> conflictSummaries;
  final Map<String, dynamic> planningMetadata;

  DateTime? get dueDateTime => _tryParseDateTime(dueAt);

  DateTime? get updatedDateTime => _tryParseDateTime(updatedAt ?? createdAt);

  TaskModel copyWith({
    String? title,
    String? description,
    String? priority,
    bool? completed,
    String? dueAt,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      bundleId: bundleId,
      createdVia: createdVia,
      sourceChannel: sourceChannel,
      sourceSessionId: sourceSessionId,
      sourceMessageId: sourceMessageId,
      linkedTaskId: linkedTaskId,
      linkedEventId: linkedEventId,
      linkedReminderId: linkedReminderId,
      normalizedTime: normalizedTime,
      normalizedTimes: normalizedTimes,
      conflictSummaries: conflictSummaries,
      planningMetadata: planningMetadata,
    );
  }

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final planningMetadata = _extractPlanningMetadata(json);
    return TaskModel(
      id: json['task_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      priority: json['priority']?.toString() ?? 'medium',
      completed: json['completed'] == true,
      dueAt: json['due_at']?.toString(),
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString(),
      bundleId: _readNullableString(planningMetadata, const <String>[
        'bundle_id',
      ]),
      createdVia: _readNullableString(planningMetadata, const <String>[
        'created_via',
      ]),
      sourceChannel: _readNullableString(planningMetadata, const <String>[
        'source_channel',
      ]),
      sourceSessionId: _readNullableString(planningMetadata, const <String>[
        'source_session_id',
      ]),
      sourceMessageId: _readNullableString(planningMetadata, const <String>[
        'source_message_id',
      ]),
      linkedTaskId: _readNullableString(planningMetadata, const <String>[
        'linked_task_id',
      ]),
      linkedEventId: _readNullableString(planningMetadata, const <String>[
        'linked_event_id',
      ]),
      linkedReminderId: _readNullableString(planningMetadata, const <String>[
        'linked_reminder_id',
      ]),
      normalizedTime: _readNullableString(planningMetadata, const <String>[
        'normalized_time',
      ]),
      normalizedTimes: _asMap(planningMetadata['normalized_times']),
      conflictSummaries: _readConflictSummaries(planningMetadata),
      planningMetadata: planningMetadata,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return <String, dynamic>{
      'title': title,
      'description': description,
      'priority': priority,
      'completed': completed,
      'due_at': dueAt,
      if (bundleId != null) 'bundle_id': bundleId,
      if (createdVia != null) 'created_via': createdVia,
      if (sourceChannel != null) 'source_channel': sourceChannel,
      if (sourceSessionId != null) 'source_session_id': sourceSessionId,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (linkedTaskId != null) 'linked_task_id': linkedTaskId,
      if (linkedEventId != null) 'linked_event_id': linkedEventId,
      if (linkedReminderId != null) 'linked_reminder_id': linkedReminderId,
      if (normalizedTime != null) 'normalized_time': normalizedTime,
      if (normalizedTimes.isNotEmpty) 'normalized_times': normalizedTimes,
    };
  }

  Map<String, dynamic> toUpdateJson() => toCreateJson();
}

Map<String, dynamic> _extractPlanningMetadata(Map<String, dynamic> json) {
  final metadata = <String, dynamic>{};
  for (final source in <Map<String, dynamic>>[
    _asMap(json['planning']),
    _asMap(json['planning_metadata']),
  ]) {
    if (source.isNotEmpty) {
      metadata.addAll(source);
    }
  }

  for (final key in const <String>[
    'bundle_id',
    'created_via',
    'source_channel',
    'source_session_id',
    'source_message_id',
    'linked_task_id',
    'linked_event_id',
    'linked_reminder_id',
    'normalized_time',
    'normalized_times',
    'conflict_summary',
    'conflict_summaries',
  ]) {
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
  final single = _readNullableString(json, const <String>['conflict_summary']);
  if (single != null) {
    summaries.add(single);
  }

  final multi = json['conflict_summaries'];
  if (multi is List) {
    for (final item in multi) {
      if (item is String && item.trim().isNotEmpty) {
        summaries.add(item.trim());
      }
    }
  }
  return summaries.toSet().toList();
}

DateTime? _tryParseDateTime(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
