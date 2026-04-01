class AppEventModel {
  AppEventModel({
    required this.eventId,
    required this.eventType,
    required this.scope,
    required this.occurredAt,
    required this.sessionId,
    required this.taskId,
    required this.payload,
  });

  final String eventId;
  final String eventType;
  final String scope;
  final String occurredAt;
  final String? sessionId;
  final String? taskId;
  final Map<String, dynamic> payload;

  factory AppEventModel.fromJson(Map<String, dynamic> json) {
    return AppEventModel(
      eventId: json['event_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      scope: json['scope']?.toString() ?? 'global',
      occurredAt:
          json['occurred_at']?.toString() ?? DateTime.now().toIso8601String(),
      sessionId: json['session_id']?.toString(),
      taskId: json['task_id']?.toString(),
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : <String, dynamic>{},
    );
  }
}
