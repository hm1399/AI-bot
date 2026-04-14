import 'package:ai_bot_app/models/experience/experience_model.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/experience/experience_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'triggerPhysicalInteraction posts to experience interactions endpoint',
    () async {
      final apiClient = _FakeApiClient()
        ..responseData = <String, dynamic>{
          'result': <String, dynamic>{
            'interaction_kind': 'tap',
            'mode': 'reject',
            'title': '拒绝执行',
            'short_result': 'rejected',
            'display_text': '已拒绝：Open Safari',
          },
        };
      final service = ExperienceService(apiClient);

      final result = await service.triggerPhysicalInteraction(
        kind: 'tap',
        payload: const <String, dynamic>{
          'tap_count': 2,
          'source': 'control_center_debug',
        },
      );

      expect(apiClient.capturedPath, '/api/app/v1/experience/interactions');
      expect(apiClient.capturedBody, <String, dynamic>{
        'kind': 'tap',
        'payload': <String, dynamic>{
          'tap_count': 2,
          'source': 'control_center_debug',
        },
      });
      expect(result, isA<InteractionResultModel>());
      expect(result.interactionKind, 'tap');
      expect(result.mode, 'reject');
      expect(result.displayText, '已拒绝：Open Safari');
    },
  );
}

class _FakeApiClient extends ApiClient {
  String? capturedPath;
  Object? capturedBody;
  dynamic responseData;

  @override
  Future<T> post<T>(
    String path, {
    required T Function(dynamic data) parser,
    Object? body,
    Map<String, String>? query,
  }) async {
    capturedPath = path;
    capturedBody = body;
    return parser(responseData);
  }
}
