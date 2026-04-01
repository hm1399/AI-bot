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
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : <String, dynamic>{},
      errorReason: json['reason']?.toString(),
    );
  }
}
