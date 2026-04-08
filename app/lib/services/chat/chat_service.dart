import '../../constants/api_constants.dart';
import '../../models/chat/message_model.dart';
import '../../models/chat/session_model.dart';
import '../api/api_client.dart';

class ChatService {
  ChatService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SessionModel>> listSessions({
    int limit = 20,
    bool pinnedFirst = true,
  }) {
    return _apiClient.get(
      ApiConstants.sessionsPath,
      query: <String, String>{
        'limit': '$limit',
        'pinned_first': '$pinnedFirst',
      },
      parser: (dynamic data) {
        final raw = data is List ? data : const <dynamic>[];
        return raw
            .map(
              (dynamic item) => SessionModel.fromJson(
                item is Map<String, dynamic> ? item : <String, dynamic>{},
              ),
            )
            .toList();
      },
    );
  }

  Future<SessionModel> createSession({required String title}) {
    return _apiClient.post(
      ApiConstants.sessionsPath,
      body: <String, dynamic>{'title': title},
      parser: (dynamic data) => SessionModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<MessagePageModel> getMessages(String sessionId, {int limit = 50}) {
    return _apiClient.get(
      '${ApiConstants.sessionsPath}/$sessionId/messages',
      query: <String, String>{'limit': '$limit'},
      parser: (dynamic data) => MessagePageModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<PostMessageAcceptedModel> postMessage(
    String sessionId, {
    required String content,
    required String clientMessageId,
  }) {
    return _apiClient.post(
      '${ApiConstants.sessionsPath}/$sessionId/messages',
      body: <String, dynamic>{
        'content': content,
        'client_message_id': clientMessageId,
      },
      parser: (dynamic data) => PostMessageAcceptedModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  MessageModel normalizeMessagePayload(Map<String, dynamic> json) {
    return MessageModel.fromJson(json);
  }
}
