import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class ChatSessionPanel extends StatelessWidget {
  const ChatSessionPanel({
    required this.sessions,
    required this.currentSessionId,
    required this.onSelect,
    required this.onCreate,
    required this.onRefresh,
    required this.onCopySessionId,
    super.key,
  });

  final List<SessionModel> sessions;
  final String currentSessionId;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String sessionId) onSelect;
  final Future<void> Function(String sessionId) onCopySessionId;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(LinearSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Conversations',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Backend-driven app sessions.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: chrome.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh conversations',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(LinearSpacing.xl),
                      child: Text(
                        'No conversations yet.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: chrome.textTertiary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(LinearSpacing.sm),
                    itemBuilder: (BuildContext context, int index) {
                      final session = sessions[index];
                      final selected = session.sessionId == currentSessionId;
                      return InkWell(
                        borderRadius: LinearRadius.control,
                        onTap: () => onSelect(session.sessionId),
                        child: Container(
                          padding: const EdgeInsets.all(LinearSpacing.sm),
                          decoration: BoxDecoration(
                            color: selected
                                ? chrome.surfaceHover
                                : Colors.transparent,
                            borderRadius: LinearRadius.control,
                            border: Border.all(
                              color: selected
                                  ? chrome.borderStrong
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      session.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: selected
                                                ? chrome.textPrimary
                                                : chrome.textSecondary,
                                          ),
                                    ),
                                  ),
                                  if (session.pinned)
                                    const StatusPill(
                                      label: 'Pinned',
                                      tone: StatusPillTone.accent,
                                      icon: Icons.push_pin_outlined,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                session.summary.isEmpty
                                    ? 'Conversation ready.'
                                    : session.summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: chrome.textTertiary),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      session.sessionId,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: chrome.textQuaternary,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        onCopySessionId(session.sessionId),
                                    child: const Text('Copy ID'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemCount: sessions.length,
                  ),
          ),
        ],
      ),
    );
  }
}
