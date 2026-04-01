import '../../constants/api_constants.dart';
import '../../models/tasks/task_model.dart';
import '../api/api_client.dart';

class TasksService {
  TasksService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<TaskModel>> listTasks() {
    return _apiClient.get(
      ApiConstants.tasksPath,
      parser: (dynamic data) {
        final rawItems = data is Map<String, dynamic> && data['items'] is List
            ? data['items'] as List<dynamic>
            : data is List
            ? data
            : const <dynamic>[];
        return rawItems
            .map(
              (dynamic item) => TaskModel.fromJson(
                item is Map<String, dynamic> ? item : <String, dynamic>{},
              ),
            )
            .toList();
      },
    );
  }

  Future<TaskModel> createTask(TaskModel task) {
    return _apiClient.post(
      ApiConstants.tasksPath,
      body: task.toCreateJson(),
      parser: (dynamic data) => TaskModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<TaskModel> updateTask(String taskId, Map<String, dynamic> body) {
    return _apiClient.patch(
      '${ApiConstants.tasksPath}/$taskId',
      body: body,
      parser: (dynamic data) => TaskModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<void> deleteTask(String taskId) {
    return _apiClient.delete('${ApiConstants.tasksPath}/$taskId');
  }
}
