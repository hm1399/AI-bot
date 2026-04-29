import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/experience/experience_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class PhysicalInteractionPanel extends StatelessWidget {
  const PhysicalInteractionPanel({
    required this.sceneLabel,
    required this.personaLabel,
    required this.interaction,
    required this.lastResult,
    required this.deviceConnected,
    required this.desktopBridgeReady,
    required this.onToggleShakeEnabled,
    required this.onToggleTapTriggerEnabled,
    required this.onTriggerPhysicalInteraction,
    this.pendingSettingToggleKey,
    this.pendingDebugTriggerKey,
    super.key,
  });

  final String sceneLabel;
  final String personaLabel;
  final PhysicalInteractionStateModel interaction;
  final InteractionResultModel lastResult;
  final bool deviceConnected;
  final bool desktopBridgeReady;
  final Future<void> Function()? onToggleShakeEnabled;
  final Future<void> Function()? onToggleTapTriggerEnabled;
  final Future<void> Function(String kind, Map<String, dynamic> payload)
  onTriggerPhysicalInteraction;
  final String? pendingSettingToggleKey;
  final String? pendingDebugTriggerKey;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final history = interaction.history.reversed.take(5).toList();
    final toggleControlsEnabled = pendingSettingToggleKey == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Physical Interaction',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Physical Interaction Enabled is the master switch. When it is off, hold-to-talk, tap confirmation, and shake are all unavailable. The quick controls below only change Shake Enabled and Tap Confirmation Enabled.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: interaction.enabled
                    ? 'Physical Interaction On'
                    : 'Physical Interaction Off',
                tone: interaction.enabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: interaction.readinessLabel,
                tone: interaction.ready
                    ? StatusPillTone.success
                    : interaction.enabled
                    ? StatusPillTone.warning
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: interaction.shakeEnabled
                    ? 'Shake Enabled'
                    : 'Shake Disabled',
                tone: interaction.shakeEnabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: interaction.tapConfirmationEnabled
                    ? 'Tap Confirmation On'
                    : 'Tap Confirmation Off',
                tone: interaction.tapConfirmationEnabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          Text('Quick Controls', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Shake Enabled only affects shake. Tap Confirmation Enabled only affects tap confirmation. Neither one disables top hold-to-talk.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              _SettingToggleButton(
                label: interaction.shakeEnabled
                    ? 'Disable Shake'
                    : 'Enable Shake',
                icon: interaction.shakeEnabled
                    ? Icons.motion_photos_off_outlined
                    : Icons.motion_photos_on_outlined,
                pending: pendingSettingToggleKey == 'shake',
                onPressed: toggleControlsEnabled ? onToggleShakeEnabled : null,
              ),
              _SettingToggleButton(
                label: interaction.tapConfirmationEnabled
                    ? 'Disable Tap Confirmation'
                    : 'Enable Tap Confirmation',
                icon: interaction.tapConfirmationEnabled
                    ? Icons.touch_app_outlined
                    : Icons.pan_tool_alt_outlined,
                pending: pendingSettingToggleKey == 'tap',
                onPressed: toggleControlsEnabled
                    ? onToggleTapTriggerEnabled
                    : null,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              _MetricCard(label: 'Scene', value: sceneLabel),
              _MetricCard(label: 'Persona', value: personaLabel),
              _MetricCard(
                label: 'Device',
                value: deviceConnected ? 'Online' : 'Offline',
              ),
              _MetricCard(
                label: 'Desktop Mic Path',
                value: desktopBridgeReady ? 'Ready' : 'Waiting',
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          Text(
            'Scene and persona stay manually editable in Chat. Voice or text commands like “切换到会议模式” and “切换人格为温暖陪伴” sync here after the backend applies them.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          _ReadOnlyRow(
            label: 'Hold-to-talk',
            value: !interaction.enabled
                ? 'Unavailable because Physical Interaction Enabled is off.'
                : interaction.holdToTalkAvailable
                ? 'Available. Shake Enabled does not disable top hold-to-talk.'
                : 'Not currently available because runtime guards or the desktop microphone path are blocking it.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Tap confirmation',
            value: interaction.tapConfirmationEnabled
                ? interaction.awaitingConfirmation
                      ? 'Enabled and waiting for a confirmation gesture.'
                      : 'Enabled, but only active when a confirmation context exists.'
                : 'Off. This only disables tap confirmation and does not affect top hold-to-talk.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Shake routing',
            value: interaction.shakeEnabled
                ? 'Enabled when the current scene and guard rails allow it.'
                : 'Off. Top hold-to-talk can still stay available while shake is off.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Current shake tendency',
            value: interaction.shakeMode.trim().isEmpty
                ? 'Not reported by backend yet.'
                : _humanizeValue(interaction.shakeMode),
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'First shake today',
            value: interaction.firstShakeUsedToday
                ? interaction.dailyShakeCount > 0
                      ? 'Used. ${interaction.dailyShakeCount} valid shake${interaction.dailyShakeCount == 1 ? '' : 's'} reported today.'
                      : 'Used.'
                : 'Unused.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Recent shake mode',
            value: interaction.recentShakeMode?.trim().isNotEmpty == true
                ? _recentShakeModeLabel(interaction)
                : 'Not reported by backend yet.',
          ),
          if (!interaction.ready &&
              interaction.blockedReason != null &&
              interaction.blockedReason!.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            _ReadOnlyRow(
              label: 'Blocked reason',
              value: interaction.blockedReason!,
            ),
          ],
          if (lastResult.hasContent) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _ResultCard(result: lastResult),
          ],
          const SizedBox(height: LinearSpacing.md),
          Text('Recent History', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (history.isEmpty)
            Text(
              'No physical interaction history has been reported yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            )
          else
            Column(
              children: history
                  .map(
                    (PhysicalInteractionHistoryEntryModel item) => Padding(
                      padding: const EdgeInsets.only(bottom: LinearSpacing.sm),
                      child: _HistoryRow(item: item),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: LinearSpacing.md),
          Text('Debug', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('Debug Trigger', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            'Buttons call the backend debug API. Panel state still waits for backend runtime or event updates.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              _DebugTriggerButton(
                label: 'Shake',
                pending: pendingDebugTriggerKey == 'shake',
                enabled: pendingDebugTriggerKey == null,
                onPressed: () => onTriggerPhysicalInteraction(
                  'shake',
                  const <String, dynamic>{},
                ),
              ),
              _DebugTriggerButton(
                label: 'Tap 1',
                pending: pendingDebugTriggerKey == 'tap:1',
                enabled: pendingDebugTriggerKey == null,
                onPressed: () => onTriggerPhysicalInteraction(
                  'tap',
                  const <String, dynamic>{'tap_count': 1},
                ),
              ),
              _DebugTriggerButton(
                label: 'Tap 2',
                pending: pendingDebugTriggerKey == 'tap:2',
                enabled: pendingDebugTriggerKey == null,
                onPressed: () => onTriggerPhysicalInteraction(
                  'tap',
                  const <String, dynamic>{'tap_count': 2},
                ),
              ),
              _DebugTriggerButton(
                label: 'Tap 3',
                pending: pendingDebugTriggerKey == 'tap:3',
                enabled: pendingDebugTriggerKey == null,
                onPressed: () => onTriggerPhysicalInteraction(
                  'tap',
                  const <String, dynamic>{'tap_count': 3},
                ),
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.md),
          _ReadOnlyRow(
            label: 'Status',
            value: interaction.statusMessage ?? interaction.status,
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Awaiting confirmation',
            value: interaction.awaitingConfirmation ? 'Yes' : 'No',
          ),
          if (interaction.latestInteractionAt != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            _ReadOnlyRow(
              label: 'Latest interaction',
              value: interaction.latestInteractionAt!,
            ),
          ],
        ],
      ),
    );
  }
}

class _DebugTriggerButton extends StatelessWidget {
  const _DebugTriggerButton({
    required this.label,
    required this.pending,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool pending;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: enabled
          ? () {
              unawaited(onPressed());
            }
          : null,
      child: Text(pending ? 'Sending...' : label),
    );
  }
}

class _SettingToggleButton extends StatelessWidget {
  const _SettingToggleButton({
    required this.label,
    required this.icon,
    required this.pending,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool pending;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = pending || onPressed == null
        ? null
        : () {
            unawaited(onPressed!());
          };
    return OutlinedButton.icon(
      onPressed: effectiveOnPressed,
      icon: pending
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(pending ? 'Saving...' : label),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
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
            ).textTheme.labelMedium?.copyWith(color: chrome.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final InteractionResultModel result;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            result.title.isEmpty ? 'Last Result' : result.title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            result.displayText ?? result.shortResult,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              if (result.interactionKind.isNotEmpty)
                StatusPill(
                  label: result.interactionKind,
                  tone: StatusPillTone.accent,
                ),
              if (result.mode.isNotEmpty)
                StatusPill(label: result.mode, tone: StatusPillTone.neutral),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final PhysicalInteractionHistoryEntryModel item;

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
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              Text(item.title, style: Theme.of(context).textTheme.labelLarge),
              if (item.interactionKind != null)
                StatusPill(
                  label: item.interactionKind!,
                  tone: StatusPillTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.summary,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (item.createdAt != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              item.createdAt!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
            ),
          ],
        ],
      ),
    );
  }
}

String _recentShakeModeLabel(PhysicalInteractionStateModel interaction) {
  final mode = interaction.recentShakeMode?.trim() ?? '';
  if (mode.isEmpty) {
    return 'Not reported by backend yet.';
  }
  final occurredAt = interaction.dailyShakeLastInteractionAt?.trim();
  if (occurredAt == null || occurredAt.isEmpty) {
    return _humanizeValue(mode);
  }
  return '${_humanizeValue(mode)} · $occurredAt';
}

String _humanizeValue(String value) {
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((String item) => item.isNotEmpty)
      .map(
        (String item) =>
            '${item.substring(0, 1).toUpperCase()}${item.substring(1).toLowerCase()}',
      )
      .join(' ');
}
