import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../services/api_service.dart';

final taskProvider = StateNotifierProvider<TaskNotifier, TaskState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return TaskNotifier(apiService);
});

class TaskState {
  final List<Task> tasks;
  final bool isLoading;
  final String? error;
  
  TaskState({
    required this.tasks,
    this.isLoading = false,
    this.error,
  });
  
  TaskState copyWith({
    List<Task>? tasks,
    bool? isLoading,
    String? error,
  }) {
    return TaskState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
  
  // 按优先级分组的任务
  Map<TaskPriority, List<Task>> get tasksByPriority {
    final Map<TaskPriority, List<Task>> grouped = {
      TaskPriority.high: [],
      TaskPriority.medium: [],
      TaskPriority.low: [],
    };
    
    for (var task in tasks) {
      if (!task.isCompleted) {
        grouped[task.priority]!.add(task);
      }
    }
    
    return grouped;
  }
  
  // 已完成的任务
  List<Task> get completedTasks {
    return tasks.where((task) => task.isCompleted).toList();
  }
}

class TaskNotifier extends StateNotifier<TaskState> {
  final ApiService _apiService;
  final _uuid = Uuid();
  
  TaskNotifier(this._apiService) : super(TaskState(tasks: [])) {
    loadTasks();
  }
  
  // 加载任务列表
  Future<void> loadTasks() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final tasks = await _apiService.getTasks();
      state = state.copyWith(tasks: tasks, isLoading: false);
    } catch (e) {
      print('Error loading tasks: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to load tasks');
    }
  }
  
  // 创建新任务
  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.medium,
  }) async {
    try {
      final newTask = Task(
        id: _uuid.v4(),
        title: title,
        description: description,
        dueDate: dueDate,
        priority: priority,
        isCompleted: false,
      );
      
      state = state.copyWith(isLoading: true, error: null);
      final createdTask = await _apiService.createTask(newTask);
      
      state = state.copyWith(
        tasks: [...state.tasks, createdTask],
        isLoading: false,
      );
    } catch (e) {
      print('Error creating task: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to create task');
    }
  }
  
  // 更新任务
  Future<void> updateTask(Task task) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final updatedTask = await _apiService.updateTask(task);
      
      final updatedTasks = state.tasks.map((t) => 
        t.id == task.id ? updatedTask : t
      ).toList();
      
      state = state.copyWith(
        tasks: updatedTasks,
        isLoading: false,
      );
    } catch (e) {
      print('Error updating task: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to update task');
    }
  }
  
  // 标记任务为完成/未完成
  Future<void> toggleTaskCompletion(String taskId) async {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    await updateTask(task.copyWith(isCompleted: !task.isCompleted));
  }
  
  // 删除任务
  Future<void> deleteTask(String taskId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      await _apiService.deleteTask(taskId);
      
      final updatedTasks = state.tasks.where((t) => t.id != taskId).toList();
      state = state.copyWith(
        tasks: updatedTasks,
        isLoading: false,
      );
    } catch (e) {
      print('Error deleting task: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to delete task');
    }
  }
  
  // 清除所有已完成的任务
  Future<void> clearCompletedTasks() async {
    final completedTaskIds = state.tasks
        .where((task) => task.isCompleted)
        .map((task) => task.id)
        .toList();
    
    for (final taskId in completedTaskIds) {
      await deleteTask(taskId);
    }
  }
}