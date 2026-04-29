import 'package:ai_bot_app/models/experience/experience_model.dart';
import 'package:ai_bot_app/widgets/control/physical_interaction_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required PhysicalInteractionStateModel interaction,
    InteractionResultModel lastResult = const InteractionResultModel(
      interactionKind: '',
      mode: '',
      title: '',
      shortResult: '',
    ),
    Future<void> Function()? onToggleShakeEnabled,
    Future<void> Function()? onToggleTapTriggerEnabled,
    String? pendingSettingToggleKey,
    String? pendingDebugTriggerKey,
    Future<void> Function(String kind, Map<String, dynamic> payload)?
    onTriggerPhysicalInteraction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              PhysicalInteractionPanel(
                sceneLabel: 'Focus',
                personaLabel: 'Balanced',
                interaction: interaction,
                lastResult: lastResult,
                deviceConnected: true,
                desktopBridgeReady: true,
                onToggleShakeEnabled: onToggleShakeEnabled,
                onToggleTapTriggerEnabled: onToggleTapTriggerEnabled,
                pendingSettingToggleKey: pendingSettingToggleKey,
                pendingDebugTriggerKey: pendingDebugTriggerKey,
                onTriggerPhysicalInteraction:
                    onTriggerPhysicalInteraction ?? (_, __) async {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('renders shake tendency and daily shake read-only state', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      interaction: const PhysicalInteractionStateModel(
        enabled: true,
        shakeEnabled: true,
        tapConfirmationEnabled: true,
        holdToTalkAvailable: true,
        ready: true,
        status: 'ready',
        shakeMode: 'fortune',
        firstShakeUsedToday: true,
        recentShakeMode: 'random',
        dailyShakeDate: '2026-04-14',
        dailyShakeCount: 2,
        dailyShakeFirstResultMode: 'fortune',
        dailyShakeLastMode: 'random',
        dailyShakeLastInteractionAt: '2026-04-14T10:30:00+08:00',
      ),
    );

    expect(find.text('Debug Trigger'), findsOneWidget);
    expect(find.text('Current shake tendency'), findsOneWidget);
    expect(find.textContaining('Fortune'), findsAtLeastNWidgets(1));
    expect(find.text('First shake today'), findsOneWidget);
    expect(find.textContaining('Used'), findsAtLeastNWidgets(1));
    expect(find.text('Recent shake mode'), findsOneWidget);
    expect(find.textContaining('Random'), findsAtLeastNWidgets(1));
    expect(find.text('Disable Shake'), findsOneWidget);
    expect(find.text('Disable Tap Confirmation'), findsOneWidget);
  });

  testWidgets('quick control buttons emit setting toggle callbacks', (
    WidgetTester tester,
  ) async {
    var shakeToggled = false;
    var tapToggled = false;

    await pumpPanel(
      tester,
      interaction: const PhysicalInteractionStateModel(
        enabled: true,
        shakeEnabled: true,
        tapConfirmationEnabled: false,
        holdToTalkAvailable: true,
        ready: true,
        status: 'ready',
      ),
      onToggleShakeEnabled: () async {
        shakeToggled = true;
      },
      onToggleTapTriggerEnabled: () async {
        tapToggled = true;
      },
    );

    await tester.tap(find.text('Disable Shake'));
    await tester.pump();
    await tester.tap(find.text('Enable Tap Confirmation'));
    await tester.pump();

    expect(shakeToggled, isTrue);
    expect(tapToggled, isTrue);
  });

  testWidgets('copy keeps shake and tap scoped away from hold-to-talk', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      interaction: const PhysicalInteractionStateModel(
        enabled: true,
        shakeEnabled: false,
        tapConfirmationEnabled: false,
        holdToTalkAvailable: true,
        ready: true,
        status: 'ready',
      ),
    );

    expect(
      find.text(
        'Physical Interaction Enabled is the master switch. When it is off, hold-to-talk, tap confirmation, and shake are all unavailable. The quick controls below only change Shake Enabled and Tap Confirmation Enabled.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Shake Enabled only affects shake. Tap Confirmation Enabled only affects tap confirmation. Neither one disables top hold-to-talk.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Available. Shake Enabled does not disable top hold-to-talk.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Off. This only disables tap confirmation and does not affect top hold-to-talk.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Off. Top hold-to-talk can still stay available while shake is off.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enable Shake'), findsOneWidget);
    expect(find.text('Enable Tap Confirmation'), findsOneWidget);
  });

  testWidgets(
    'debug buttons emit backend trigger requests without local result state',
    (WidgetTester tester) async {
      final calls = <Map<String, dynamic>>[];
      await pumpPanel(
        tester,
        interaction: PhysicalInteractionStateModel.empty(
          enabled: true,
          shakeEnabled: true,
          tapConfirmationEnabled: true,
        ),
        onTriggerPhysicalInteraction:
            (String kind, Map<String, dynamic> payload) async {
              calls.add(<String, dynamic>{'kind': kind, 'payload': payload});
            },
      );

      await tester.dragUntilVisible(
        find.text('Tap 2'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap 2'));
      await tester.pump();

      expect(calls, hasLength(1));
      expect(calls.single['kind'], 'tap');
      expect(calls.single['payload'], <String, dynamic>{'tap_count': 2});
      expect(find.text('Last Result'), findsNothing);
    },
  );

  testWidgets('pending debug request disables all trigger buttons', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      interaction: PhysicalInteractionStateModel.empty(
        enabled: true,
        shakeEnabled: true,
        tapConfirmationEnabled: true,
      ),
      pendingDebugTriggerKey: 'tap:1',
    );

    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(
      buttons.where((FilledButton button) => button.onPressed != null),
      isEmpty,
    );
    expect(find.text('Sending...'), findsOneWidget);
  });

  testWidgets('pending setting toggle shows saving state and disables button', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      interaction: PhysicalInteractionStateModel.empty(
        enabled: true,
        shakeEnabled: true,
        tapConfirmationEnabled: true,
      ),
      pendingSettingToggleKey: 'shake',
      onToggleShakeEnabled: () async {},
      onToggleTapTriggerEnabled: () async {},
    );

    expect(find.text('Saving...'), findsOneWidget);
    final outlinedButtons = tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(
      outlinedButtons.where(
        (OutlinedButton button) => button.onPressed != null,
      ),
      isEmpty,
    );
  });

  testWidgets(
    'recent history shows newest items first and hides blocked row when ready',
    (WidgetTester tester) async {
      await pumpPanel(
        tester,
        interaction: const PhysicalInteractionStateModel(
          enabled: true,
          shakeEnabled: true,
          tapConfirmationEnabled: true,
          holdToTalkAvailable: true,
          ready: true,
          status: 'ready',
          blockedReason: 'no_pending_confirmation',
          history: <PhysicalInteractionHistoryEntryModel>[
            PhysicalInteractionHistoryEntryModel(
              title: 'Old 1',
              summary: 'Old 1',
            ),
            PhysicalInteractionHistoryEntryModel(
              title: 'Old 2',
              summary: 'Old 2',
            ),
            PhysicalInteractionHistoryEntryModel(
              title: 'Old 3',
              summary: 'Old 3',
            ),
            PhysicalInteractionHistoryEntryModel(
              title: 'Old 4',
              summary: 'Old 4',
            ),
            PhysicalInteractionHistoryEntryModel(
              title: 'Old 5',
              summary: 'Old 5',
            ),
            PhysicalInteractionHistoryEntryModel(
              title: 'Newest',
              summary: 'Newest',
            ),
          ],
        ),
      );

      expect(find.text('Blocked reason'), findsNothing);
      expect(find.text('Newest'), findsWidgets);
      expect(find.text('Old 1'), findsNothing);
    },
  );
}
