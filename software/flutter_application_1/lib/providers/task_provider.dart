import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/task.dart';

class TaskState {
  final List<Task> tasks;
  TaskState({required this.tasks});

  TaskState copyWith({List<Task>? tasks}) {
    return TaskState(tasks: tasks ?? this.tasks);
  }

  void where(Function(Task) param0) {}
}

class TaskNotifier extends StateNotifier<TaskState> {
  TaskNotifier() : super(TaskState(tasks: []));

  void setTasks(List<Task> newTasks) {
    state = state.copyWith(tasks: newTasks);
  }

  void addTask(Task task) {
    state = state.copyWith(tasks: [...state.tasks, task]);
  }

  void updateTask(Task updatedTask) {
    final index = state.tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      final newList = List<Task>.from(state.tasks);
      newList[index] = updatedTask;
      state = state.copyWith(tasks: newList);
    }
  }

  void removeTask(String id) {
    state = state.copyWith(tasks: state.tasks.where((t) => t.id != id).toList());
  }

  void handleWsMessage(Map<String, dynamic> message) {
    if (message['type'] == 'task_update') {
      // 假设服务端推送任务列表或单个任务更新
      // 这里简单处理：如果收到任务列表则替换
      final tasksData = message['data'] as List;
      final tasks = tasksData.map((e) => Task.fromJson(e)).toList();
      setTasks(tasks);
    } else if (message['type'] == 'task_created') {
      addTask(Task.fromJson(message['data']));
    }
  }

  void toggleTask(id) {}
}

final taskProvider = StateNotifierProvider<TaskNotifier, TaskState>((ref) {
  return TaskNotifier();
});

final taskWsHandlerProvider = Provider<Function>((ref) {
  return (Map<String, dynamic> message) {
    ref.read(taskProvider.notifier).handleWsMessage(message);
  };
});