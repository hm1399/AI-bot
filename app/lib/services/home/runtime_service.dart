import '../../constants/api_constants.dart';
import '../../models/home/runtime_state_model.dart';
import '../api/api_client.dart';

class RuntimeService {
  RuntimeService(this._apiClient);

  final ApiClient _apiClient;

  Future<RuntimeStateModel> fetchRuntimeState() {
    return _apiClient.get(
      ApiConstants.runtimeStatePath,
      parser: (dynamic data) => RuntimeStateModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<Map<String, dynamic>> stopCurrentTask({String? taskId}) {
    return _apiClient.post(
      ApiConstants.runtimeStopPath,
      body: <String, dynamic>{
        if (taskId != null && taskId.trim().isNotEmpty) 'task_id': taskId,
      },
      parser: (dynamic data) =>
          data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }

  Future<TodoSummaryModel> fetchTodoSummary() {
    return _apiClient.get(
      ApiConstants.todoSummaryPath,
      parser: (dynamic data) => TodoSummaryModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<CalendarSummaryModel> fetchCalendarSummary() {
    return _apiClient.get(
      ApiConstants.calendarSummaryPath,
      parser: (dynamic data) => CalendarSummaryModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }
}
