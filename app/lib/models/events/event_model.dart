class EventModel {
  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final String startAt;
  final String endAt;
  final String? location;
  final String createdAt;
  final String? updatedAt;

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['event_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      startAt:
          json['start_at']?.toString() ??
          json['start_time']?.toString() ??
          DateTime.now().toIso8601String(),
      endAt:
          json['end_at']?.toString() ??
          json['end_time']?.toString() ??
          DateTime.now().toIso8601String(),
      location: json['location']?.toString(),
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return <String, dynamic>{
      'title': title,
      'description': description,
      'start_at': startAt,
      'end_at': endAt,
      'location': location,
    };
  }
}
