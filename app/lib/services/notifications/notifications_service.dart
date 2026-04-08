import '../../constants/api_constants.dart';
import '../../models/notifications/notification_model.dart';
import '../api/api_client.dart';

class NotificationsService {
  NotificationsService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<NotificationModel>> listNotifications() {
    return _apiClient.get(
      ApiConstants.notificationsPath,
      parser: (dynamic data) {
        final payload = data is Map<String, dynamic>
            ? data
            : <String, dynamic>{};
        final rawItems = payload['items'] is List
            ? payload['items'] as List<dynamic>
            : const <dynamic>[];
        return rawItems
            .map(
              (dynamic item) => NotificationModel.fromJson(
                item is Map<String, dynamic> ? item : <String, dynamic>{},
              ),
            )
            .toList();
      },
    );
  }

  Future<void> markRead(String notificationId, {required bool read}) {
    return _apiClient.patch(
      '${ApiConstants.notificationsPath}/$notificationId',
      body: <String, dynamic>{'read': read},
      parser: (_) {},
    );
  }

  Future<void> markAllRead() {
    return _apiClient.post(
      ApiConstants.notificationsReadAllPath,
      parser: (_) {},
    );
  }

  Future<void> deleteNotification(String notificationId) {
    return _apiClient.delete(
      '${ApiConstants.notificationsPath}/$notificationId',
    );
  }

  Future<void> clearNotifications() {
    return _apiClient.delete(ApiConstants.notificationsPath);
  }
}
