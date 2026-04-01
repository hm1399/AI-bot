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
    final settings = _draft ?? state.settings;

    if (settings == null) {
      return Center(
        child: state.settingsStatus == FeatureStatus.loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.settingsMessage ?? 'Connect to load settings.',
                ),
              ),
      );
    }

    return SettingsForm(
      settings: settings,
      apiKeyController: _apiKeyController,
      statusMessage: state.settingsMessage,
      canEdit:
          state.settingsStatus == FeatureStatus.ready ||
          state.settingsStatus == FeatureStatus.demo,
      onChanged: (AppSettingsModel next) => setState(() => _draft = next),
      onSave: () => ref
          .read(appControllerProvider.notifier)
          .saveSettings(
            _draft ?? settings,
            apiKey: _apiKeyController.text.trim(),
          ),
      onTest: () => ref.read(appControllerProvider.notifier).testAiConnection(),
    );
  }
}
