class VoiceActivityModel {
  const VoiceActivityModel({
    required this.state,
    this.lastTranscript,
    this.lastResponse,
    this.lastError,
    this.lastUpdatedAt,
    this.sessionId,
    this.taskId,
  });

  final String state;
  final String? lastTranscript;
  final String? lastResponse;
  final String? lastError;
  final String? lastUpdatedAt;
  final String? sessionId;
  final String? taskId;

  bool get hasTranscript => _hasValue(lastTranscript);
  bool get hasResponse => _hasValue(lastResponse);
  bool get hasError => _hasValue(lastError);
  bool get hasIdentifiers => _hasValue(sessionId) || _hasValue(taskId);
  bool get hasContent => hasTranscript || hasResponse || hasError;

  bool get isActive => switch (state) {
    'capturing' ||
    'listening' ||
    'transcribing' ||
    'thinking' ||
    'responding' ||
    'speaking' => true,
    _ => false,
  };

  bool get shouldRenderStrip => hasContent || hasIdentifiers || isActive;

  String get displayStateLabel => switch (state) {
    'capturing' || 'listening' => 'Listening',
    'transcribing' => 'Transcribing',
    'thinking' => 'Thinking',
    'responding' => 'Responding',
    'speaking' => 'Speaking',
    'completed' => 'Completed',
    'error' => 'Error',
    'idle' => 'Idle',
    _ => _humanize(state),
  };

  DateTime? get updatedDateTime {
    final raw = lastUpdatedAt?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  VoiceActivityModel copyWith({
    String? state,
    Object? lastTranscript = _sentinel,
    Object? lastResponse = _sentinel,
    Object? lastError = _sentinel,
    Object? lastUpdatedAt = _sentinel,
    Object? sessionId = _sentinel,
    Object? taskId = _sentinel,
  }) {
    return VoiceActivityModel(
      state: state ?? this.state,
      lastTranscript: identical(lastTranscript, _sentinel)
          ? this.lastTranscript
          : lastTranscript as String?,
      lastResponse: identical(lastResponse, _sentinel)
          ? this.lastResponse
          : lastResponse as String?,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      lastUpdatedAt: identical(lastUpdatedAt, _sentinel)
          ? this.lastUpdatedAt
          : lastUpdatedAt as String?,
      sessionId: identical(sessionId, _sentinel)
          ? this.sessionId
          : sessionId as String?,
      taskId: identical(taskId, _sentinel) ? this.taskId : taskId as String?,
    );
  }

  factory VoiceActivityModel.fromJson(Map<String, dynamic> json) {
    return VoiceActivityModel(
      state:
          _readNullableString(json, const <String>[
            'state',
            'status',
            'stage',
          ]) ??
          'idle',
      lastTranscript: _readNullableString(json, const <String>[
        'last_transcript',
        'transcript',
      ]),
      lastResponse: _readNullableString(json, const <String>[
        'last_response',
        'response',
      ]),
      lastError: _readNullableString(json, const <String>[
        'last_error',
        'error',
      ]),
      lastUpdatedAt: _readNullableString(json, const <String>[
        'last_updated_at',
        'updated_at',
        'timestamp',
      ]),
      sessionId: _readNullableString(json, const <String>[
        'session_id',
        'source_session_id',
      ]),
      taskId: _readNullableString(json, const <String>['task_id']),
    );
  }

  factory VoiceActivityModel.empty() {
    return const VoiceActivityModel(state: 'idle');
  }
}

const Object _sentinel = Object();

bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

String? _readNullableString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _humanize(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'Idle';
  }
  return normalized
      .split('_')
      .where((String part) => part.isNotEmpty)
      .map(
        (String part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
