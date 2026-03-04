class Event {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? notes;

  Event({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.notes,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      title: json['title'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      location: json['location'] as String?,
      notes: json['notes'] as String?,
    );
  }
}