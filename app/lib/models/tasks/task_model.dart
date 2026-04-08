class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.completed,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final String priority;
  final bool completed;
  final String? dueAt;
  final String createdAt;
  final String? updatedAt;

  TaskModel copyWith({
    String? title,
    String? description,
    String? priority,
    bool? completed,
    String? dueAt,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['task_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      priority: json['priority']?.toString() ?? 'medium',
      completed: json['completed'] == true,
      dueAt: json['due_at']?.toString(),
      createdAt:
          json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return <String, dynamic>{
      'title': title,
      'description': description,
      'priority': priority,
      'completed': completed,
      'due_at': dueAt,
    };
  }

  Map<String, dynamic> toUpdateJson() => toCreateJson();
}
