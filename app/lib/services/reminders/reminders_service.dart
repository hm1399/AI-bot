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

  Future<ReminderModel> createReminder(ReminderModel reminder) {
    return _apiClient.post(
      ApiConstants.remindersPath,
      body: reminder.toCreateJson(),
      parser: (dynamic data) => ReminderModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<ReminderModel> updateReminder(
    String reminderId,
    Map<String, dynamic> body,
  ) {
    return _apiClient.patch(
      '${ApiConstants.remindersPath}/$reminderId',
      body: body,
      parser: (dynamic data) => ReminderModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<void> deleteReminder(String reminderId) {
    return _apiClient.delete('${ApiConstants.remindersPath}/$reminderId');
  }
}
