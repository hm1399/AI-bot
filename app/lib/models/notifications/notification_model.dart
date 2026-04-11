import '../common/source_context_model.dart';

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.message,
    required this.read,
    required this.createdAt,
    required this.metadata,
    this.bundleId,
    this.createdVia,
    this.sourceChannel,
    this.interactionSurface,
    this.captureSource,
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
  final String type;
  final String priority;
  final String title;
  final String message;
  final bool read;
  final String createdAt;
  final Map<String, dynamic> metadata;
  final String? bundleId;
  final String? createdVia;
  final String? sourceChannel;
  final String? interactionSurface;
  final String? captureSource;
  final String? sourceSessionId;
  final String? sourceMessageId;
  final String? linkedTaskId;
  final String? linkedEventId;
  final String? linkedReminderId;
  final String? normalizedTime;
  final Map<String, dynamic> normalizedTimes;
  final List<String> conflictSummaries;
  final Map<String, dynamic> planningMetadata;

  SourceContextModel get sourceContext => SourceContextModel.fromMetadata(
    sourceChannel: sourceChannel,
    interactionSurface: interactionSurface,
    captureSource: captureSource,
    createdVia: createdVia,
  );

  String get sourceLabel => sourceContext.label;

  NotificationModel copyWith({bool? read}) {
    return NotificationModel(
      id: id,
      type: type,
      priority: priority,
      title: title,
      message: message,
      read: read ?? this.read,
      createdAt: createdAt,
      metadata: metadata,
      bundleId: bundleId,
      createdVia: createdVia,
      sourceChannel: sourceChannel,
      interactionSurface: interactionSurface,
      captureSource: captureSource,
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

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final metadata = _asMap(json['metadata']);
    final planningMetadata = _extractPlanningMetadata(json, metadata);
    return NotificationModel(
      id: json['notification_id']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      priority: json['priority']?.toString() ?? 'medium',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      read: json['read'] == true,
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      metadata: metadata,
      bundleId: _readNullableString(planningMetadata, const <String>[
        'bundle_id',
      ]),
      createdVia: _readNullableString(planningMetadata, const <String>[
        'created_via',
      ]),
      sourceChannel: _readNullableString(planningMetadata, const <String>[
        'source_channel',
      ]),
      interactionSurface: _readNullableString(planningMetadata, const <String>[
        'interaction_surface',
      ]),
      captureSource: _readNullableString(planningMetadata, const <String>[
        'capture_source',
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
}

Map<String, dynamic> _extractPlanningMetadata(
  Map<String, dynamic> json,
  Map<String, dynamic> metadata,
) {
  final planning = <String, dynamic>{};
  for (final source in <Map<String, dynamic>>[
    _asMap(json['planning']),
    _asMap(json['planning_metadata']),
    _asMap(metadata['planning']),
    metadata,
  ]) {
    if (source.isNotEmpty) {
      planning.addAll(source);
    }
  }

  for (final entry in const <MapEntry<String, String>>[
    MapEntry<String, String>('task_id', 'linked_task_id'),
    MapEntry<String, String>('event_id', 'linked_event_id'),
    MapEntry<String, String>('reminder_id', 'linked_reminder_id'),
  ]) {
    if (!planning.containsKey(entry.value) && planning.containsKey(entry.key)) {
      planning[entry.value] = planning[entry.key];
    }
  }

  for (final key in const <String>[
    'bundle_id',
    'created_via',
    'source_channel',
    'interaction_surface',
    'capture_source',
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
    if (!planning.containsKey(key) && json.containsKey(key)) {
      planning[key] = json[key];
    }
  }

  return planning;
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
  return summaries.toSet().toList();
}
