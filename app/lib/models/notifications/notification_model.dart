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
  });

  final String id;
  final String type;
  final String priority;
  final String title;
  final String message;
  final bool read;
  final String createdAt;
  final Map<String, dynamic> metadata;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['notification_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      priority: json['priority']?.toString() ?? 'medium',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      read: json['read'] == true,
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : <String, dynamic>{},
    );
  }
}
