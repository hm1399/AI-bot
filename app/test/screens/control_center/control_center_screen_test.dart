import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/models/settings/settings_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/providers/app_state.dart';
import 'package:ai_bot_app/screens/control_center/control_center_screen.dart';
import 'package:ai_bot_app/services/api/api_client.dart';
import 'package:ai_bot_app/services/connect/connect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_reconnect_service.dart';
import 'package:ai_bot_app/services/realtime/ws_service.dart';
import 'package:ai_bot_app/services/storage/auth_storage_service.dart';
import 'package:ai_bot_app/services/storage/theme_preference_service.dart';
import 'package:ai_bot_app/theme/linear_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('control center shows speech trigger toggles near the top', (
    WidgetTester tester,
  ) async {
    final state = AppState.initial().copyWith(
      connection: ConnectionConfigModel.empty().copyWith(
        currentSessionId: 'app:main',
      ),
      settingsStatus: FeatureStatus.ready,
      settings: AppSettingsModel.fromJson(<String, dynamic>{
        'physical_interaction_enabled': true,
        'shake_enabled': true,
        'tap_confirmation_enabled': false,
      }),
      runtimeState: RuntimeStateModel.fromJson(<String, dynamic>{
        'device': <String, dynamic>{
          'connected': true,
          'state': 'IDLE',
          'controls': <String, dynamic>{
            'volume': 70,
            'muted': false,
            'sleeping': false,
            'led_enabled': true,
            'led_brightness': 50,
            'led_color': '#2563eb',
          },
          'last_command': <String, dynamic>{'status': 'idle'},
        },
        'voice': <String, dynamic>{
          'desktop_bridge': <String, dynamic>{'ready': true, 'status': 'idle'},
        },
        'experience': <String, dynamic>{
          'active_scene_mode': 'focus',
          'active_persona': <String, dynamic>{
            'preset': 'balanced',
            'label': 'Balanced',
            'tone_style': 'clear',
            'reply_length': 'medium',
            'proactivity': 'balanced',
            'voice_style': 'calm',
          },
          'override_source': 'global_default',
          'physical_interaction': <String, dynamic>{
            'enabled': true,
            'ready': true,
            'status': 'ready',
            'shake_enabled': true,
            'tap_confirmation_enabled': false,
            'hold_enabled': true,
          },
          'last_interaction_result': <String, dynamic>{
            'interaction_kind': '',
            'mode': '',
            'title': '',
            'short_result': '',
          },
        },
      }),
    );

    await tester.pumpWidget(_buildTestApp(state));
    await tester.pumpAndSettle();

    expect(find.text('Speech Triggers'), findsOneWidget);
    expect(find.text('Turn Shake Off'), findsAtLeastNWidgets(1));
    expect(find.text('Turn Tap On'), findsAtLeastNWidgets(1));
    expect(tester.getTopLeft(find.text('Speech Triggers')).dy, lessThan(260));
  });
}

Widget _buildTestApp(AppState state) {
  final ws = _FakeWebSocketService();
  return ProviderScope(
    overrides: <Override>[
      storageServiceProvider.overrideWithValue(_FakeAuthStorageService()),
      themePreferenceServiceProvider.overrideWithValue(
        _FakeThemePreferenceService(),
      ),
      connectServiceProvider.overrideWithValue(_FakeConnectService()),
      wsServiceProvider.overrideWithValue(ws),
      wsReconnectServiceProvider.overrideWithValue(_FakeWsReconnectService(ws)),
      appControllerProvider.overrideWith(
        (Ref ref) => _FakeAppController(ref, state),
      ),
    ],
    child: MaterialApp(
      theme: LinearTheme.light(),
      darkTheme: LinearTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const Scaffold(body: ControlCenterScreen()),
    ),
  );
}

class _FakeAppController extends AppController {
  _FakeAppController(Ref ref, AppState initialState) : super(ref) {
    state = initialState;
  }

  @override
  Future<void> loadNotifications() async {}

  @override
  Future<void> loadReminders() async {}

  @override
  Future<void> loadSettings() async {}

  @override
  Future<void> refreshPlanningWorkbench() async {}

  @override
  Future<void> loadComputerControl({bool silent = false}) async {}

  @override
  Future<void> refreshRuntime() async {}
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

class _FakeWebSocketService extends WebSocketService {}

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
