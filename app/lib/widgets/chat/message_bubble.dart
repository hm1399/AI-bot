import 'package:flutter/material.dart';

import '../../models/chat/message_model.dart';
import '../../theme/linear_tokens.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final isUser = message.role == 'user';
    final bubbleColor = isUser ? chrome.brand : chrome.panel;
    final textColor = isUser ? Colors.white : chrome.textPrimary;
    final planningMetadata = message.planningMetadata;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser ? chrome.brand : chrome.borderStandard,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isUser ? 'You' : 'Assistant',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isUser ? Colors.white70 : chrome.textQuaternary,
              ),
            ),
            if (message.text.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(message.text, style: TextStyle(color: textColor)),
            ],
            if (planningMetadata.hasVisibleContent) ...<Widget>[
              const SizedBox(height: 10),
              _PlanningMetadataCard(metadata: planningMetadata, isUser: isUser),
            ],
            const SizedBox(height: 10),
            Text(
              message.status.toUpperCase(),
              style: TextStyle(
                color: isUser ? Colors.white70 : chrome.textQuaternary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanningMetadataCard extends StatelessWidget {
  const _PlanningMetadataCard({required this.metadata, required this.isUser});

  final PlanningMessageMetadata metadata;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final borderColor = metadata.requiresUserConfirmation
        ? chrome.warning
        : chrome.borderStandard;
    final backgroundColor = isUser
        ? Colors.white.withValues(alpha: 0.08)
        : chrome.surface;
    final textColor = isUser ? Colors.white : chrome.textPrimary;
    final secondaryTextColor = isUser ? Colors.white70 : chrome.textTertiary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _PlanningChip(
                label: metadata.resourceType == null
                    ? 'Structured Result'
                    : metadata.resourceType!,
                textColor: textColor,
                backgroundColor: isUser
                    ? Colors.white.withValues(alpha: 0.12)
                    : chrome.panel,
              ),
              if (metadata.bundleId?.isNotEmpty == true)
                _PlanningChip(
                  label: 'Bundle ${metadata.bundleId}',
                  textColor: textColor,
                  backgroundColor: isUser
                      ? Colors.white.withValues(alpha: 0.12)
                      : chrome.panel,
                ),
              if (metadata.requiresUserConfirmation)
                _PlanningChip(
                  label: 'User confirmation needed',
                  textColor: isUser ? Colors.white : chrome.warning,
                  backgroundColor: isUser
                      ? Colors.white.withValues(alpha: 0.12)
                      : chrome.warning.withValues(alpha: 0.12),
                ),
            ],
          ),
          if (metadata.resourceIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _StructuredRow(
              label: 'Resource IDs',
              value: metadata.resourceIds.join(', '),
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
          ],
          if (metadata.normalizedTime?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 8),
            _StructuredRow(
              label: 'Normalized time',
              value: metadata.normalizedTime!,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
          ],
          if (metadata.confirmationLabel?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 8),
            _StructuredRow(
              label: 'Next step',
              value: metadata.confirmationLabel!,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
          ],
          if (metadata.conflicts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Conflicts',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: secondaryTextColor),
            ),
            const SizedBox(height: 6),
            ...metadata.conflicts.map(
              (String conflict) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $conflict',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: textColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StructuredRow extends StatelessWidget {
  const _StructuredRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.secondaryTextColor,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color secondaryTextColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: secondaryTextColor),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: textColor),
        ),
      ],
    );
  }
}

class _PlanningChip extends StatelessWidget {
  const _PlanningChip({
    required this.label,
    required this.textColor,
    required this.backgroundColor,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: LinearRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}
