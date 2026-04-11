import 'package:ai_bot_app/models/chat/message_model.dart';
import 'package:ai_bot_app/models/chat/session_model.dart';
import 'package:ai_bot_app/models/connect/bootstrap_model.dart';
import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/control/computer_action_model.dart';
import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/bootstrap/bootstrap_service.dart';
import 'package:ai_bot_app/services/chat/chat_service.dart';
import 'package:ai_bot_app/services/connect/connect_service.dart';
import 'package:ai_bot_app/services/control/computer_control_service.dart';
import 'package:ai_bot_app/services/realtime/ws_reconnect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_service.dart';
import 'package:ai_bot_app/services/storage/auth_storage_service.dart';
import 'package:ai_bot_app/services/storage/theme_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  ProviderContainer buildContainer(_FakeComputerControlService computer) {
    final bootstrap = BootstrapModel(
      serverVersion: 'test',
      capabilities: CapabilitiesModel.empty().copyWith(
        computerControl: true,
        computerActions: const <String>['open_app', 'system_info'],
      ),
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
        computerControlServiceProvider.overrideWithValue(computer),
      ],
    );
  }

  test('runComputerAction stores structured action state in bootstrap snapshot', () async {
    final computer = _FakeComputerControlService();
    final container = buildContainer(computer);
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    await controller.connect(
      host: 'demo.local',
      port: 8000,
      secure: false,
      token: 'token',
    );
    await controller.runComputerAction(
      const ComputerActionRequest(
        kind: 'open_app',
        arguments: <String, dynamic>{'app': 'Safari'},
      ),
    );

    final state = container.read(appControllerProvider);
    expect(computer.requests.single.kind, 'open_app');
    expect(
      state.bootstrap?.computerControl.recentActions.first.displaySummary,
      'Open Safari',
    );
    expect(state.bootstrap?.computerControl.pendingActions, hasLength(1));
    expect(state.globalMessage, contains('needs approval'));
  });

  test('confirmComputerAction moves pending action into completed recent state', () async {
    final computer = _FakeComputerControlService();
    final container = buildContainer(computer);
    addTearDown(container.dispose);

    final controller = container.read(appControllerProvider.notifier);
    await controller.connect(
      host: 'demo.local',
      port: 8000,
      secure: false,
      token: 'token',
    );
    await controller.runComputerAction(
      const ComputerActionRequest(
        kind: 'open_app',
        arguments: <String, dynamic>{'app': 'Safari'},
      ),
    );
    await controller.confirmComputerAction('cc_awaiting');

    final state = container.read(appControllerProvider);
    expect(computer.confirmedActionId, 'cc_awaiting');
    expect(state.bootstrap?.computerControl.pendingActions, isEmpty);
    expect(
      state.bootstrap?.computerControl.recentActions.first.isSuccessful,
      isTrue,
    );
    expect(state.globalMessage, contains('completed'));
  });
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
  Future<MessagePageModel> getMessages(String sessionId, {int limit = 50}) async {
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

  final List<ComputerActionRequest> requests = <ComputerActionRequest>[];
  String? confirmedActionId;

  @override
  Future<ComputerControlStateModel> getState({
    List<String> fallbackSupportedActions = const <String>[],
  }) async {
    return ComputerControlStateModel(
      available: true,
      supportedActions: fallbackSupportedActions,
      permissionHints: const <String>['automation'],
      pendingActions: const <ComputerActionModel>[],
      recentActions: const <ComputerActionModel>[],
    );
  }

  @override
  Future<ComputerActionModel> createAction(ComputerActionRequest request) async {
    requests.add(request);
    return ComputerActionModel(
      actionId: 'cc_awaiting',
      kind: request.kind,
      status: 'awaiting_confirmation',
      riskLevel: 'medium',
      requiresConfirmation: true,
      requestedVia: 'app',
      sourceSessionId: 'app:test',
      summary: 'Open Safari',
      arguments: request.arguments,
      result: const <String, dynamic>{},
      resultSummary: null,
      errorCode: null,
      errorMessage: null,
      createdAt: '2026-04-11T18:00:00+08:00',
      updatedAt: '2026-04-11T18:00:00+08:00',
    );
  }

  @override
  Future<ComputerActionModel> confirmAction(String actionId) async {
    confirmedActionId = actionId;
    return const ComputerActionModel(
      actionId: 'cc_awaiting',
      kind: 'open_app',
      status: 'completed',
      riskLevel: 'medium',
      requiresConfirmation: true,
      requestedVia: 'app',
      sourceSessionId: 'app:test',
      summary: 'Open Safari',
      arguments: <String, dynamic>{'app': 'Safari'},
      result: <String, dynamic>{'summary': 'Safari opened'},
      resultSummary: 'Safari opened',
      errorCode: null,
      errorMessage: null,
      createdAt: '2026-04-11T18:00:00+08:00',
      updatedAt: '2026-04-11T18:00:02+08:00',
    );
  }
}
