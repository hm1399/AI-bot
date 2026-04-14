import '../common/source_context_model.dart';

class MessageModel {
  const MessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.text,
    required this.status,
    required this.createdAt,
    this.metadata = const <String, dynamic>{},
    this.errorReason,
  });

  final String id;
  final String sessionId;
  final String role;
  final String text;
  final String status;
  final String createdAt;
  final Map<String, dynamic> metadata;
  final String? errorReason;

  PlanningMessageMetadata get planningMetadata =>
      PlanningMessageMetadata.fromMetadata(metadata);

  bool get hasPlanningMetadata => planningMetadata.hasVisibleContent;

  SourceContextModel get sourceContext {
    final scopes = _collectSourceMetadataScopes(metadata);
    return SourceContextModel.fromMetadata(
      sourceChannel: _firstNonEmptyString(scopes, const <String>[
        'source_channel',
        'sourceChannel',
      ]),
      interactionSurface: _firstNonEmptyString(scopes, const <String>[
        'interaction_surface',
        'interactionSurface',
      ]),
      captureSource: _firstNonEmptyString(scopes, const <String>[
        'capture_source',
        'captureSource',
      ]),
      createdVia: _firstNonEmptyString(scopes, const <String>[
        'created_via',
        'createdVia',
      ]),
      sceneMode: _firstNonEmptyString(scopes, const <String>[
        'scene_mode',
        'sceneMode',
      ]),
      personaProfileId: _firstNonEmptyString(scopes, const <String>[
        'persona_profile_id',
        'personaProfileId',
        'persona_profile',
        'personaProfile',
      ]),
      personaVoiceStyle: _firstNonEmptyString(scopes, const <String>[
        'persona_voice_style',
        'personaVoiceStyle',
      ]),
      interactionKind: _firstNonEmptyString(scopes, const <String>[
        'interaction_kind',
        'interactionKind',
      ]),
      interactionMode: _firstNonEmptyString(scopes, const <String>[
        'interaction_mode',
        'interactionMode',
      ]),
      approvalSource: _firstNonEmptyString(scopes, const <String>[
        'approval_source',
        'approvalSource',
      ]),
    );
  }

  String get sourceLabel => sourceContext.label;

  String? get sceneMode => sourceContext.sceneMode;

  String? get personaProfileId => sourceContext.personaProfileId;

  MessageModel copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? text,
    String? status,
    String? createdAt,
    Map<String, dynamic>? metadata,
    String? errorReason,
  }) {
    return MessageModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
      errorReason: errorReason ?? this.errorReason,
    );
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final role = json['role']?.toString() ?? 'user';
    final status = json['status']?.toString() ?? 'completed';
    return MessageModel(
      id: json['message_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      role: role == 'assistant' || role == 'system' ? role : 'user',
      text: json['content']?.toString() ?? '',
      status: status == 'pending' || status == 'streaming' || status == 'failed'
          ? status
          : 'completed',
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      metadata: _coerceStringMap(json['metadata']),
      errorReason: json['reason']?.toString(),
    );
  }
}

List<Map<String, dynamic>> _collectSourceMetadataScopes(
  Map<String, dynamic> metadata,
) {
  final root = _coerceStringMap(metadata);
  if (root.isEmpty) {
    return const <Map<String, dynamic>>[];
  }
  final scopes = <Map<String, dynamic>>[root];
  for (final key in <String>[
    'source',
    'context',
    'message_context',
    'messageContext',
    'interaction',
    'experience',
    'source_context',
    'sourceContext',
  ]) {
    final nested = _coerceStringMap(root[key]);
    if (nested.isNotEmpty) {
      scopes.add(nested);
    }
  }
  return scopes;
}

class PlanningMessageMetadata {
  const PlanningMessageMetadata({
    required this.action,
    required this.summaryMessage,
    required this.primaryTitle,
    required this.resourceType,
    required this.createdVia,
    required this.resourceIds,
    required this.rawBundleId,
    required this.normalizedTime,
    required this.conflicts,
    required this.requiresUserConfirmation,
    required this.confirmationLabel,
    required this.taskCount,
    required this.eventCount,
    required this.reminderCount,
    required this.planningSurface,
    required this.ownerKind,
    required this.deliveryMode,
  });

