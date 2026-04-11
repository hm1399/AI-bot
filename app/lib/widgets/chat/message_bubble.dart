import 'package:flutter/material.dart';

import '../../models/chat/message_model.dart';
import '../../theme/linear_tokens.dart';
import 'chat_structured_summary.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final isUser = message.role == 'user';
    final bubbleColor = isUser
        ? chrome.brand.withValues(alpha: 0.14)
        : chrome.panel;
    final textColor = chrome.textPrimary;
    final borderColor = _bubbleBorderColor(chrome, isUser);
    final metadata = message.planningMetadata;
    final headerLabel = _headerLabel;
    final footerLabel = _footerLabel;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isUser ? 12 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 12),
            ),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                headerLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isUser
                      ? chrome.accent.withValues(alpha: 0.9)
                      : chrome.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (message.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    height: 1.45,
                  ),
                ),
              ],
              if (!isUser && metadata.hasVisibleContent) ...<Widget>[
                const SizedBox(height: 8),
                ChatStructuredSummary(metadata: metadata),
              ],
              if (footerLabel != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  footerLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isUser
                        ? chrome.textQuaternary
                        : chrome.textQuaternary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _headerLabel {
    final parts = <String>[
      switch (message.role) {
        'user' => 'You',
        'system' => 'System',
        _ => 'Assistant',
      },
      if (message.sourceLabel.isNotEmpty) message.sourceLabel,
    ];
    return parts.join(' · ');
  }

  String? get _footerLabel {
    final parts = <String>[];
    final createdLabel = _createdAtLabel;
    if (createdLabel != null) {
      parts.add(createdLabel);
    }
    final status = switch (message.status) {
      'pending' => 'Pending',
      'streaming' => 'Responding',
      'failed' => 'Failed',
      _ => null,
    };

    if (status != null) {
      parts.add(status);
    }
    if (message.status == 'failed' &&
        message.errorReason != null &&
        message.errorReason!.trim().isNotEmpty) {
      parts.add(message.errorReason!.trim());
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  Color _bubbleBorderColor(LinearThemeTokens chrome, bool isUser) {
    if (message.status == 'failed') {
      return chrome.danger.withValues(alpha: 0.75);
    }
    if (isUser) {
      return chrome.brand.withValues(alpha: 0.34);
    }
    return chrome.borderStandard;
  }

  String? get _createdAtLabel {
    final parsed = DateTime.tryParse(message.createdAt);
    if (parsed == null) {
      return null;
    }
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
