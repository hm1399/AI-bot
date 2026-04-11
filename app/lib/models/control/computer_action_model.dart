class ComputerActionRequest {
  const ComputerActionRequest({
    required this.kind,
    this.arguments = const <String, dynamic>{},
    this.reason,
    this.requiresConfirmation,
  });

  final String kind;
  final Map<String, dynamic> arguments;
  final String? reason;
  final bool? requiresConfirmation;

  Map<String, dynamic> toJson() {
    final trimmedReason = reason?.trim();
    final cleanedArguments = _compactMap(arguments);
    return <String, dynamic>{
      'action': kind,
      'kind': kind,
      'target': cleanedArguments,
      'arguments': cleanedArguments,
      if (trimmedReason != null && trimmedReason.isNotEmpty)
        'reason': trimmedReason,
      if (requiresConfirmation != null)
        'requires_confirmation': requiresConfirmation,
    };
  }
}

class ComputerActionModel {
  const ComputerActionModel({
    required this.actionId,
    required this.kind,
    required this.status,
    required this.riskLevel,
    required this.requiresConfirmation,
    required this.requestedVia,
    required this.sourceSessionId,
    required this.summary,
    required this.arguments,
    required this.result,
    required this.resultSummary,
    required this.errorCode,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String actionId;
  final String kind;
  final String status;
  final String riskLevel;
  final bool requiresConfirmation;
  final String requestedVia;
  final String? sourceSessionId;
  final String summary;
  final Map<String, dynamic> arguments;
  final Map<String, dynamic> result;
  final String? resultSummary;
  final String? errorCode;
  final String? errorMessage;
  final String? createdAt;
  final String? updatedAt;

  bool get isPendingLike => switch (status) {
    'requested' || 'accepted' || 'queued' || 'pending' || 'running' => true,
    _ => isAwaitingConfirmation,
  };

  bool get isAwaitingConfirmation =>
      status == 'awaiting_confirmation' ||
      status == 'requires_confirmation' ||
      (requiresConfirmation && !isTerminal);

  bool get isTerminal => switch (status) {
    'completed' || 'succeeded' || 'failed' || 'cancelled' || 'rejected' => true,
    _ => false,
  };

  bool get isSuccessful => switch (status) {
    'completed' || 'succeeded' => true,
    _ => false,
  };

  bool get isFailed => switch (status) {
    'failed' || 'rejected' => true,
    _ => false,
  };

  String get displayStatusLabel => switch (status) {
    'awaiting_confirmation' || 'requires_confirmation' => 'Needs Approval',
    'completed' || 'succeeded' => 'Completed',
    'failed' => 'Failed',
    'cancelled' => 'Cancelled',
    'rejected' => 'Rejected',
    'accepted' => 'Accepted',
    'queued' => 'Queued',
    'running' => 'Running',
    'requested' || 'pending' => 'Pending',
    _ => status.replaceAll('_', ' '),
  };

  String get displaySummary =>
      summary.trim().isNotEmpty ? summary.trim() : _fallbackSummary(kind, arguments);

  String? get outputSummary {
    final resultText = resultSummary?.trim();
    if (resultText != null && resultText.isNotEmpty) {
      return resultText;
    }
    final errorText = errorMessage?.trim();
    if (errorText != null && errorText.isNotEmpty) {
      return errorText;
    }
    return null;
  }

  String? get timestamp => updatedAt ?? createdAt;

  ComputerActionModel copyWith({
    String? actionId,
    String? kind,
    String? status,
    String? riskLevel,
    bool? requiresConfirmation,
    String? requestedVia,
    Object? sourceSessionId = _sentinel,
    String? summary,
    Map<String, dynamic>? arguments,
    Map<String, dynamic>? result,
    Object? resultSummary = _sentinel,
    Object? errorCode = _sentinel,
    Object? errorMessage = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
  }) {
    return ComputerActionModel(
      actionId: actionId ?? this.actionId,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      riskLevel: riskLevel ?? this.riskLevel,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      requestedVia: requestedVia ?? this.requestedVia,
      sourceSessionId: identical(sourceSessionId, _sentinel)
          ? this.sourceSessionId
          : sourceSessionId as String?,
      summary: summary ?? this.summary,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      resultSummary: identical(resultSummary, _sentinel)
          ? this.resultSummary
          : resultSummary as String?,
      errorCode: identical(errorCode, _sentinel)
          ? this.errorCode
          : errorCode as String?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      createdAt: identical(createdAt, _sentinel)
          ? this.createdAt
          : createdAt as String?,
      updatedAt: identical(updatedAt, _sentinel)
          ? this.updatedAt
          : updatedAt as String?,
    );
  }

  factory ComputerActionModel.fromDynamic(dynamic raw) {
    return ComputerActionModel.fromJson(
      raw is Map<String, dynamic> ? raw : <String, dynamic>{},
    );
  }

  factory ComputerActionModel.fromJson(Map<String, dynamic> json) {
    final payload = _extractActionPayload(json);
    final target = _asMap(payload['target']);
    final arguments = <String, dynamic>{
      ...target,
      ..._asMap(payload['arguments']),
    };
    final result = _asMap(payload['result']);
    final error = _asMap(payload['error']);
    return ComputerActionModel(
      actionId: _readString(payload, const <String>[
        'action_id',
        'id',
      ]),
      kind: _readString(payload, const <String>[
        'kind',
        'action',
      ], fallback: 'unknown'),
      status: _readString(payload, const <String>[
        'status',
      ], fallback: 'pending'),
      riskLevel: _readString(payload, const <String>[
        'risk_level',
      ], fallback: 'unknown'),
      requiresConfirmation:
          _readBool(payload, const <String>['requires_confirmation']) ||
          _readBool(payload, const <String>['awaiting_confirmation']),
      requestedVia: _readString(payload, const <String>[
        'requested_via',
      ], fallback: 'app'),
      sourceSessionId: _readNullableString(payload, const <String>[
        'source_session_id',
        'session_id',
      ]),
      summary:
          _readNullableString(payload, const <String>[
            'summary',
            'label',
            'description',
          ]) ??
          _fallbackSummary(
            _readString(payload, const <String>[
              'kind',
              'action',
            ], fallback: 'unknown'),
            arguments,
          ),
      arguments: arguments,
      result: result,
      resultSummary:
          _readNullableString(payload, const <String>[
            'result_summary',
          ]) ??
          _readNullableString(result, const <String>[
            'summary',
            'message',
            'value',
            'text',
            'path',
            'url',
            'app',
          ]),
      errorCode: _readNullableString(error, const <String>[
        'code',
      ]),
      errorMessage:
          _readNullableString(payload, const <String>[
            'error_message',
          ]) ??
          _readNullableString(error, const <String>[
            'message',
            'detail',
            'error',
          ]) ??
          _readNullableString(payload, const <String>['error']),
      createdAt: _readNullableString(payload, const <String>[
        'created_at',
      ]),
      updatedAt: _readNullableString(payload, const <String>[
        'updated_at',
        'completed_at',
      ]),
    );
  }
}

class ComputerControlStateModel {
  const ComputerControlStateModel({
    this.available = false,
    this.supportedActions = const <String>[],
    this.permissionHints = const <String>[],
    this.pendingActions = const <ComputerActionModel>[],
    this.recentActions = const <ComputerActionModel>[],
    this.statusMessage,
  });

  final bool available;
  final List<String> supportedActions;
  final List<String> permissionHints;
  final List<ComputerActionModel> pendingActions;
  final List<ComputerActionModel> recentActions;
  final String? statusMessage;

  bool get hasStructuredActions => available || supportedActions.isNotEmpty;
  bool get hasPendingActions => pendingActions.isNotEmpty;
  bool get hasRecentActions => recentActions.isNotEmpty;

  ComputerControlStateModel copyWith({
    bool? available,
    List<String>? supportedActions,
    List<String>? permissionHints,
    List<ComputerActionModel>? pendingActions,
    List<ComputerActionModel>? recentActions,
    Object? statusMessage = _sentinel,
  }) {
    return ComputerControlStateModel(
      available: available ?? this.available,
      supportedActions: supportedActions ?? this.supportedActions,
      permissionHints: permissionHints ?? this.permissionHints,
      pendingActions: pendingActions ?? this.pendingActions,
      recentActions: recentActions ?? this.recentActions,
      statusMessage: identical(statusMessage, _sentinel)
          ? this.statusMessage
          : statusMessage as String?,
    );
  }

  ComputerControlStateModel withStatusMessage(String? message) {
    return copyWith(statusMessage: message);
  }

  ComputerControlStateModel upsertAction(ComputerActionModel action) {
    final nextPending = List<ComputerActionModel>.from(pendingActions);
    final nextRecent = List<ComputerActionModel>.from(recentActions);
    _upsertActionList(nextRecent, action);
    if (action.isTerminal) {
      nextPending.removeWhere(
        (ComputerActionModel item) => item.actionId == action.actionId,
      );
    } else {
      _upsertActionList(nextPending, action);
    }
    return copyWith(
      available: available || supportedActions.isNotEmpty || action.actionId.isNotEmpty,
      pendingActions: _sortActions(nextPending),
      recentActions: _sortActions(nextRecent),
    );
  }

  ComputerControlStateModel removeAction(String actionId) {
    if (actionId.trim().isEmpty) {
      return this;
    }
    return copyWith(
      pendingActions: pendingActions
          .where((ComputerActionModel item) => item.actionId != actionId)
          .toList(),
      recentActions: recentActions
          .where((ComputerActionModel item) => item.actionId != actionId)
          .toList(),
    );
  }

  factory ComputerControlStateModel.fromJson(
    Map<String, dynamic> json, {
    List<String> fallbackSupportedActions = const <String>[],
  }) {
    final payload = _extractControlPayload(json);
    final recent = _readActionList(payload, const <String>[
      'recent_actions',
      'recent',
      'actions',
    ]);
    final pending = _readActionList(payload, const <String>[
      'pending_actions',
      'pending',
    ]);
    final supportedActions = _readStringList(payload, const <String>[
      'supported_actions',
      'actions',
    ]);
    final nextSupportedActions =
        supportedActions.isEmpty ? fallbackSupportedActions : supportedActions;
    final nextPending = pending.isEmpty
        ? recent.where((ComputerActionModel item) => item.isPendingLike).toList()
        : pending;

    return ComputerControlStateModel(
      available:
          _readBool(payload, const <String>['available', 'enabled']) ||
          nextSupportedActions.isNotEmpty ||
          nextPending.isNotEmpty ||
          recent.isNotEmpty,
      supportedActions: nextSupportedActions,
      permissionHints: _readStringList(payload, const <String>[
        'permission_hints',
      ]),
      pendingActions: _sortActions(nextPending),
      recentActions: _sortActions(recent),
      statusMessage: _readNullableString(payload, const <String>[
        'status_message',
        'message',
        'note',
      ]) ??
          _readNullableString(
            _asMap(payload['adapter_error']),
            const <String>['message'],
          ),
    );
  }
}

const Object _sentinel = Object();

Map<String, dynamic> _compactMap(Map<String, dynamic> source) {
  final next = <String, dynamic>{};
  for (final entry in source.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    if (value is String && value.trim().isEmpty) {
      continue;
    }
    next[entry.key] = value;
  }
  return next;
}

Map<String, dynamic> _extractActionPayload(Map<String, dynamic> json) {
  if (_looksLikeAction(json)) {
    return Map<String, dynamic>.from(json);
  }
  for (final key in const <String>['action', 'data']) {
    final value = json[key];
    if (value is Map<String, dynamic> && _looksLikeAction(value)) {
      return Map<String, dynamic>.from(value);
    }
  }
  return Map<String, dynamic>.from(json);
}

Map<String, dynamic> _extractControlPayload(Map<String, dynamic> json) {
  if (_looksLikeControlState(json)) {
    return Map<String, dynamic>.from(json);
  }
  for (final key in const <String>[
    'computer_control',
    'state',
    'data',
  ]) {
    final value = json[key];
    if (value is Map<String, dynamic> && _looksLikeControlState(value)) {
      return Map<String, dynamic>.from(value);
    }
  }
  return Map<String, dynamic>.from(json);
}

bool _looksLikeAction(Map<String, dynamic> json) {
  return json.containsKey('action_id') ||
      json.containsKey('kind') ||
      json.containsKey('action') ||
      json.containsKey('requires_confirmation');
}

bool _looksLikeControlState(Map<String, dynamic> json) {
  return json.containsKey('pending_actions') ||
      json.containsKey('recent_actions') ||
      json.containsKey('permission_hints') ||
      json.containsKey('supported_actions') ||
      json.containsKey('available') ||
      json.containsKey('enabled');
}

List<ComputerActionModel> _readActionList(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value
          .map((dynamic item) => ComputerActionModel.fromDynamic(item))
          .where(
            (ComputerActionModel item) =>
                item.actionId.isNotEmpty || item.kind != 'unknown',
          )
          .toList();
    }
  }
  return const <ComputerActionModel>[];
}