  final String? action;
  final String? summaryMessage;
  final String? primaryTitle;
  final String? resourceType;
  final String? createdVia;
  final List<String> resourceIds;
  final String? rawBundleId;
  final String? normalizedTime;
  final List<String> conflicts;
  final bool requiresUserConfirmation;
  final String? confirmationLabel;
  final int taskCount;
  final int eventCount;
  final int reminderCount;
  final String? planningSurface;
  final String? ownerKind;
  final String? deliveryMode;

  String? get bundleId => rawBundleId;

  int get resourceCount => resourceIds.length;

  int get totalResourceCount => taskCount + eventCount + reminderCount;

  bool get hasPlanningContext =>
      action != null ||
      resourceType != null ||
      totalResourceCount > 0 ||
      bundleId != null;

  String get effectivePlanningSurface =>
      _normalizePlanningSurface(planningSurface) ??
      _defaultPlanningSurfaceFor(resourceType);

  String get effectiveOwnerKind =>
      _normalizeOwnerKind(ownerKind) ?? _inferOwnerKind(createdVia) ?? 'user';

  String get effectiveDeliveryMode =>
      _normalizeDeliveryMode(deliveryMode) ?? 'none';

  String? get planningSurfaceLabel =>
      planningSurface != null || hasPlanningContext
      ? _humanizePlanningSurface(effectivePlanningSurface)
      : null;

  String? get ownerLabel => ownerKind != null || createdVia != null
      ? _humanizeOwnerKind(effectiveOwnerKind)
      : null;

  String? get deliveryModeLabel => deliveryMode != null
      ? _humanizeDeliveryMode(effectiveDeliveryMode)
      : null;

  String get summaryHeading {
    if (summaryMessage?.isNotEmpty == true) {
      return summaryMessage!;
    }
    if (primaryTitle?.isNotEmpty == true && actionLabel != null) {
      return '$actionLabel: $primaryTitle';
    }
    if (actionLabel != null) {
      return actionLabel!;
    }
    if (requiresUserConfirmation) {
      return 'Review required';
    }
    if (conflicts.isNotEmpty) {
      return 'Conflict detected';
    }
    if (resourceLabel != null) {
      return 'Planning update';
    }
    if (normalizedTime != null) {
      return 'Time update';
    }
    return 'Structured update';
  }

  String? get actionLabel => _actionLabel(action);

  String? get resourceLabel {
    final typedLabels = <String>[
      if (taskCount > 0) _countLabel(taskCount, 'task'),
      if (eventCount > 0) _countLabel(eventCount, 'event'),
      if (reminderCount > 0) _countLabel(reminderCount, 'reminder'),
    ];
    if (typedLabels.isNotEmpty) {
      return typedLabels.join(', ');
    }
    if (resourceType == null || resourceType!.isEmpty) {
      if (resourceCount <= 0) {
        return null;
      }
      return resourceCount == 1 ? '1 item' : '$resourceCount items';
    }
    if (resourceCount > 1) {
      return '$resourceCount ${_pluralize(resourceType!)}';
    }
    return resourceType;
  }

  String? get conflictSummary {
    if (conflicts.isEmpty) {
      return null;
    }
    if (conflicts.length == 1) {
      return '1 conflict to review';
    }
    return '${conflicts.length} conflicts to review';
  }

  String? get confirmationSummary {
    if (confirmationLabel != null && confirmationLabel!.isNotEmpty) {
      return confirmationLabel;
    }
    if (!requiresUserConfirmation) {
      return null;
    }
    return 'Review this before the assistant continues.';
  }

