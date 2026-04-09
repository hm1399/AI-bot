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

class PlanningMessageMetadata {
  const PlanningMessageMetadata({
    required this.resourceType,
    required this.resourceIds,
    required this.bundleId,
    required this.normalizedTime,
    required this.conflicts,
    required this.requiresUserConfirmation,
    required this.confirmationLabel,
  });

  final String? resourceType;
  final List<String> resourceIds;
  final String? bundleId;
  final String? normalizedTime;
  final List<String> conflicts;
  final bool requiresUserConfirmation;
  final String? confirmationLabel;

  bool get hasVisibleContent =>
      (resourceType?.isNotEmpty ?? false) ||
      resourceIds.isNotEmpty ||
      (bundleId?.isNotEmpty ?? false) ||
      (normalizedTime?.isNotEmpty ?? false) ||
      conflicts.isNotEmpty ||
      requiresUserConfirmation ||
      (confirmationLabel?.isNotEmpty ?? false);

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

    return PlanningMessageMetadata(
      resourceType: resourceType,
      resourceIds: resourceIds,
      bundleId: _firstNonEmptyString(scopes, <String>[
        'bundle_id',
        'bundleId',
        'plan_bundle_id',
        'planBundleId',
      ]),
      normalizedTime: _firstNonEmptyString(scopes, <String>[
        'normalized_time',
        'normalizedTime',
        'normalized_at',
        'normalizedAt',
        'scheduled_for',
        'scheduledFor',
        'target_time',
        'targetTime',
      ]),
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
      confirmationLabel: _firstNonEmptyString(scopes, <String>[
        'confirmation_prompt',
        'confirmationPrompt',
        'confirmation_message',
        'confirmationMessage',
        'confirmation_reason',
        'confirmationReason',
        'next_action',
        'nextAction',
      ]),
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
  final scopes = <Map<String, dynamic>>[root];
  for (final key in <String>[
    'planning',
    'planning_result',
    'planningResult',
    'structured_result',
    'structuredResult',
    'result',
    'payload',
    'bundle',
    'resource',
    'resource_reference',
    'resourceReference',
    'confirmation',
  ]) {
    final nested = _coerceStringMap(root[key]);
    if (nested.isNotEmpty) {
      scopes.add(nested);
    }
  }
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
    return _firstNonEmptyString(
      <Map<String, dynamic>>[map],
      <String>['summary', 'title', 'message', 'reason', 'detail', 'label'],
    );
  }
  final stringValue = _stringify(value);
  return stringValue == null || stringValue.isEmpty ? null : stringValue;
}

String? _inferResourceType(List<Map<String, dynamic>> scopes) {
  for (final scope in scopes) {
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
