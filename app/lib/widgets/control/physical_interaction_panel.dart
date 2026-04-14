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
    super.key,
  });

  final String sceneLabel;
  final String personaLabel;
  final PhysicalInteractionStateModel interaction;
  final InteractionResultModel lastResult;
  final bool deviceConnected;
  final bool desktopBridgeReady;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final history = interaction.history.take(5).toList();

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
            'Read-only runtime state for hold, tap confirmation, and shake routing. No synthetic success states are shown here.',
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
                label: interaction.enabled ? 'Enabled' : 'Disabled',
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
                label: interaction.shakeEnabled ? 'Shake On' : 'Shake Off',
                tone: interaction.shakeEnabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
              ),
              StatusPill(
                label: interaction.tapConfirmationEnabled
                    ? 'Tap Confirm On'
                    : 'Tap Confirm Off',
                tone: interaction.tapConfirmationEnabled
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
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
            value: interaction.holdToTalkAvailable
                ? 'Available. Voice remains device-first and uses the desktop microphone bridge.'
                : 'Not currently available.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Tap confirmation',
            value: interaction.tapConfirmationEnabled
                ? interaction.awaitingConfirmation
                      ? 'Waiting for a confirmation gesture.'
                      : 'Enabled, but only active when a confirmation context exists.'
                : 'Off for the current runtime state.',
          ),
          const SizedBox(height: LinearSpacing.sm),
          _ReadOnlyRow(
            label: 'Shake routing',
            value: interaction.shakeEnabled
                ? 'Enabled when the current scene and guard rails allow it.'
                : 'Off for the current runtime state.',
          ),
          if (interaction.blockedReason != null &&
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
