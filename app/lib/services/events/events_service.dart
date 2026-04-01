import '../../constants/api_constants.dart';
import '../../models/events/event_model.dart';
import '../api/api_client.dart';

class EventsService {
  EventsService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<EventModel>> listEvents() {
    return _apiClient.get(
      ApiConstants.eventsPath,
      parser: (dynamic data) {
        final rawItems = data is Map<String, dynamic> && data['items'] is List
            ? data['items'] as List<dynamic>
            : data is List
            ? data
            : const <dynamic>[];
        return rawItems
            .map(
              (dynamic item) => EventModel.fromJson(
                item is Map<String, dynamic> ? item : <String, dynamic>{},
              ),
            )
            .toList();
      },
    );
  }

  Future<EventModel> createEvent(EventModel event) {
    return _apiClient.post(
      ApiConstants.eventsPath,
      body: event.toCreateJson(),
      parser: (dynamic data) => EventModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<EventModel> updateEvent(String eventId, Map<String, dynamic> body) {
    return _apiClient.patch(
      '${ApiConstants.eventsPath}/$eventId',
      body: body,
      parser: (dynamic data) => EventModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<void> deleteEvent(String eventId) {
    return _apiClient.delete('${ApiConstants.eventsPath}/$eventId');
  }
}
