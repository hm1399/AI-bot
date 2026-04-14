import 'package:flutter/material.dart';

import '../../models/chat/message_model.dart';
import '../../theme/linear_tokens.dart';

class ChatStructuredSummary extends StatelessWidget {
  const ChatStructuredSummary({required this.metadata, super.key});

  final PlanningMessageMetadata metadata;

  @override
  Widget build(BuildContext context) {
    if (!metadata.hasVisibleContent) {
      return const SizedBox.shrink();
    }

    final chrome = context.linear;
    final emphasisColor = metadata.requiresUserConfirmation
        ? chrome.warning
        : metadata.conflicts.isNotEmpty
        ? chrome.danger.withValues(alpha: 0.72)
        : chrome.borderStandard;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: emphasisColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LinearSpacing.sm,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    metadata.summaryHeading,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: chrome.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (metadata.requiresUserConfirmation)
                  _SummaryPill(
                    label: 'Needs confirmation',
                    textColor: chrome.warning,
                    backgroundColor: chrome.warning.withValues(alpha: 0.12),
                  ),
              ],
            ),
            if (_hasMetadataTags) ...<Widget>[
              const SizedBox(height: LinearSpacing.xs),
              Wrap(
                spacing: LinearSpacing.xs,
                runSpacing: LinearSpacing.xs,
                children: <Widget>[
                  if (metadata.resourceLabel != null)
                    _SummaryPill(
                      label: metadata.resourceLabel!,
                      textColor: chrome.textSecondary,
                      backgroundColor: chrome.panel,
                    ),
                  if (metadata.planningSurfaceLabel != null)
                    _SummaryPill(
                      label: metadata.planningSurfaceLabel!,
                      textColor: chrome.textSecondary,
                      backgroundColor: chrome.panel,
                    ),
                  if (metadata.ownerLabel != null)
                    _SummaryPill(
                      label: metadata.ownerLabel!,
                      textColor: chrome.textSecondary,
                      backgroundColor: chrome.panel,
                    ),
                  if (metadata.deliveryModeLabel != null)
                    _SummaryPill(
                      label: metadata.deliveryModeLabel!,
                      textColor: chrome.textSecondary,
                      backgroundColor: chrome.panel,
                    ),
                  if (metadata.normalizedTime != null)
                    _SummaryPill(
                      label: metadata.normalizedTime!,
                      textColor: chrome.textSecondary,
                      backgroundColor: chrome.panel,
                    ),
                  if (metadata.conflictSummary != null)
                    _SummaryPill(
                      label: metadata.conflictSummary!,
                      textColor: metadata.conflicts.isNotEmpty
                          ? chrome.danger
                          : chrome.textSecondary,
                      backgroundColor: metadata.conflicts.isNotEmpty
                          ? chrome.danger.withValues(alpha: 0.12)
                          : chrome.panel,
                    ),
                ],
              ),
            ],
            if (metadata.confirmationSummary != null) ...<Widget>[
              const SizedBox(height: LinearSpacing.xs),
              Text(
                metadata.confirmationSummary!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: chrome.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
            if (metadata.conflicts.isNotEmpty) ...<Widget>[
              const SizedBox(height: LinearSpacing.xs),
              ...metadata.conflicts
                  .take(3)
                  .map(
                    (String conflict) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $conflict',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasMetadataTags =>
      metadata.resourceLabel != null ||
      metadata.planningSurfaceLabel != null ||
      metadata.ownerLabel != null ||
      metadata.deliveryModeLabel != null ||
      metadata.normalizedTime != null ||
      metadata.conflictSummary != null;
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.textColor,
    required this.backgroundColor,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: LinearRadius.pill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
