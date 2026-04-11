import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import 'chat_session_list.dart';

class ChatSessionPanel extends StatelessWidget {
  const ChatSessionPanel({
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
    this.title = 'Conversations',
    this.description,
    this.showBorder = true,
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
  final String? description;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.panel,
        border: showBorder
            ? Border.all(color: chrome.borderStandard)
            : Border.all(color: Colors.transparent),
      ),
      child: ChatSessionList(
        title: title,
        activeDescription: description ?? 'Backend-driven app sessions.',
        archivedDescription:
            description ??
            'Archived conversations remain readable and restorable.',
        sessions: sessions,
        currentSessionId: currentSessionId,
        sessionListMode: sessionListMode,
        onSessionListModeChanged: onSessionListModeChanged,
        onSelect: onSelect,
        onCreate: onCreate,
        onRefresh: onRefresh,
        onCopySessionId: onCopySessionId,
        onRename: onRename,
        onSetPinned: onSetPinned,
        onSetArchived: onSetArchived,
      ),
    );
  }
}