  bool get hasVisibleContent =>
      (summaryMessage?.isNotEmpty ?? false) ||
      (primaryTitle?.isNotEmpty ?? false) ||
      (actionLabel?.isNotEmpty ?? false) ||
      (resourceLabel?.isNotEmpty ?? false) ||
      (normalizedTime?.isNotEmpty ?? false) ||
      (planningSurfaceLabel?.isNotEmpty ?? false) ||
      (ownerLabel?.isNotEmpty ?? false) ||
      (deliveryModeLabel?.isNotEmpty ?? false) ||
      conflicts.isNotEmpty ||
      requiresUserConfirmation ||
      (confirmationSummary?.isNotEmpty ?? false);

  factory PlanningMessageMetadata.fromMetadata(Map<String, dynamic> metadata) {
    final scopes = _collectMetadataScopes(metadata);
    final resourceIds = _collectDistinctStrings(scopes, <String>[
      'resource_ids',
      'resourceIds',
      'resource_id',
      'resourceId',
      'task_ids',
      'taskIds',
      'task_id',
      'taskId',
      'event_ids',
      'eventIds',
      'event_id',
      'eventId',
      'reminder_ids',
      'reminderIds',
      'reminder_id',
      'reminderId',
    ]);
    final resourceType =
        _firstNonEmptyString(scopes, <String>[
          'resource_type',
          'resourceType',
          'type',
          'kind',
        ]) ??
        _inferResourceType(scopes);
    final confirmationLabel = _firstNonEmptyString(scopes, <String>[
      'confirmation_prompt',
      'confirmationPrompt',
      'confirmation_message',
      'confirmationMessage',
      'confirmation_reason',
      'confirmationReason',
      'next_action',
      'nextAction',
    ]);

    return PlanningMessageMetadata(
      action: _firstNonEmptyString(scopes, <String>['action']),
      summaryMessage: _humanizeReadableText(
        _firstNonEmptyString(scopes, <String>[
          'message',
          'summary',
          'display_message',
          'displayMessage',
        ]),
      ),
      primaryTitle: _humanizeReadableText(
        _firstNonEmptyString(scopes, <String>['title']),
      ),
      resourceType: _humanizeResourceType(resourceType),
      createdVia: _firstNonEmptyString(scopes, <String>[
        'created_via',
        'createdVia',
      ]),
      resourceIds: resourceIds,
      rawBundleId: _firstNonEmptyString(scopes, <String>[
        'bundle_id',
        'bundleId',
        'plan_bundle_id',
        'planBundleId',
      ]),
      normalizedTime: _readNormalizedTimeSummary(scopes),
      conflicts: _collectConflictLabels(scopes),
      requiresUserConfirmation:
          _firstTrue(scopes, <String>[
            'requires_user_confirmation',
            'requiresUserConfirmation',
            'requires_confirmation',
            'requiresConfirmation',
            'confirmation_required',
            'confirmationRequired',
            'user_confirmation_needed',
            'userConfirmationNeeded',
            'needs_confirmation',
            'needsConfirmation',
          ]) ||
          _firstNonEmptyString(scopes, <String>[
                'confirmation_prompt',
                'confirmationPrompt',
                'confirmation_message',
                'confirmationMessage',
                'confirmation_reason',
                'confirmationReason',
              ]) !=
              null,
      confirmationLabel: _humanizeReadableText(confirmationLabel),
      taskCount: _collectDistinctStrings(scopes, <String>[
        'task_ids',
        'task_id',
      ]).length,
      eventCount: _collectDistinctStrings(scopes, <String>[
        'event_ids',
        'event_id',
      ]).length,
      reminderCount: _collectDistinctStrings(scopes, <String>[
        'reminder_ids',
        'reminder_id',
      ]).length,
      planningSurface: _normalizePlanningSurface(
        _firstNonEmptyString(scopes, <String>[
          'planning_surface',
          'planningSurface',
        ]),
      ),
      ownerKind: _normalizeOwnerKind(
        _firstNonEmptyString(scopes, <String>['owner_kind', 'ownerKind']),
      ),
      deliveryMode: _normalizeDeliveryMode(
        _firstNonEmptyString(scopes, <String>['delivery_mode', 'deliveryMode']),
      ),
    );
  }
}

