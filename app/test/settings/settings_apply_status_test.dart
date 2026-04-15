import 'package:ai_bot_app/models/settings/settings_model.dart';
import 'package:ai_bot_app/widgets/settings/settings_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppSettingsModel buildSettings() {
    return AppSettingsModel.fromJson(<String, dynamic>{
      'settings': <String, dynamic>{
        'server_url': 'demo.local',
        'server_port': 8000,
        'llm_provider': 'server-managed',
        'llm_model': 'demo-model',
        'llm_api_key_configured': true,
        'llm_base_url': null,
        'stt_provider': 'server-managed',
        'stt_model': 'demo-stt',
        'stt_language': 'en-US',
        'tts_provider': 'server-managed',
        'tts_model': 'demo-tts',
        'tts_voice': 'alloy',
        'tts_speed': 1.0,
        'device_volume': 70,
        'led_enabled': true,
        'led_brightness': 50,
        'led_mode': 'breathing',
        'led_color': '#2563eb',
        'wake_word': 'Hey Assistant',
        'auto_listen': true,
      },
      'apply_results': <String, dynamic>{
        'device_volume': <String, dynamic>{
          'mode': 'save_and_apply',
          'status': 'pending',
        },
        'led_color': <String, dynamic>{
          'mode': 'save_and_apply',
          'status': 'applied',
        },
        'wake_word': <String, dynamic>{
          'mode': 'config_only',
          'status': 'saved_only',
        },
      },
    });
  }

  Future<void> pumpForm(WidgetTester tester, AppSettingsModel settings) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsForm(
            settings: settings,
            connectionDiagnostics: const SettingsConnectionDiagnosticsModel(
              status: 'Connected backend',
              endpoint: 'http://demo.local:8000',
            ),
            themeMode: ThemeMode.dark,
            apiKeyController: TextEditingController(),
            onChanged: (_) {},
            onThemeModeChanged: (_) {},
            onSave: () async {},
            onTest: () async {},
            onReset: () {},
            canEdit: true,
            statusMessage: settings.applySummary,
            hasDraftChanges: false,
          ),
        ),
      ),
    );
  }

  test('parses nested settings save result and apply statuses', () {
    final settings = buildSettings();

    expect(settings.applyResults['device_volume']?.isPending, isTrue);
    expect(settings.applyResults['led_color']?.isSuccessful, isTrue);
    expect(settings.applyResults['wake_word']?.isConfigOnly, isTrue);
    expect(settings.applySummary, contains('live applied'));
    expect(settings.applySummary, contains('pending'));
    expect(settings.applySummary, contains('config only'));
  });

  test('maps backend apply reason codes into readable helper text', () {
    final settings = AppSettingsModel.fromJson(<String, dynamic>{
      'settings': <String, dynamic>{
        'server_url': 'demo.local',
        'server_port': 8000,
        'llm_provider': 'server-managed',
        'llm_model': 'demo-model',
        'llm_api_key_configured': true,
        'stt_provider': 'server-managed',
        'stt_model': 'demo-stt',
        'stt_language': 'en-US',
        'tts_provider': 'server-managed',
        'tts_model': 'demo-tts',
        'tts_voice': 'alloy',
        'tts_speed': 1.0,
        'device_volume': 70,
        'led_enabled': true,
        'led_brightness': 50,
        'led_mode': 'breathing',
        'led_color': '#2563eb',
        'wake_word': 'Hey Assistant',
        'auto_listen': true,
      },
      'apply_results': <String, dynamic>{
        'device_volume': <String, dynamic>{
          'mode': 'save_and_apply',
          'status': 'saved_only',
          'reason': 'device_offline',
        },
      },
    });

    expect(
      settings.applyResults['device_volume']?.message,
      contains('offline'),
    );
  });

  testWidgets('renders apply summary and field-level badges', (
    WidgetTester tester,
  ) async {
    final settings = buildSettings();

    await pumpForm(tester, settings);

    Future<void> dragUntilFound(Finder finder) async {
      for (
        var scrolls = 0;
        scrolls < 8 && finder.evaluate().isEmpty;
        scrolls += 1
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('Apply Results'), findsOneWidget);
    expect(find.textContaining('live applied'), findsOneWidget);
    final configOnlyHelper = find.text(
      'Saved as config only. Runtime effect is not guaranteed yet.',
    );

    await dragUntilFound(find.text('Live Apply'));
    expect(find.text('Live Apply'), findsWidgets);
    expect(find.text('Pending'), findsWidgets);

    await dragUntilFound(configOnlyHelper);
    expect(find.text('Config Only'), findsWidgets);
    expect(configOnlyHelper, findsOneWidget);
  });
}
