import 'package:ai_bot_app/models/connect/connection_config_model.dart';
import 'package:ai_bot_app/models/planning/planning_conflict_model.dart';
import 'package:ai_bot_app/models/planning/planning_timeline_item_model.dart';
import 'package:ai_bot_app/models/reminders/reminder_model.dart';
import 'package:ai_bot_app/models/tasks/task_model.dart';
import 'package:ai_bot_app/providers/app_providers.dart';
import 'package:ai_bot_app/providers/app_state.dart';
import 'package:ai_bot_app/screens/tasks/tasks_screen.dart';
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
  testWidgets('tasks screen highlights assistant-owned AI tasks', (
    WidgetTester tester,
  ) async {
    final dueAt = DateTime.now()
        .add(const Duration(hours: 2))
        .toIso8601String();
    final state = AppState.initial().copyWith(
      tasksStatus: FeatureStatus.ready,
      tasks: <TaskModel>[
        TaskModel.fromJson(<String, dynamic>{
          'task_id': 'task_ai_followup',
          'title': 'Call the dentist',
          'description': 'Confirm the reschedule',
          'priority': 'high',
          'completed': false,
          'due_at': dueAt,
          'created_via': 'agent',
          'planning_surface': 'tasks',
          'owner_kind': 'assistant',
        }),
      ],
      planningTimelineStatus: FeatureStatus.ready,
      planningTimeline: const <PlanningTimelineItemModel>[],
      planningConflictsStatus: FeatureStatus.ready,
      planningConflicts: const <PlanningConflictModel>[],
    );

    await tester.pumpWidget(_buildTestApp(state));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Call the dentist'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('AI Task'), findsOneWidget);
    expect(find.text('Assistant-owned'), findsOneWidget);
    expect(find.text('Tasks surface'), findsOneWidget);
  });

  testWidgets(
    'tasks screen shows linked reminder schedule for reminder-backed tasks',
    (WidgetTester tester) async {
      final reminderTrigger = DateTime(2026, 4, 15, 14, 26).toIso8601String();
      final state = AppState.initial().copyWith(
        tasksStatus: FeatureStatus.ready,
        tasks: <TaskModel>[
          TaskModel.fromJson(<String, dynamic>{
            'task_id': 'task_exam_followup',
            'title': '去考试',
            'description': '提醒去考试',
            'priority': 'medium',
            'completed': false,
            'created_via': 'agent',
            'planning_surface': 'tasks',
            'owner_kind': 'assistant',
            'delivery_mode': 'device_voice_and_notification',
            'linked_reminder_id': 'rem_exam_001',
          }),
        ],
        reminders: <ReminderModel>[
          ReminderModel.fromJson(<String, dynamic>{
            'reminder_id': 'rem_exam_001',
            'title': '去考试',
            'message': '该去考试了！加油！',
            'time': reminderTrigger,
            'repeat': 'once',
            'enabled': true,
            'next_trigger_at': reminderTrigger,
            'planning_surface': 'hidden',
            'delivery_mode': 'device_voice_and_notification',
            'scheduled_action_kind': 'open_app',
            'scheduled_action_target': 'WeChat',
          }),
        ],
        planningTimelineStatus: FeatureStatus.ready,
        planningTimeline: const <PlanningTimelineItemModel>[],
        planningConflictsStatus: FeatureStatus.ready,
        planningConflicts: const <PlanningConflictModel>[],
      );

      await tester.pumpWidget(_buildTestApp(state));
      await tester.pumpAndSettle();
      final reminderLabel =
          'Reminder ${_formatTestDateTimeLabel(DateTime.parse(reminderTrigger))}';
      await tester.scrollUntilVisible(
        find.text(reminderLabel),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('去考试'), findsAtLeastNWidgets(1));
      expect(find.text(reminderLabel), findsOneWidget);
      expect(find.text('Action Open WeChat'), findsOneWidget);
    },
  );
}

String _formatTestDateTimeLabel(DateTime value) {
  const monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${monthNames[value.month - 1]} ${value.day} · $hour:$minute';
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
      home: const Scaffold(body: TasksScreen()),
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