List<Map<String, dynamic>> _collectMetadataScopes(
  Map<String, dynamic> metadata,
) {
  final root = _coerceStringMap(metadata);
  if (root.isEmpty) {
    return const <Map<String, dynamic>>[];
  }
  final scopes = <Map<String, dynamic>>[];

  void addScope(Map<String, dynamic> scope) {
    if (scope.isEmpty) {
      return;
    }
    scopes.add(scope);
    for (final key in <String>[
      'planning',
      'planning_metadata',
      'planningMetadata',
      'planning_result',
      'planningResult',
      'structured_result',
      'structuredResult',
      'metadata',
      'result',
      'payload',
      'bundle',
      'resource',
      'resource_reference',
      'resourceReference',
      'confirmation',
      'task',
      'event',
      'reminder',
    ]) {
      final nested = _coerceStringMap(scope[key]);
      if (nested.isNotEmpty) {
        addScope(nested);
      }
    }
  }

  final toolResults = _coerceStringMap(root['tool_results']);
  final planningResults = toolResults['planning'];
  if (planningResults is Iterable) {
    for (final item in planningResults) {
      addScope(_coerceStringMap(item));
    }
  } else {
    addScope(_coerceStringMap(planningResults));
  }

  addScope(root);
  return scopes;
}

Map<String, dynamic> _coerceStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

String? _firstNonEmptyString(
  List<Map<String, dynamic>> scopes,
  List<String> keys,
) {
  for (final scope in scopes) {
    for (final key in keys) {
      final value = _stringify(scope[key]);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}

bool _firstTrue(List<Map<String, dynamic>> scopes, List<String> keys) {
  for (final scope in scopes) {
    for (final key in keys) {
      final value = _toBool(scope[key]);
      if (value == true) {
        return true;
      }
    }
  }
  return false;
}

List<String> _collectDistinctStrings(
  List<Map<String, dynamic>> scopes,
  List<String> keys,
) {
  final results = <String>[];
  for (final scope in scopes) {
    for (final key in keys) {
      final value = scope[key];
      if (value is Iterable) {
        for (final item in value) {
          final stringValue = _stringify(item);
          if (stringValue != null && stringValue.isNotEmpty) {
            results.addAll(_splitValues(stringValue));
          }
        }
        continue;
      }
      final stringValue = _stringify(value);
      if (stringValue != null && stringValue.isNotEmpty) {
        results.addAll(_splitValues(stringValue));
      }
    }
  }
  return _dedupe(results);
}

List<String> _splitValues(String value) {
  if (!value.contains(',') && !value.contains('|')) {
    return <String>[value.trim()];
  }
  return value
      .split(RegExp(r'[,\|]'))
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toList();
}

List<String> _collectConflictLabels(List<Map<String, dynamic>> scopes) {
  final conflicts = <String>[];
  for (final scope in scopes) {
    for (final key in <String>[
      'conflicts',
      'conflict_items',
      'conflictItems',
      'detected_conflicts',
      'detectedConflicts',
      'conflict',
    ]) {
      final value = scope[key];
      if (value is Iterable) {
        for (final item in value) {
          final label = _conflictLabel(item);
          if (label != null) {
            conflicts.add(label);
          }
        }
      } else {
        final label = _conflictLabel(value);
        if (label != null) {
          conflicts.add(label);
        }
      }
    }
  }
  return _dedupe(conflicts);
}

String? _conflictLabel(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value ? 'Potential conflict detected.' : null;
  }
  if (value is Map) {
    final map = _coerceStringMap(value);
    return _humanizeReadableText(
      _firstNonEmptyString(
        <Map<String, dynamic>>[map],
        <String>['summary', 'title', 'message', 'reason', 'detail', 'label'],
      ),
    );
  }
  final stringValue = _humanizeReadableText(_stringify(value));
  return stringValue == null || stringValue.isEmpty ? null : stringValue;
}

String? _inferResourceType(List<Map<String, dynamic>> scopes) {
  for (final scope in scopes) {
    final action = _stringify(scope['action'])?.toLowerCase();
    if (action != null) {
      if (action.contains('task')) {
        return 'task';
      }
      if (action.contains('event')) {
        return 'event';
      }
      if (action.contains('reminder')) {
        return 'reminder';
      }
      if (action == 'list_today') {
        return 'planning item';
      }
    }
    if (scope.containsKey('task_id') || scope.containsKey('task_ids')) {
      return 'task';
    }
    if (scope.containsKey('event_id') || scope.containsKey('event_ids')) {
      return 'event';
    }
    if (scope.containsKey('reminder_id') || scope.containsKey('reminder_ids')) {
      return 'reminder';
    }
  }
  return null;
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

String _defaultPlanningSurfaceFor(String? resourceType) {
  switch (resourceType?.trim().toLowerCase()) {
    case 'task':
    case 'tasks':
      return 'tasks';
    case 'event':
    case 'events':
    case 'reminder':
    case 'reminders':
      return 'agenda';
  }
  return 'agenda';
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
  switch (value) {
    case 'agenda':
      return 'Agenda surface';
    case 'tasks':
      return 'Tasks surface';
    case 'hidden':
      return 'Hidden surface';
  }
  return _humanizeToken(value);
}

String _humanizeOwnerKind(String value) {
  switch (value) {
    case 'assistant':
      return 'Assistant-owned';
    case 'user':
      return 'User-owned';
  }
  return _humanizeToken(value);
}

String? _humanizeDeliveryMode(String value) {
  switch (value) {
    case 'none':
      return null;
    case 'device_voice':
      return 'Device voice';
    case 'device_voice_and_notification':
      return 'Device voice + notification';
  }
  return _humanizeToken(value);
}

String _humanizeToken(String value) {
  final words = value
      .split(RegExp(r'[_\s-]+'))
      .where((String item) => item.isNotEmpty)
      .map(
        (String item) =>
            '${item[0].toUpperCase()}${item.substring(1).toLowerCase()}',
      )
      .toList();
  return words.join(' ');
}

String? _stringify(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.trim();
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value is Map) {
    final map = _coerceStringMap(value);
    final label = _firstNonEmptyString(
      <Map<String, dynamic>>[map],
      <String>[
        'label',
        'summary',
        'title',
        'value',
        'id',
        'iso',
        'start',
        'at',
        'time',
      ],
    );
    return label?.trim();
  }
  return value.toString().trim();
}

bool? _toBool(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == 'yes' || text == '1') {
    return true;
  }
  if (text == 'false' || text == 'no' || text == '0') {
    return false;
  }
  return null;
}

