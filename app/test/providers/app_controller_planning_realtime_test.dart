import 'dart:async';

import 'package:ai_bot_app/models/api/app_event_model.dart';
import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/connect/connect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_reconnect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_service.dart';
import 'package:ai_bot_app/services/storage/auth_storage_service.dart';
import 'package:ai_bot_app/services/storage/theme_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'task.created realtime event keeps planning metadata semantics',
    () async {
      final ws = _FakeWebSocketService();
      final container = ProviderContainer(
        overrides: <Override>[
          storageServiceProvider.overrideWithValue(_FakeAuthStorageService()),
          themePreferenceServiceProvider.overrideWithValue(
            _FakeThemePreferenceService(),
          ),
          connectServiceProvider.overrideWithValue(_FakeConnectService()),
          wsServiceProvider.overrideWithValue(ws),
          wsReconnectServiceProvider.overrideWithValue(
            _FakeWsReconnectService(ws),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(appControllerProvider.notifier);
      await controller.connectDemo();

      ws.emitJson(<String, dynamic>{
        'event_id': 'evt_task_created',
        'event_type': 'task.created',
        'scope': 'global',
        'occurred_at': DateTime.now().toIso8601String(),
        'session_id': 'app:demo',
        'payload': <String, dynamic>{
          'task': <String, dynamic>{
            'task_id': 'task_ai_followup',
            'title': 'Call the dentist',
            'description': 'Confirm the reschedule',
            'priority': 'high',
            'completed': false,
            'due_at': DateTime.now()
                .add(const Duration(hours: 2))
                .toIso8601String(),
            'created_via': 'agent',
            'planning_surface': 'tasks',
            'owner_kind': 'assistant',
            'delivery_mode': 'none',
          },
        },
      });

      await Future<void>.delayed(Duration.zero);

      final task = container
          .read(appControllerProvider)
          .tasks
          .firstWhere((item) => item.id == 'task_ai_followup');
      expect(task.isAssistantOwned, isTrue);
      expect(task.effectivePlanningSurface, 'tasks');
      expect(task.ownerLabel, 'Assistant-owned');
      expect(task.deliveryModeLabel, isNull);
    },
  );
}

class _FakeThemePreferenceService extends ThemePreferenceService {
  @override
  Future<ThemeMode?> loadThemeMode() async => null;

  @override
  Future<void> saveThemeMode(ThemeMode themeMode) async {}
}

class _FakeAuthStorageService extends AuthStorageService {
  @override
  Future<void> saveConnection(ConnectionConfigModel connection) async {}

  @override
  Future<ConnectionConfigModel?> loadConnection() async => null;
}

class _FakeConnectService extends ConnectService {
  _FakeConnectService() : super(_FakeAuthStorageService(), ApiClient());

  @override
  Future<void> saveConnection(ConnectionConfigModel config) async {}

  @override
  Future<ConnectionConfigModel?> loadConnection() async => null;
}

class _FakeWebSocketService extends WebSocketService {
  final StreamController<AppEventModel> _events =
      StreamController<AppEventModel>.broadcast();
  final StreamController<RealtimeConnectionStatus> _status =
      StreamController<RealtimeConnectionStatus>.broadcast();

  @override
  Stream<AppEventModel> get events => _events.stream;

  @override
  Stream<RealtimeConnectionStatus> get status => _status.stream;

  void emitJson(Map<String, dynamic> payload) {
    _events.add(AppEventModel.fromJson(payload));
  }

  @override
  void disconnect() {
    _status.add(RealtimeConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _events.close();
    _status.close();
  }
}

class _FakeWsReconnectService extends WsReconnectService {
  _FakeWsReconnectService(WebSocketService ws) : super(ws);

  @override
  Future<void> connect({
    required ConnectionConfigModel connection,
    required String path,
    required int replayLimit,
  }) async {}

  @override
  void disconnect() {}
}
