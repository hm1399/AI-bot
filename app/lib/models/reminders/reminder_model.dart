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
    );
  }

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

  Map<String, dynamic> toCreateJson() {
    return <String, dynamic>{
      'title': title,
      'message': message.isEmpty ? null : message,
      'time': time,
      'repeat': repeat,
      'enabled': enabled,
    };
  }

  Map<String, dynamic> toUpdateJson() => toCreateJson();
}
