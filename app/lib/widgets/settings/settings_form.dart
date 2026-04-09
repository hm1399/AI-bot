import 'package:flutter/material.dart';

import '../../models/settings/settings_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class SettingsForm extends StatefulWidget {
  const SettingsForm({
    required this.settings,
    required this.apiKeyController,
    required this.onChanged,
    required this.onSave,
    required this.onTest,
    required this.onReset,
    required this.canEdit,
    required this.statusMessage,
    required this.hasDraftChanges,
    super.key,
  });

  final AppSettingsModel settings;
  final TextEditingController apiKeyController;
  final ValueChanged<AppSettingsModel> onChanged;
  final Future<void> Function() onSave;
  final Future<void> Function() onTest;
  final VoidCallback onReset;
  final bool canEdit;
  final String? statusMessage;
  final bool hasDraftChanges;

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  late final TextEditingController _llmProviderController;
  late final TextEditingController _llmModelController;
  late final TextEditingController _llmBaseUrlController;
  late final TextEditingController _sttLanguageController;
  late final TextEditingController _ttsVoiceController;
  late final TextEditingController _ledModeController;
  late final TextEditingController _ledColorController;
  late final TextEditingController _wakeWordController;

  @override
  void initState() {
    super.initState();
    _llmProviderController = TextEditingController();
    _llmModelController = TextEditingController();
    _llmBaseUrlController = TextEditingController();
    _sttLanguageController = TextEditingController();
    _ttsVoiceController = TextEditingController();
    _ledModeController = TextEditingController();
    _ledColorController = TextEditingController();
    _wakeWordController = TextEditingController();
    _syncControllers(widget.settings);
  }

  @override
  void didUpdateWidget(covariant SettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _syncControllers(widget.settings);
    }
  }

  void _syncControllers(AppSettingsModel settings) {
    _setText(_llmProviderController, settings.llmProvider);
    _setText(_llmModelController, settings.llmModel);
    _setText(_llmBaseUrlController, settings.llmBaseUrl ?? '');
    _setText(_sttLanguageController, settings.sttLanguage);
    _setText(_ttsVoiceController, settings.ttsVoice);
    _setText(_ledModeController, settings.ledMode);
    _setText(_ledColorController, settings.ledColor);
    _setText(_wakeWordController, settings.wakeWord);
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _llmProviderController.dispose();
    _llmModelController.dispose();
    _llmBaseUrlController.dispose();
    _sttLanguageController.dispose();
    _ttsVoiceController.dispose();
    _ledModeController.dispose();
    _ledColorController.dispose();
    _wakeWordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final chrome = context.linear;
    return ListView(
      children: <Widget>[
        Wrap(
          spacing: LinearSpacing.xs,
          runSpacing: LinearSpacing.xs,
          children: <Widget>[
            StatusPill(
              label: settings.llmApiKeyConfigured
                  ? 'API key configured'
                  : 'API key missing',
              tone: settings.llmApiKeyConfigured
                  ? StatusPillTone.success
                  : StatusPillTone.warning,
              icon: Icons.key_outlined,
            ),
            StatusPill(
              label: widget.canEdit ? 'Editable' : 'Read Only',
              tone: widget.canEdit
                  ? StatusPillTone.accent
                  : StatusPillTone.neutral,
              icon: Icons.tune_outlined,
            ),
            StatusPill(
              label: widget.hasDraftChanges ? 'Draft Changed' : 'Draft Synced',
              tone: widget.hasDraftChanges
                  ? StatusPillTone.warning
                  : StatusPillTone.success,
              icon: Icons.edit_note_outlined,
            ),
          ],
        ),
        const SizedBox(height: LinearSpacing.md),
        _Section(
          title: 'LLM',
          description: 'Backend-managed provider and connection settings.',
          child: Column(
            children: <Widget>[
              _ReadOnlyRow(
                label: 'Server',
                value: '${settings.serverUrl}:${settings.serverPort}',
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _llmProviderController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'LLM Provider'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(llmProvider: value)),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _llmModelController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'LLM Model'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(llmModel: value)),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _llmBaseUrlController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(
                  labelText: 'LLM Base URL',
                  helperText: 'Leave empty for provider default routing.',
                ),
                onChanged: (String value) => widget.onChanged(
                  settings.copyWith(
                    llmBaseUrl: value.trim().isEmpty ? null : value,
                  ),
                ),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                enabled: widget.canEdit,
                controller: widget.apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New API key for backend',
                  helperText:
                      'The frontend does not store provider SDK clients.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinearSpacing.md),
        _Section(
          title: 'Voice & Device',
          description: 'Runtime-adjacent voice and hardware preferences.',
          child: Column(
            children: <Widget>[
              _ReadOnlyRow(
                label: 'STT Stack',
                value: '${settings.sttProvider} / ${settings.sttModel}',
              ),
              const SizedBox(height: LinearSpacing.sm),
              _ReadOnlyRow(
                label: 'TTS Stack',
                value: '${settings.ttsProvider} / ${settings.ttsModel}',
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _sttLanguageController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'STT Language'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(sttLanguage: value)),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _ttsVoiceController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'TTS Voice'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(ttsVoice: value)),
              ),
              const SizedBox(height: LinearSpacing.md),
              _SliderField(
                label: 'TTS Speed',
                value: settings.ttsSpeed,
                min: 0.5,
                max: 2,
                divisions: 15,
                displayValue: settings.ttsSpeed.toStringAsFixed(2),
                onChanged: widget.canEdit
                    ? (double value) =>
                          widget.onChanged(settings.copyWith(ttsSpeed: value))
                    : null,
              ),
              const SizedBox(height: LinearSpacing.sm),
              _SliderField(
                label: 'Device Volume',
                value: settings.deviceVolume.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                displayValue: '${settings.deviceVolume}',
                onChanged: widget.canEdit
                    ? (double value) => widget.onChanged(
                        settings.copyWith(deviceVolume: value.round()),
                      )
                    : null,
              ),
              const SizedBox(height: LinearSpacing.sm),
              SwitchListTile.adaptive(
                value: settings.ledEnabled,
                onChanged: widget.canEdit
                    ? (bool value) =>
                          widget.onChanged(settings.copyWith(ledEnabled: value))
                    : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('LED Enabled'),
              ),
              _SliderField(
                label: 'LED Brightness',
                value: settings.ledBrightness.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                displayValue: '${settings.ledBrightness}',
                onChanged: widget.canEdit
                    ? (double value) => widget.onChanged(
                        settings.copyWith(ledBrightness: value.round()),
                      )
                    : null,
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _ledModeController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'LED Mode'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(ledMode: value)),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _ledColorController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'LED Color'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(ledColor: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinearSpacing.md),
        _Section(
          title: 'Runtime Flags',
          description:
              'These values are configuration-level today. They do not guarantee runtime activation.',
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(LinearSpacing.md),
                decoration: BoxDecoration(
                  color: chrome.warning.withValues(alpha: 0.08),
                  borderRadius: LinearRadius.card,
                  border: Border.all(color: chrome.borderStandard),
                ),
                child: Text(
                  'wake_word and auto_listen are configuration fields only in the current build. Saving them does not mean wake word detection or hands-free listening is already active.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
                ),
              ),
              const SizedBox(height: LinearSpacing.sm),
              TextField(
                controller: _wakeWordController,
                enabled: widget.canEdit,
                decoration: const InputDecoration(labelText: 'Wake Word'),
                onChanged: (String value) =>
                    widget.onChanged(settings.copyWith(wakeWord: value)),
              ),
              const SizedBox(height: LinearSpacing.sm),
              SwitchListTile.adaptive(
                value: settings.autoListen,
                onChanged: widget.canEdit
                    ? (bool value) =>
                          widget.onChanged(settings.copyWith(autoListen: value))
                    : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto Listen'),
                subtitle: const Text(
                  'Saved as a backend setting only. It does not confirm an always-on listening loop is running yet.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinearSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: widget.canEdit ? widget.onSave : null,
                child: const Text('Save Settings'),
              ),
            ),
            const SizedBox(width: LinearSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.canEdit ? widget.onTest : null,
                child: const Text('Test AI Connection'),
              ),
            ),
            const SizedBox(width: LinearSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.hasDraftChanges ? widget.onReset : null,
                child: const Text('Reset Draft'),
              ),
            ),
          ],
        ),
        if (widget.statusMessage != null) ...<Widget>[
          const SizedBox(height: LinearSpacing.md),
          Container(
            padding: const EdgeInsets.all(LinearSpacing.md),
            decoration: BoxDecoration(
              color: chrome.panel,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderSubtle),
            ),
            child: Text(widget.statusMessage!),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text(displayValue),
          ],
        ),
        Slider(
          value: (value.clamp(min, max) as num).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
