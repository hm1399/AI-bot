enum TaskPriority { low, medium, high }

class Task {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final TaskPriority priority;
  final DateTime createdAt;
  final DateTime? dueDate;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.isCompleted,
    required this.priority,
    required this.createdAt,
    this.dueDate,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isCompleted: json['isCompleted'] as bool,
      priority: TaskPriority.values.byName(json['priority'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
    );
  }
}