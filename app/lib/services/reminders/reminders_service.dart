import '../../constants/api_constants.dart';
import '../../models/reminders/reminder_model.dart';
import '../api/api_client.dart';

class RemindersService {
  RemindersService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ReminderModel>> listReminders() {
    return _apiClient.get(
      ApiConstants.remindersPath,
      parser: (dynamic data) {
        final payload = data is Map<String, dynamic>
            ? data
            : <String, dynamic>{};
        final rawItems = payload['items'] is List
            ? payload['items'] as List<dynamic>
            : data is List
            ? data
            : const <dynamic>[];
        return rawItems
            .map(
              (dynamic item) => ReminderModel.fromJson(
                item is Map<String, dynamic> ? item : <String, dynamic>{},
              ),
            )
            .toList();
      },
    );
  }
}