String? _readNormalizedTimeSummary(List<Map<String, dynamic>> scopes) {
  final direct = _firstNonEmptyString(scopes, <String>[
    'normalized_time',
    'normalizedTime',
    'normalized_at',
    'normalizedAt',
    'scheduled_for',
    'scheduledFor',
    'target_time',
    'targetTime',
    'time_summary',
    'timeSummary',
  ]);
  final directSummary = _formatStructuredTimeValue(direct);
  if (directSummary != null) {
    return directSummary;
  }

  for (final scope in scopes) {
    for (final key in <String>[
      'normalized_times',
      'normalizedTimes',
      'time_window',
      'timeWindow',
      'time_range',
      'timeRange',
    ]) {
      final summary = _formatStructuredTimeValue(scope[key]);
      if (summary != null) {
        return summary;
      }
    }
  }
  return null;
}

String? _formatStructuredTimeValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    final map = _coerceStringMap(value);
    final summary = _humanizeReadableText(
      _firstNonEmptyString(
        <Map<String, dynamic>>[map],
        <String>['summary', 'label', 'display', 'text'],
      ),
    );
    if (summary != null) {
      return summary;
    }

    final start = _firstNonEmptyString(
      <Map<String, dynamic>>[map],
      <String>['start', 'from', 'begin', 'at', 'time'],
    );
    final end = _firstNonEmptyString(
      <Map<String, dynamic>>[map],
      <String>['end', 'to', 'until'],
    );
    final date = _firstNonEmptyString(
      <Map<String, dynamic>>[map],
      <String>['date', 'day'],
    );

    final startSummary = _formatTimeLabel(start);
    final endSummary = _formatTimeLabel(end);
    final dateSummary = _formatTimeLabel(date);

    if (startSummary != null && endSummary != null) {
      if (_areSameCalendarDay(start, end)) {
        final parsedEnd = DateTime.tryParse(end!);
        final endTimeOnly = parsedEnd == null
            ? endSummary
            : _formatClockLabel(
                parsedEnd.isUtc ? parsedEnd.toLocal() : parsedEnd,
              );
        return '$startSummary to $endTimeOnly';
      }
      return '$startSummary to $endSummary';
    }
    return startSummary ?? dateSummary ?? endSummary;
  }
  if (value is Iterable) {
    final items = value
        .map(_formatStructuredTimeValue)
        .whereType<String>()
        .where((String item) => item.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      return null;
    }
    return _dedupe(items).join(' · ');
  }
  return _formatTimeLabel(value.toString());
}

