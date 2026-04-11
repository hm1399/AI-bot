import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/settings/settings_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../widgets/settings/settings_form.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  AppSettingsModel? _draft;

  @override
  void initState() {
    super.initState();
    _apiKeyController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    Future<void>.microtask(
      () => ref.read(appControllerProvider.notifier).loadSettings(),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final savedSettings = state.settings;
    final settings = _draft ?? savedSettings;
    final hasDraftChanges =
        _draft != null || _apiKeyController.text.trim().isNotEmpty;
    final statusMessage =
        state.settingsMessage ?? savedSettings?.applySummary;

    if (settings == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          ThemeModeSection(
            themeMode: state.themeMode,
            onThemeModeChanged: (ThemeMode mode) =>
                ref.read(appControllerProvider.notifier).setThemeMode(mode),
          ),
          const SizedBox(height: 16),
          Center(
            child: state.settingsStatus == FeatureStatus.loading
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      state.settingsMessage ?? 'Connect to load settings.',
                    ),
                  ),
          ),
        ],
      );
    }

    return SettingsForm(
      settings: settings,
      themeMode: state.themeMode,
      apiKeyController: _apiKeyController,
      statusMessage: statusMessage,
      canEdit:
          state.settingsStatus == FeatureStatus.ready ||
          state.settingsStatus == FeatureStatus.demo,
      hasDraftChanges: hasDraftChanges,
      onChanged: (AppSettingsModel next) => setState(() => _draft = next),
      onThemeModeChanged: (ThemeMode mode) =>
          ref.read(appControllerProvider.notifier).setThemeMode(mode),
      onSave: () async {
        await ref
            .read(appControllerProvider.notifier)
            .saveSettings(
              _draft ?? settings,
              apiKey: _apiKeyController.text.trim(),
            );
        if (mounted) {
          setState(() {
            _draft = null;
            _apiKeyController.clear();
          });
        }
      },
      onReset: () => setState(() {
        _draft = null;
        _apiKeyController.clear();
      }),
      onTest: () => ref
          .read(appControllerProvider.notifier)
          .testAiConnection(
            draft: _draft ?? settings,
            apiKey: _apiKeyController.text.trim(),
          ),
    );
  }
}
