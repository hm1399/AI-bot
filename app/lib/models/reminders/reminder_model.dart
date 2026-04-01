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
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final String repeat;
  final bool enabled;
  final String createdAt;
  final String updatedAt;

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['reminder_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      repeat: json['repeat']?.toString() ?? 'daily',
      enabled: json['enabled'] == true,
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt:
          json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}