bool _areSameCalendarDay(String? left, String? right) {
  final leftDate = DateTime.tryParse(left ?? '');
  final rightDate = DateTime.tryParse(right ?? '');
  if (leftDate == null || rightDate == null) {
    return false;
  }
  final normalizedLeft = leftDate.isUtc ? leftDate.toLocal() : leftDate;
  final normalizedRight = rightDate.isUtc ? rightDate.toLocal() : rightDate;
  return normalizedLeft.year == normalizedRight.year &&
      normalizedLeft.month == normalizedRight.month &&
      normalizedLeft.day == normalizedRight.day;
}

String? _formatTimeLabel(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(cleaned);
  if (parsed == null) {
    return _humanizeReadableText(cleaned);
  }
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  final hasExplicitTime = RegExp(r'(?:T|\s)\d{2}:\d{2}').hasMatch(cleaned);
  final datePart =
      '${_weekdayLabel(local.weekday)}, ${_monthLabel(local.month)} ${local.day}';

  if (!hasExplicitTime) {
    return datePart;
  }
  return '$datePart · ${_formatClockLabel(local)}';
}

String _formatClockLabel(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _weekdayLabel(int weekday) {
  return const <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][weekday - 1];
}

String _monthLabel(int month) {
  return const <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

String? _humanizeResourceType(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  final normalized = cleaned
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized
      .split(' ')
      .where((String part) => part.isNotEmpty)
      .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String? _actionLabel(String? action) {
  final cleaned = action?.trim().toLowerCase();
  switch (cleaned) {
    case 'create_task':
      return 'Created task';
    case 'create_event':
      return 'Created event';
    case 'create_reminder':
      return 'Created reminder';
    case 'complete_task':
      return 'Completed task';
    case 'snooze_reminder':
      return 'Snoozed reminder';
    case 'list_today':
      return 'Today\'s plan';
  }
  return null;
}

String _countLabel(int count, String singular) {
  if (count == 1) {
    return '1 $singular';
  }
  return '$count ${_pluralize(singular)}';
}

String _pluralize(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return value;
  }
  if (normalized.endsWith('s')) {
    return normalized;
  }
  return '${normalized}s';
}

String? _humanizeReadableText(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(cleaned)) {
    return cleaned;
  }

  final normalizedWhitespace = cleaned.replaceAll(RegExp(r'\s+'), ' ');
  if ((normalizedWhitespace.contains('_') ||
          normalizedWhitespace.contains('-')) &&
      !normalizedWhitespace.contains(' ')) {
    final words = normalizedWhitespace
        .split(RegExp(r'[_\-]+'))
        .where((String part) => part.isNotEmpty)
        .map((String part) => part.toLowerCase())
        .toList();
    if (words.isNotEmpty) {
      final sentence = words.join(' ');
      return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
    }
  }
  return normalizedWhitespace;
}

List<String> _dedupe(List<String> values) {
  final seen = <String>{};
  final deduped = <String>[];
  for (final value in values) {
    if (seen.add(value)) {
      deduped.add(value);
    }
  }
  return deduped;
}
