import 'package:flutter/material.dart';

import '../../models/notifications/notification_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class NotificationPanel extends StatelessWidget {
  const NotificationPanel({
    required this.items,
    required this.statusMessage,
    required this.onRefresh,
    required this.onMarkAllRead,
    required this.onClearAll,
    required this.onToggleRead,
    required this.onDelete,
    super.key,
  });

  final List<NotificationModel> items;
  final String? statusMessage;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onClearAll;
  final Future<void> Function(NotificationModel item) onToggleRead;
  final Future<void> Function(NotificationModel item) onDelete;

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
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: onRefresh, child: const Text('Refresh')),
              TextButton(
                onPressed: onMarkAllRead,
                child: const Text('Mark All Read'),
              ),
              OutlinedButton(
                onPressed: items.isEmpty ? null : onClearAll,
                child: const Text('Clear All'),
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
              'No notifications.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
            )
          else
            ...items.map((NotificationModel item) {
              return Container(
                margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
                padding: const EdgeInsets.all(LinearSpacing.sm),
                decoration: BoxDecoration(
                  color: item.read ? chrome.panel : chrome.surfaceHover,
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
                          label: item.priority,
                          tone: switch (item.priority) {
                            'high' => StatusPillTone.danger,
                            'medium' => StatusPillTone.warning,
                            _ => StatusPillTone.neutral,
                          },
                        ),
                      ],
                    ),
                    if (item.sourceLabel.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      _SourceMetaChip(label: item.sourceLabel),
                    ],
                    const SizedBox(height: 6),
                    Text(item.message),
                    const SizedBox(height: 6),
                    Text(
                      item.createdAt,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textQuaternary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => onToggleRead(item),
                          child: Text(item.read ? 'Mark Unread' : 'Mark Read'),
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

class _SourceMetaChip extends StatelessWidget {
  const _SourceMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.pill,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
      ),
    );
  }
}
