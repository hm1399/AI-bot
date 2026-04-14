import '../common/source_context_model.dart';

class ReminderModel {
  const ReminderModel({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.repeat,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
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
    this.planningSurface,
    this.ownerKind,
    this.deliveryMode,
    this.nextTriggerAt,
    this.lastTriggeredAt,
    this.lastError,
    this.snoozedUntil,
    this.completedAt,
    this.status,
    this.planningMetadata = const <String, dynamic>{},
    this.runtimeMetadata = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final String repeat;
  final bool enabled;
  final String createdAt;
  final String updatedAt;
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
  final String? planningSurface;
  final String? ownerKind;
  final String? deliveryMode;
  final String? nextTriggerAt;
  final String? lastTriggeredAt;
  final String? lastError;
  final String? snoozedUntil;
  final String? completedAt;
  final String? status;
  final Map<String, dynamic> planningMetadata;
  final Map<String, dynamic> runtimeMetadata;

  SourceContextModel get sourceContext => SourceContextModel.fromMetadata(
    sourceChannel: sourceChannel,
    interactionSurface: interactionSurface,
    captureSource: captureSource,
    createdVia: createdVia,
  );

  String get sourceLabel => sourceContext.label;

  DateTime? get nextTriggerDateTime => _tryParseDateTime(nextTriggerAt);

  DateTime? get snoozedUntilDateTime => _tryParseDateTime(snoozedUntil);

  DateTime? get updatedDateTime => _tryParseDateTime(updatedAt);

  String? get normalizedPlanningSurface =>
      _normalizePlanningSurface(planningSurface);

  String get effectiveOwnerKind =>
      _normalizeOwnerKind(ownerKind) ?? _inferOwnerKind(createdVia) ?? 'user';

  String get effectiveDeliveryMode =>
      _normalizeDeliveryMode(deliveryMode) ?? 'none';

  bool get belongsToAgenda =>
      normalizedPlanningSurface == null ||
      normalizedPlanningSurface == 'agenda';

  bool get isHiddenSurface => normalizedPlanningSurface == 'hidden';

  bool get isAssistantOwned => effectiveOwnerKind == 'assistant';

  String? get planningSurfaceLabel => normalizedPlanningSurface == null
      ? null
      : _humanizePlanningSurface(normalizedPlanningSurface!);

  String get ownerLabel => _humanizeOwnerKind(effectiveOwnerKind);

  String? get deliveryModeLabel => _humanizeDeliveryMode(effectiveDeliveryMode);

  ReminderModel copyWith({
    String? title,
    String? message,
    String? time,
    String? repeat,
    bool? enabled,
  }) {
    return ReminderModel(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      time: time ?? this.time,
      repeat: repeat ?? this.repeat,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: DateTime.now().toIso8601String(),
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
      planningSurface: planningSurface,
      ownerKind: ownerKind,
      deliveryMode: deliveryMode,
      nextTriggerAt: nextTriggerAt,
      lastTriggeredAt: lastTriggeredAt,
      lastError: lastError,
      snoozedUntil: snoozedUntil,
      completedAt: completedAt,
      status: status,
      planningMetadata: planningMetadata,
      runtimeMetadata: runtimeMetadata,
    );
  }

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    final planningMetadata = _extractPlanningMetadata(json);
    final runtimeMetadata = _extractRuntimeMetadata(json);
    return ReminderModel(
      id: json['reminder_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      repeat: json['repeat']?.toString() ?? 'daily',
      enabled: json['enabled'] == true,
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt:
          json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
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
      planningSurface: _normalizePlanningSurface(
        _readNullableString(planningMetadata, const <String>[
          'planning_surface',
          'planningSurface',
        ]),
      ),
      ownerKind: _normalizeOwnerKind(
        _readNullableString(planningMetadata, const <String>[
          'owner_kind',
          'ownerKind',
        ]),
      ),
      deliveryMode: _normalizeDeliveryMode(
        _readNullableString(planningMetadata, const <String>[
          'delivery_mode',
          'deliveryMode',
        ]),
      ),
      nextTriggerAt: _readNullableString(runtimeMetadata, const <String>[
        'next_trigger_at',
      ]),
      lastTriggeredAt: _readNullableString(runtimeMetadata, const <String>[
        'last_triggered_at',
      ]),
      lastError: _readNullableString(runtimeMetadata, const <String>[
        'last_error',
      ]),
      snoozedUntil: _readNullableString(runtimeMetadata, const <String>[
        'snoozed_until',
      ]),
      completedAt: _readNullableString(runtimeMetadata, const <String>[
        'completed_at',
      ]),
      status: _readNullableString(runtimeMetadata, const <String>['status']),
      planningMetadata: planningMetadata,
      runtimeMetadata: runtimeMetadata,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return <String, dynamic>{
      'title': title,
      'message': message.isEmpty ? null : message,
      'time': time,
      'repeat': repeat,
      'enabled': enabled,
      if (bundleId != null) 'bundle_id': bundleId,
      if (createdVia != null) 'created_via': createdVia,
      if (sourceChannel != null) 'source_channel': sourceChannel,
      if (interactionSurface != null) 'interaction_surface': interactionSurface,
      if (captureSource != null) 'capture_source': captureSource,
      if (sourceSessionId != null) 'source_session_id': sourceSessionId,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (linkedTaskId != null) 'linked_task_id': linkedTaskId,
      if (linkedEventId != null) 'linked_event_id': linkedEventId,
      if (linkedReminderId != null) 'linked_reminder_id': linkedReminderId,
      if (normalizedTime != null) 'normalized_time': normalizedTime,
      if (normalizedTimes.isNotEmpty) 'normalized_times': normalizedTimes,
      if (planningSurface != null) 'planning_surface': planningSurface,
      if (ownerKind != null) 'owner_kind': ownerKind,
      if (deliveryMode != null) 'delivery_mode': deliveryMode,
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
    'planning_surface',
    'owner_kind',
    'delivery_mode',
  ]) {
    if (!metadata.containsKey(key) && json.containsKey(key)) {
      metadata[key] = json[key];
    }
  }

  return metadata;
}

Map<String, dynamic> _extractRuntimeMetadata(Map<String, dynamic> json) {
  final runtime = <String, dynamic>{};
  final runtimePayload = _asMap(json['runtime']);
  if (runtimePayload.isNotEmpty) {
    runtime.addAll(runtimePayload);
  }

  for (final key in const <String>[
    'next_trigger_at',
    'last_triggered_at',
    'last_error',
    'snoozed_until',
    'completed_at',
    'status',
  ]) {
    if (!runtime.containsKey(key) && json.containsKey(key)) {
      runtime[key] = json[key];
    }
  }

  return runtime;
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

String? _normalizePlanningSurface(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'agenda':
    case 'tasks':
    case 'hidden':
      return value!.trim().toLowerCase();
  }
  return null;
}

String? _normalizeOwnerKind(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'assistant':
    case 'user':
      return value!.trim().toLowerCase();
  }
  return null;
}

String? _inferOwnerKind(String? createdVia) {
  final normalized = createdVia?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (<String>{'agent', 'assistant', 'ai'}.contains(normalized) ||
      normalized.contains('agent')) {
    return 'assistant';
  }
  return 'user';
}

String? _normalizeDeliveryMode(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll(
    RegExp(r'[\s\-]+'),
    '_',
  );
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String _humanizePlanningSurface(String value) {
  return switch (value) {
    'agenda' => 'Agenda surface',
    'tasks' => 'Tasks surface',
    'hidden' => 'Hidden surface',
    _ => _humanizeToken(value),
  };
}

String _humanizeOwnerKind(String value) {
  return switch (value) {
    'assistant' => 'Assistant-owned',
    'user' => 'User-owned',
    _ => _humanizeToken(value),
  };
}

String? _humanizeDeliveryMode(String value) {
  return switch (value) {
    'none' => null,
    'device_voice' => 'Device voice',
    'device_voice_and_notification' => 'Device voice + notification',
    _ => _humanizeToken(value),
  };
}

String _humanizeToken(String value) {
  final words = value
      .split(RegExp(r'[_\-\s]+'))
      .where((String item) => item.isNotEmpty)
      .map(
        (String item) =>
            '${item[0].toUpperCase()}${item.substring(1).toLowerCase()}',
      )
      .toList();
  return words.join(' ');
}
