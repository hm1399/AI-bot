import 'package:ai_bot_app/models/chat/message_model.dart';
import 'package:ai_bot_app/models/chat/session_model.dart';
import 'package:ai_bot_app/models/connect/bootstrap_model.dart';
import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/experience/experience_model.dart';
import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/bootstrap/bootstrap_service.dart';
import 'package:ai_bot_app/services/chat/chat_service.dart';
import 'package:ai_bot_app/services/connect/connect_service.dart';
import 'package:ai_bot_app/services/control/computer_control_service.dart';
import 'package:ai_bot_app/services/experience/experience_service.dart';
import 'package:ai_bot_app/services/home/runtime_service.dart';
import 'package:ai_bot_app/services/realtime/ws_reconnect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_service.dart';
import 'package:ai_bot_app/services/storage/auth_storage_service.dart';
import 'package:ai_bot_app/services/storage/theme_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  ProviderContainer buildContainer({
    required _FakeExperienceService experience,
    required _FakeRuntimeService runtime,
  }) {
    final bootstrap = BootstrapModel(
      serverVersion: 'test',
      capabilities: CapabilitiesModel.empty(),
      runtime: RuntimeStateModel.empty(),
      sessions: const <SessionModel>[
        SessionModel(
          sessionId: 'app:test',
          channel: 'app',
          title: 'Test Session',
          summary: '',
          lastMessageAt: null,
          messageCount: 0,
          pinned: false,
          archived: false,
          active: true,
        ),
      ],
      eventStream: const EventStreamModel(
        type: 'websocket',
        path: '/ws/app/v1/events',
        resume: EventResumeModel(
          query: 'last_event_id',
          replayLimit: 20,
          latestEventId: 'evt_latest',
        ),
      ),
    );

    return ProviderContainer(
      overrides: <Override>[
        storageServiceProvider.overrideWithValue(_FakeAuthStorageService()),
        themePreferenceServiceProvider.overrideWithValue(
          _FakeThemePreferenceService(),
        ),
        connectServiceProvider.overrideWithValue(_FakeConnectService()),
        bootstrapServiceProvider.overrideWithValue(
          _FakeBootstrapService(bootstrap),
        ),
        chatServiceProvider.overrideWithValue(_FakeChatService()),
        wsReconnectServiceProvider.overrideWithValue(_FakeWsReconnectService()),
        computerControlServiceProvider.overrideWithValue(
          _FakeComputerControlService(),
        ),
        experienceServiceProvider.overrideWithValue(experience),
        runtimeServiceProvider.overrideWithValue(runtime),
      ],
    );
  }

  test(
    'triggerPhysicalInteraction uses experience service but keeps runtime backend-sourced',
    () async {
      final experience = _FakeExperienceService(
        result: const InteractionResultModel(
          interactionKind: 'shake',
          mode: 'fortune',
          title: '今日提示',
          shortResult: 'fortune_ready',
          displayText: '今日提示：稳住节奏，先把当前主线做实。',
        ),
      );
      final runtime = _FakeRuntimeService(state: RuntimeStateModel.empty());
      final container = buildContainer(
        experience: experience,
        runtime: runtime,
      );
      addTearDown(container.dispose);

      final controller = container.read(appControllerProvider.notifier);
      await controller.connect(
        host: 'demo.local',
        port: 8000,
        secure: false,
        token: 'token',
      );

      await controller.triggerPhysicalInteraction(kind: 'shake');

      final state = container.read(appControllerProvider);
      expect(experience.calls, hasLength(1));
      expect(experience.calls.single.kind, 'shake');
      expect(experience.calls.single.payload, <String, dynamic>{
        'app_session_id': 'app:test',
        'source': 'control_center_debug',
      });
      expect(runtime.fetchCount, 1);
      expect(
        state.runtimeState.experience.lastInteractionResult.hasContent,
        isFalse,
      );
      expect(state.physicalInteractionDebugPendingKey, isNull);
    },
  );
}

class _TriggerCall {
  const _TriggerCall({required this.kind, required this.payload});

  final String kind;
  final Map<String, dynamic> payload;
}

class _FakeExperienceService extends ExperienceService {
  _FakeExperienceService({required this.result}) : super(ApiClient());

  final InteractionResultModel result;
  final List<_TriggerCall> calls = <_TriggerCall>[];

  @override
  Future<InteractionResultModel> triggerPhysicalInteraction({
    required String kind,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    calls.add(
      _TriggerCall(kind: kind, payload: Map<String, dynamic>.from(payload)),
    );
    return result;
  }
}

class _FakeRuntimeService extends RuntimeService {
  _FakeRuntimeService({required this.state}) : super(ApiClient());

  final RuntimeStateModel state;
  int fetchCount = 0;

  @override
  Future<RuntimeStateModel> fetchRuntimeState() async {
    fetchCount += 1;
    return state;
  }
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

  @override
  Future<Map<String, dynamic>> checkHealth(
    String host,
    int port,
    String token,
    bool secure,
  ) async {
    return <String, dynamic>{'ok': true};
  }
}

class _FakeBootstrapService extends BootstrapService {
  _FakeBootstrapService(this.bootstrap) : super(ApiClient());

  final BootstrapModel bootstrap;

  @override
  Future<BootstrapModel> fetchBootstrap() async => bootstrap;
}

class _FakeChatService extends ChatService {
  _FakeChatService() : super(ApiClient());

  @override
  Future<SessionModel> setActiveSession(String sessionId) async {
    return SessionModel(
      sessionId: sessionId,
      channel: 'app',
      title: 'Test Session',
      summary: '',
      lastMessageAt: null,
      messageCount: 0,
      pinned: false,
      archived: false,
      active: true,
    );
  }

  @override
  Future<MessagePageModel> getMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    return const MessagePageModel(
      items: <MessageModel>[],
      hasMoreBefore: false,
      hasMoreAfter: false,
    );
  }
}

class _FakeWsReconnectService extends WsReconnectService {
  _FakeWsReconnectService() : super(WebSocketService());

  @override
  Future<void> connect({
    required ConnectionConfigModel connection,
    required String path,
    required int replayLimit,
  }) async {}

  @override
  void disconnect() {}
}

class _FakeComputerControlService extends ComputerControlService {
  _FakeComputerControlService() : super(ApiClient());
}