List<String> _readStringList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value
          .map((dynamic item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList();
    }
  }
  return const <String>[];
}

void _upsertActionList(
  List<ComputerActionModel> items,
  ComputerActionModel action,
) {
  final index = items.indexWhere(
    (ComputerActionModel item) => item.actionId == action.actionId,
  );
  if (index == -1) {
    items.add(action);
    return;
  }
  items[index] = action;
}

List<ComputerActionModel> _sortActions(List<ComputerActionModel> actions) {
  final sorted = List<ComputerActionModel>.from(actions);
  sorted.sort((ComputerActionModel left, ComputerActionModel right) {
    final leftTimestamp = left.timestamp ?? '';
    final rightTimestamp = right.timestamp ?? '';
    return rightTimestamp.compareTo(leftTimestamp);
  });
  return sorted;
}

String _fallbackSummary(String kind, Map<String, dynamic> arguments) {
  final normalizedKind = kind.trim().isEmpty ? 'action' : kind;
  final label = switch (normalizedKind) {
    'open_app' => 'Open ${arguments['app']?.toString() ?? 'app'}',
    'open_path' => 'Open ${arguments['path']?.toString() ?? 'path'}',
    'open_url' => 'Open ${arguments['url']?.toString() ?? 'URL'}',
    'run_shortcut' =>
      'Run shortcut ${arguments['shortcut']?.toString() ?? ''}'.trim(),
    'run_script' =>
      'Run script ${(arguments['script_id'] ?? arguments['script'])?.toString() ?? ''}'
          .trim(),
    'clipboard_get' => 'Read clipboard',
    'clipboard_set' => 'Write clipboard',
    'active_window' => 'Inspect active window',
    'screenshot' => 'Capture screenshot',
    'system_info' => arguments['profile']?.toString().trim().isNotEmpty == true
        ? 'Fetch ${arguments['profile']} info'
        : 'Fetch system info',
    _ => normalizedKind.replaceAll('_', ' '),
  };
  return label.trim().isEmpty ? normalizedKind.replaceAll('_', ' ') : label;
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

String _readString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  return _readNullableString(json, keys) ?? fallback;
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
