import 'package:flutter/material.dart';

import '../../models/settings/settings_model.dart';

class SettingsForm extends StatelessWidget {
  const SettingsForm({
    required this.settings,
    required this.apiKeyController,
    required this.onChanged,
    required this.onSave,
    required this.onTest,
    required this.canEdit,
    required this.statusMessage,
    super.key,
  });

  final AppSettingsModel settings;
  final TextEditingController apiKeyController;
  final ValueChanged<AppSettingsModel> onChanged;
  final Future<void> Function() onSave;
  final Future<void> Function() onTest;
  final bool canEdit;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          enabled: canEdit,
          decoration: const InputDecoration(labelText: 'LLM Provider'),
          controller: TextEditingController(text: settings.llmProvider),
          onChanged: (String value) =>
              onChanged(settings.copyWith(llmProvider: value)),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: canEdit,
          decoration: const InputDecoration(labelText: 'LLM Model'),
          controller: TextEditingController(text: settings.llmModel),
          onChanged: (String value) =>
              onChanged(settings.copyWith(llmModel: value)),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: canEdit,
          controller: apiKeyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New API key for backend',
            helperText: 'The frontend does not store provider SDK clients.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: canEdit,
          decoration: const InputDecoration(labelText: 'Wake word'),
          controller: TextEditingController(text: settings.wakeWord),
          onChanged: (String value) =>
              onChanged(settings.copyWith(wakeWord: value)),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: canEdit ? onSave : null,
                child: const Text('Save Settings'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: canEdit ? onTest : null,
                child: const Text('Test AI Connection'),
              ),
            ),
          ],
        ),
        if (statusMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFF8FAFC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(statusMessage!),
            ),
          ),
        ],
      ],
    );
  }
}
