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
            const SizedBox(height: 6),
            Text(message.text, style: TextStyle(color: textColor)),
            const SizedBox(height: 8),
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
