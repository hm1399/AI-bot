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
        'tts_voice': 'en-US-AriaNeural',
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
        'tts_voice': 'en-US-AriaNeural',
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

  test('normalizes physical interaction apply results to runtime applied', () {
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
        'tts_voice': 'en-US-AriaNeural',
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
        'physical_interaction_enabled': <String, dynamic>{
          'mode': 'config_only',
          'status': 'saved_only',
          'reason': 'config_saved_but_not_runtime_applied',
        },
        'shake_enabled': <String, dynamic>{
          'mode': 'config_only',
          'status': 'saved_only',
        },
        'tap_confirmation_enabled': <String, dynamic>{
          'mode': 'config_only',
          'status': 'saved_only',
        },
      },
    });

    final masterResult = settings.applyResults['physical_interaction_enabled'];
    final shakeResult = settings.applyResults['shake_enabled'];
    final tapResult = settings.applyResults['tap_confirmation_enabled'];

    expect(masterResult?.isRuntimeApplied, isTrue);
    expect(masterResult?.isConfigOnly, isFalse);
    expect(masterResult?.modeLabel, 'Runtime Applied');
    expect(masterResult?.statusLabel, 'Applied');
    expect(
      masterResult?.message,
      contains('mirrored into the current runtime state'),
    );
    expect(shakeResult?.modeLabel, 'Runtime Applied');
    expect(tapResult?.statusLabel, 'Applied');
    expect(settings.applySummary, isNot(contains('config only')));
  });

  test('defaults physical interaction fields to runtime applied mode', () {
    final shakeResult = SettingApplyResultModel.defaultForField(
      'shake_enabled',
    );
    final tapResult = SettingApplyResultModel.defaultForField(
      'tap_confirmation_enabled',
    );

    expect(shakeResult?.modeLabel, 'Runtime Applied');
    expect(shakeResult?.statusLabel, 'Idle');
    expect(shakeResult?.isRuntimeApplied, isTrue);
    expect(tapResult?.modeLabel, 'Runtime Applied');
  });

  test('falls back to english tts voice when backend payload omits it', () {
    final settings = AppSettingsModel.fromJson(<String, dynamic>{
      'settings': <String, dynamic>{
        'llm_provider': 'server-managed',
        'llm_model': 'demo-model',
        'llm_api_key_configured': true,
        'stt_provider': 'server-managed',
        'stt_model': 'demo-stt',
        'stt_language': 'en-US',
        'tts_provider': 'server-managed',
        'tts_model': 'demo-tts',
        'tts_speed': 1.0,
        'device_volume': 70,
        'led_enabled': true,
        'led_brightness': 50,
        'wake_word': 'Hey Assistant',
        'auto_listen': true,
      },
    });

    expect(settings.ttsVoice, 'en-US-AriaNeural');
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
    expect(configOnlyHelper, findsWidgets);
  });

  testWidgets('explains master, shake, and tap confirmation switches', (
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
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
    }

    await dragUntilFound(find.text('Physical Interaction Enabled'));

    expect(find.text('Physical Interaction Enabled'), findsOneWidget);
    expect(
      find.text(
        'Master switch for runtime physical interaction. Turning this off disables top hold-to-talk, tap confirmation, and shake.',
      ),
      findsOneWidget,
    );
    expect(find.text('Shake Enabled'), findsOneWidget);
    expect(
      find.text(
        'Only controls shake gestures. Turning this off does not disable top hold-to-talk listening.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tap Confirmation Enabled'), findsOneWidget);
    expect(
      find.text(
        'Only controls tap confirmation. It does not affect top hold-to-talk or shake routing.',
      ),
      findsOneWidget,
    );
  });
}
