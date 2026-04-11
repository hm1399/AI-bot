import 'package:ai_bot_app/models/control/computer_action_model.dart';
import 'package:ai_bot_app/widgets/control/computer_action_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required ComputerControlStateModel state,
    Future<void> Function()? onRefresh,
    Future<void> Function(ComputerActionRequest request)? onRunAction,
    Future<void> Function(String actionId)? onConfirmAction,
    Future<void> Function(String actionId)? onCancelAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              ComputerActionPanel(
                state: state,
                onRefresh: onRefresh ?? () async {},
                onRunAction: onRunAction ?? (_) async {},
                onConfirmAction: onConfirmAction ?? (_) async {},
                onCancelAction: onCancelAction ?? (_) async {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('renders pending approvals and recent actions', (
    WidgetTester tester,
  ) async {
    final state = ComputerControlStateModel(
      available: true,
      supportedActions: const <String>[
        'open_app',
        'open_url',
        'system_info',
      ],
      permissionHints: const <String>['automation', 'screen_recording'],
      pendingActions: const <ComputerActionModel>[
        ComputerActionModel(
          actionId: 'cc_1',
          kind: 'open_app',
          status: 'awaiting_confirmation',
          riskLevel: 'medium',
          requiresConfirmation: true,
          requestedVia: 'app',
          sourceSessionId: 'app:test',
          summary: 'Open Safari',
          arguments: <String, dynamic>{'app': 'Safari'},
          result: <String, dynamic>{},
          resultSummary: null,
          errorCode: null,
          errorMessage: null,
          createdAt: '2026-04-11T18:00:00+08:00',
          updatedAt: '2026-04-11T18:00:00+08:00',
        ),
      ],
      recentActions: const <ComputerActionModel>[
        ComputerActionModel(
          actionId: 'cc_2',
          kind: 'system_info',
          status: 'completed',
          riskLevel: 'low',
          requiresConfirmation: false,
          requestedVia: 'app',
          sourceSessionId: 'app:test',
          summary: 'Fetch system info',
          arguments: <String, dynamic>{},
          result: <String, dynamic>{'summary': 'macOS ready'},
          resultSummary: 'macOS ready',
          errorCode: null,
          errorMessage: null,
          createdAt: '2026-04-11T18:01:00+08:00',
          updatedAt: '2026-04-11T18:01:05+08:00',
        ),
      ],
    );

    await pumpPanel(tester, state: state);

    expect(find.text('Computer Actions'), findsOneWidget);
    expect(find.text('Pending Approvals'), findsOneWidget);
    expect(find.text('Recent Actions'), findsOneWidget);
    expect(find.text('Open Safari'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('macOS ready'), findsOneWidget);
    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Screen Recording'), findsOneWidget);
  });

  testWidgets('submits structured quick action requests', (
    WidgetTester tester,
  ) async {
    ComputerActionRequest? captured;
    await pumpPanel(
      tester,
      state: const ComputerControlStateModel(
        available: true,
        supportedActions: <String>['open_app', 'system_info'],
      ),
      onRunAction: (ComputerActionRequest request) async {
        captured = request;
      },
    );

    await tester.ensureVisible(find.widgetWithText(TextField, 'Open App'));
    await tester.enterText(find.widgetWithText(TextField, 'Open App'), 'Safari');
    await tester.tap(find.widgetWithText(FilledButton, 'Open').first);
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.kind, 'open_app');
    expect(captured!.arguments, <String, dynamic>{'app': 'Safari'});
  });

  testWidgets('system info quick action requests frontmost app profile', (
    WidgetTester tester,
  ) async {
    ComputerActionRequest? captured;
    await pumpPanel(
      tester,
      state: const ComputerControlStateModel(
        available: true,
        supportedActions: <String>['system_info'],
      ),
      onRunAction: (ComputerActionRequest request) async {
        captured = request;
      },
    );

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Frontmost App Info'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Frontmost App Info'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.kind, 'system_info');
    expect(captured!.arguments, <String, dynamic>{'profile': 'frontmost_app'});
  });
}
