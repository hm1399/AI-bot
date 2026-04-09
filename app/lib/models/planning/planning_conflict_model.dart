class PlanningConflictParticipantModel {
  const PlanningConflictParticipantModel({
    required this.kind,
    required this.id,
    required this.title,
    this.startAt,
    this.endAt,
    this.dueAt,
    this.nextTriggerAt,
    this.bundleId,
    this.metadata = const <String, dynamic>{},
  });

  final String kind;
  final String id;
  final String title;
  final String? startAt;
  final String? endAt;
  final String? dueAt;
  final String? nextTriggerAt;
  final String? bundleId;
  final Map<String, dynamic> metadata;

  factory PlanningConflictParticipantModel.fromJson(Map<String, dynamic> json) {
    final kind =
        _readStringAny(
          <Map<String, dynamic>>[json],
          const <String>['resource_type', 'kind', 'type'],
        ) ??
        _inferResourceType(json);
    return PlanningConflictParticipantModel(
      kind: kind,
      id:
          _readStringAny(
            <Map<String, dynamic>>[json],
            <String>['resource_id', '${kind}_id', 'id'],
          ) ??
          '',
      title:
          _readStringAny(
            <Map<String, dynamic>>[json],
            const <String>['title', 'summary'],
          ) ??
          '',
      startAt: _readStringAny(
        <Map<String, dynamic>>[json],
        const <String>['start_at'],
      ),
      endAt: _readStringAny(
        <Map<String, dynamic>>[json],
        const <String>['end_at'],
      ),
      dueAt: _readStringAny(
        <Map<String, dynamic>>[json],
        const <String>['due_at'],
      ),
      nextTriggerAt: _readStringAny(
        <Map<String, dynamic>>[json],
        const <String>['next_trigger_at'],
      ),
      bundleId: _readStringAny(
        <Map<String, dynamic>>[json],
        const <String>['bundle_id'],
      ),
      metadata: Map<String, dynamic>.from(json),
    );
  }
}

class PlanningConflictModel {
  const PlanningConflictModel({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    this.summary,
    this.startAt,
    this.endAt,
    this.bundleId,
    this.resourceIds = const <String>[],
    this.resourceKinds = const <String>[],
    this.participants = const <PlanningConflictParticipantModel>[],
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String type;
  final String severity;
  final String title;
  final String? summary;
  final String? startAt;
  final String? endAt;
  final String? bundleId;
  final List<String> resourceIds;
  final List<String> resourceKinds;
  final List<PlanningConflictParticipantModel> participants;
  final Map<String, dynamic> metadata;

  factory PlanningConflictModel.fromJson(Map<String, dynamic> json) {
    final source = _firstMap(<dynamic>[json['conflict'], json]);
    final participants = _readParticipants(source);
    final bundleId = _readStringAny(
      <Map<String, dynamic>>[source],
      const <String>['bundle_id'],
    );
    final resourceIds = _readStringList(
      source['resource_ids'],
      fallback: participants.map((item) => item.id),
    );
    final resourceKinds = _readStringList(
      source['resource_kinds'],
      fallback: participants.map((item) => item.kind),
    );

    return PlanningConflictModel(
      id:
          _readStringAny(
            <Map<String, dynamic>>[source],
            const <String>['conflict_id', 'id'],
          ) ??
          _buildConflictId(source, participants),
      type:
          _readStringAny(
            <Map<String, dynamic>>[source],
            const <String>['type', 'conflict_type'],
          ) ??
          'conflict',
      severity:
          _readStringAny(
            <Map<String, dynamic>>[source],
            const <String>['severity', 'level'],
          ) ??
          'medium',
      title:
          _readStringAny(
            <Map<String, dynamic>>[source],
            const <String>['title', 'summary'],
          ) ??
          'Conflict',
      summary: _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['summary', 'message'],
      ),
      startAt: _readStringAny(
        <Map<String, dynamic>>[
          source,
          if (participants.isNotEmpty) participants.first.metadata,
        ],
        const <String>['start_at', 'due_at', 'next_trigger_at'],
      ),
      endAt: _readStringAny(
        <Map<String, dynamic>>[
          source,
          if (participants.length > 1) participants.last.metadata,
        ],
        const <String>['end_at'],
      ),
      bundleId: bundleId,
      resourceIds: resourceIds,
      resourceKinds: resourceKinds,
      participants: participants,
      metadata: source,
    );
  }
}

List<PlanningConflictParticipantModel> _readParticipants(
  Map<String, dynamic> source,
) {
  final participants = <PlanningConflictParticipantModel>[];
  for (final candidate in <dynamic>[
    source['participants'],
    source['items'],
    source['resources'],
  ]) {
    if (candidate is List) {
      for (final item in candidate) {
        if (item is Map<String, dynamic>) {
          participants.add(PlanningConflictParticipantModel.fromJson(item));
        }
      }
    }
  }

  for (final key in const <String>['left', 'right']) {
    final item = source[key];
    if (item is Map<String, dynamic>) {
      participants.add(PlanningConflictParticipantModel.fromJson(item));
    }
  }

  final seen = <String>{};
  return participants.where((participant) {
    final dedupeKey = '${participant.kind}:${participant.id}';
    if (seen.contains(dedupeKey)) {
      return false;
    }
    seen.add(dedupeKey);
    return true;
  }).toList();
}

String _buildConflictId(
  Map<String, dynamic> source,
  List<PlanningConflictParticipantModel> participants,
) {
  final type =
      _readStringAny(
        <Map<String, dynamic>>[source],
        const <String>['type', 'conflict_type'],
      ) ??
      'conflict';
  if (participants.isEmpty) {
    return type;
  }
  final suffix = participants
      .map((participant) => '${participant.kind}:${participant.id}')
      .join('|');
  return '$type:$suffix';
}

String _inferResourceType(Map<String, dynamic> json) {
  if (json.containsKey('event_id')) {
    return 'event';
  }
  if (json.containsKey('reminder_id')) {
    return 'reminder';
  }
  if (json.containsKey('task_id')) {
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

List<String> _readStringList(
  dynamic value, {
  Iterable<String> fallback = const <String>[],
}) {
  if (value is List) {
    return value
        .map((dynamic item) => item.toString().trim())
        .where((String item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
  return fallback.where((String item) => item.isNotEmpty).toSet().toList();
}
