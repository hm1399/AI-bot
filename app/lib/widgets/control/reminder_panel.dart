import 'package:flutter/material.dart';

import '../../models/reminders/reminder_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class ReminderPanel extends StatelessWidget {
  const ReminderPanel({
    required this.items,
    required this.statusMessage,
    required this.onRefresh,
    required this.onAdd,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final List<ReminderModel> items;
  final String? statusMessage;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAdd;
  final Future<void> Function(ReminderModel item, bool enabled) onToggleEnabled;
  final Future<void> Function(ReminderModel item) onEdit;
  final Future<void> Function(ReminderModel item) onDelete;

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Reminders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: onRefresh, child: const Text('Refresh')),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          if (statusMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
          const SizedBox(height: LinearSpacing.sm),
          if (items.isEmpty)
            Text(
              'No reminders.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
            )
          else
            ...items.map((ReminderModel item) {
              return Container(
                margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
                padding: const EdgeInsets.all(LinearSpacing.sm),
                decoration: BoxDecoration(
                  color: chrome.panel,
                  borderRadius: LinearRadius.control,
                  border: Border.all(color: chrome.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        StatusPill(
                          label: item.enabled ? 'Enabled' : 'Paused',
                          tone: item.enabled
                              ? StatusPillTone.success
                              : StatusPillTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.time} · ${item.repeat}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textSecondary,
                      ),
                    ),
                    if (item.message.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        item.message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Switch.adaptive(
                          value: item.enabled,
                          onChanged: (bool value) =>
                              onToggleEnabled(item, value),
                        ),
                        TextButton(
                          onPressed: () => onEdit(item),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () => onDelete(item),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
