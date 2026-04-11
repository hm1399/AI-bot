import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';

enum _ChatSessionAction { rename, togglePin, toggleArchive, copyId }

class ChatSessionList extends StatelessWidget {
  const ChatSessionList({
    required this.sessions,
    required this.currentSessionId,
    required this.sessionListMode,
    required this.onSessionListModeChanged,
    required this.onSelect,
    required this.onCreate,
    required this.onRefresh,
    required this.onCopySessionId,
    required this.onRename,
    required this.onSetPinned,
    required this.onSetArchived,
    this.title = 'Sessions',
    this.activeDescription = 'Backend-driven app sessions.',
    this.archivedDescription =
        'Archived conversations remain readable and restorable.',
    super.key,
  });

  final List<SessionModel> sessions;
  final String currentSessionId;
  final ChatSessionListMode sessionListMode;
  final ValueChanged<ChatSessionListMode> onSessionListModeChanged;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String sessionId) onSelect;
  final Future<void> Function(String sessionId) onCopySessionId;
  final Future<void> Function(SessionModel session) onRename;
  final Future<void> Function(SessionModel session, bool pinned) onSetPinned;
  final Future<void> Function(SessionModel session, bool archived)
  onSetArchived;
  final String title;
  final String activeDescription;
  final String archivedDescription;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final theme = Theme.of(context);
    final visibleSessions = sessions
        .where((SessionModel session) {
          return sessionListMode == ChatSessionListMode.archived
              ? session.archived
              : !session.archived;
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LinearSpacing.md,
            LinearSpacing.md,
            LinearSpacing.md,
            LinearSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      sessionListMode == ChatSessionListMode.archived
                          ? archivedDescription
                          : activeDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LinearSpacing.sm),
              IconButton(
                tooltip: 'Refresh conversations',
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await onRefresh();
                },
                icon: const Icon(Icons.refresh, size: 18),
              ),
              const SizedBox(width: LinearSpacing.xs),
              FilledButton.icon(
                onPressed: () async {
                  await onCreate();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LinearSpacing.md,
            0,
            LinearSpacing.md,
            LinearSpacing.md,
          ),
          child: SegmentedButton<ChatSessionListMode>(
            segments: const <ButtonSegment<ChatSessionListMode>>[
              ButtonSegment<ChatSessionListMode>(
                value: ChatSessionListMode.active,
                label: Text('Active'),
                icon: Icon(Icons.chat_bubble_outline, size: 16),
              ),
              ButtonSegment<ChatSessionListMode>(
                value: ChatSessionListMode.archived,
                label: Text('Archived'),
                icon: Icon(Icons.archive_outlined, size: 16),
              ),
            ],
            selected: <ChatSessionListMode>{sessionListMode},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ChatSessionListMode> selection) {
              if (selection.isNotEmpty) {
                onSessionListModeChanged(selection.first);
              }
            },
          ),
        ),
        Divider(height: 1, color: chrome.borderStandard),
        Expanded(
          child: visibleSessions.isEmpty
              ? _SessionEmptyState(mode: sessionListMode)
              : ListView.separated(
                  padding: const EdgeInsets.all(LinearSpacing.sm),
                  itemCount: visibleSessions.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: LinearSpacing.xs),
                  itemBuilder: (BuildContext context, int index) {
                    final session = visibleSessions[index];
                    return _SessionListItem(
                      session: session,
                      selected: session.sessionId == currentSessionId,
                      onSelect: onSelect,
                      onCopySessionId: onCopySessionId,
                      onRename: onRename,
                      onSetPinned: onSetPinned,
                      onSetArchived: onSetArchived,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionEmptyState extends StatelessWidget {
  const _SessionEmptyState({required this.mode});

  final ChatSessionListMode mode;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LinearSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              mode == ChatSessionListMode.archived
                  ? Icons.archive_outlined
                  : Icons.chat_bubble_outline,
              size: 28,
              color: chrome.textQuaternary,
            ),
            const SizedBox(height: LinearSpacing.sm),
            Text(
              mode == ChatSessionListMode.archived
                  ? 'No archived conversations yet.'
                  : 'No conversations yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: chrome.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LinearSpacing.xs),
            Text(
              mode == ChatSessionListMode.archived
                  ? 'Restore a session from its menu when you need the thread again.'
                  : 'Start a new conversation to open the first session.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: chrome.textQuaternary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionListItem extends StatelessWidget {
  const _SessionListItem({
    required this.session,
    required this.selected,
    required this.onSelect,
    required this.onCopySessionId,
    required this.onRename,
    required this.onSetPinned,
    required this.onSetArchived,
  });

  final SessionModel session;
  final bool selected;
  final Future<void> Function(String sessionId) onSelect;
  final Future<void> Function(String sessionId) onCopySessionId;
  final Future<void> Function(SessionModel session) onRename;
  final Future<void> Function(SessionModel session, bool pinned) onSetPinned;
  final Future<void> Function(SessionModel session, bool archived)
  onSetArchived;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final theme = Theme.of(context);
    final metadata = <String>[
      if (session.active) 'Current',
      if (session.pinned) 'Pinned',
      _formatChannelLabel(session.channel),
      '${session.messageCount} ${session.messageCount == 1 ? 'msg' : 'msgs'}',
    ];
    final timestamp = _formatSessionTimestamp(session.lastMessageAt);
    if (timestamp != null) {
      metadata.add(timestamp);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: LinearRadius.control,
        onTap: () async {
          await onSelect(session.sessionId);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(LinearSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? chrome.surfaceHover : Colors.transparent,
            borderRadius: LinearRadius.control,
            border: Border.all(
              color: selected ? chrome.borderStrong : chrome.borderStandard,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Tooltip(
                      message: session.title,
                      child: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? chrome.textPrimary
                              : chrome.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LinearSpacing.xs),
                  PopupMenuButton<_ChatSessionAction>(
                    tooltip: 'Conversation actions',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    splashRadius: 18,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onSelected: (_ChatSessionAction action) async {
                      switch (action) {
                        case _ChatSessionAction.rename:
                          await onRename(session);
                          return;
                        case _ChatSessionAction.togglePin:
                          await onSetPinned(session, !session.pinned);
                          return;
                        case _ChatSessionAction.toggleArchive:
                          await onSetArchived(session, !session.archived);
                          return;
                        case _ChatSessionAction.copyId:
                          await onCopySessionId(session.sessionId);
                          return;
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<_ChatSessionAction>>[
                          const PopupMenuItem<_ChatSessionAction>(
                            value: _ChatSessionAction.rename,
                            child: Text('Rename'),
                          ),
                          PopupMenuItem<_ChatSessionAction>(
                            value: _ChatSessionAction.togglePin,
                            child: Text(session.pinned ? 'Unpin' : 'Pin'),
                          ),
                          PopupMenuItem<_ChatSessionAction>(
                            value: _ChatSessionAction.toggleArchive,
                            child: Text(
                              session.archived ? 'Restore' : 'Archive',
                            ),
                          ),
                          const PopupMenuItem<_ChatSessionAction>(
                            value: _ChatSessionAction.copyId,
                            child: Text('Copy ID'),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: LinearSpacing.xs),
              Text(
                session.summary.isEmpty
                    ? 'Conversation ready.'
                    : session.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: chrome.textTertiary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: LinearSpacing.sm),
              Wrap(
                spacing: LinearSpacing.xs,
                runSpacing: LinearSpacing.xs,
                children: metadata
                    .map((String label) => _SessionMetaChip(label: label))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionMetaChip extends StatelessWidget {
  const _SessionMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LinearSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.pill,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: chrome.textQuaternary),
      ),
    );
  }
}

String _formatChannelLabel(String channel) {
  if (channel.isEmpty) {
    return 'App';
  }
  return '${channel[0].toUpperCase()}${channel.substring(1)}';
}

String? _formatSessionTimestamp(String? rawTimestamp) {
  if (rawTimestamp == null || rawTimestamp.isEmpty) {
    return null;
  }

  final parsed = DateTime.tryParse(rawTimestamp)?.toLocal();
  if (parsed == null) {
    return null;
  }

  final now = DateTime.now();
  final difference = now.difference(parsed);
  if (difference.inMinutes < 1) {
    return 'Just now';
  }
  if (_isSameDay(parsed, now)) {
    return _formatClock(parsed);
  }
  if (difference.inDays < 7) {
    return _weekdayLabel(parsed.weekday);
  }
  if (parsed.year == now.year) {
    return '${_monthLabel(parsed.month)} ${parsed.day}';
  }
  return '${parsed.year}-${_twoDigits(parsed.month)}-${_twoDigits(parsed.day)}';
}

bool _isSameDay(DateTime lhs, DateTime rhs) {
  return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day;
}

String _formatClock(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${_twoDigits(value.minute)} $period';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _monthLabel(int month) {
  const labels = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return labels[month - 1];
}

String _weekdayLabel(int weekday) {
  const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[weekday - 1];
}
