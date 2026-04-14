import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/events/event_model.dart';
import 'package:ai_bot_app/models/planning/planning_conflict_model.dart';
import 'package:ai_bot_app/models/planning/planning_timeline_item_model.dart';
import 'package:ai_bot_app/models/reminders/reminder_model.dart';
import 'package:ai_bot_app/models/tasks/task_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/providers/app_state.dart';
import 'package:ai_bot_app/screens/agenda/agenda_screen.dart';
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
  testWidgets('agenda screen keeps tasks-surface items out of agenda lane', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final eventStart = DateTime(day.year, day.month, day.day, 15);
    final eventEnd = DateTime(day.year, day.month, day.day, 16);
    final hiddenReminderTime = DateTime(day.year, day.month, day.day, 17);

    final state = AppState.initial().copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: <TaskModel>[
        TaskModel.fromJson(<String, dynamic>{
          'task_id': 'task_ai_followup',
          'title': 'Call the dentist',
          'description': 'Confirm the reschedule',
          'priority': 'high',
          'completed': false,
          'due_at': hiddenReminderTime.toIso8601String(),
          'created_via': 'agent',
          'planning_surface': 'tasks',
          'owner_kind': 'assistant',
        }),
      ],
      eventsStatus: FeatureStatus.ready,
      events: <EventModel>[
        EventModel.fromJson(<String, dynamic>{
          'event_id': 'event_dentist',
          'title': 'Dentist visit',
          'start_at': eventStart.toIso8601String(),
          'end_at': eventEnd.toIso8601String(),
          'planning_surface': 'agenda',
          'owner_kind': 'user',
        }),
      ],
      remindersStatus: FeatureStatus.ready,
      reminders: <ReminderModel>[
        ReminderModel.fromJson(<String, dynamic>{
          'reminder_id': 'rem_hidden',
          'title': 'Travel reminder',
          'time': hiddenReminderTime.toIso8601String(),
          'repeat': 'once',
          'enabled': true,
          'planning_surface': 'hidden',
          'owner_kind': 'assistant',
          'delivery_mode': 'device_voice_and_notification',
          'next_trigger_at': hiddenReminderTime.toIso8601String(),
          'status': 'scheduled',
        }),
      ],
      planningTimelineStatus: FeatureStatus.ready,
      planningTimeline: const <PlanningTimelineItemModel>[],
      planningTimelineMessage: null,
      planningConflictsStatus: FeatureStatus.ready,
      planningConflicts: const <PlanningConflictModel>[],
    );

    await tester.pumpWidget(_buildTestApp(state));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dentist visit'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Dentist visit'), findsWidgets);
    expect(find.text('Call the dentist'), findsNothing);
    expect(find.text('Hidden Delivery'), findsOneWidget);
    expect(find.textContaining('hidden delivery reminders'), findsOneWidget);
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
      home: const Scaffold(body: AgendaScreen()),
    ),
  );
}

class _FakeAppController extends AppController {
  _FakeAppController(Ref ref, AppState initialState) : super(ref) {
    state = initialState;
  }

  @override
  Future<void> loadTasks() async {}

  @override
  Future<void> loadEvents() async {}

  @override
  Future<void> loadReminders() async {}

  @override
  Future<void> refreshPlanningWorkbench() async {}
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
