import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import 'chat_session_list.dart';

Future<T?> showChatSessionDialog<T>(
  BuildContext context, {
  required List<SessionModel> sessions,
  required String currentSessionId,
  required ChatSessionListMode sessionListMode,
  required ValueChanged<ChatSessionListMode> onSessionListModeChanged,
  required Future<void> Function(String sessionId) onSelect,
  required Future<void> Function() onCreate,
  required Future<void> Function() onRefresh,
  required Future<void> Function(String sessionId) onCopySessionId,
  required Future<void> Function(SessionModel session) onRename,
  required Future<void> Function(SessionModel session, bool pinned) onSetPinned,
  required Future<void> Function(SessionModel session, bool archived)
  onSetArchived,
  bool closeOnSelect = true,
  bool closeOnCreate = true,
  bool closeOnRename = true,
  String title = 'Sessions',
  String activeDescription =
      'Switch, pin, or start a conversation without leaving the chat flow.',
  String archivedDescription =
      'Archived conversations stay readable and can be restored anytime.',
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext dialogContext) {
      return ChatSessionDialog(
        sessions: sessions,
        currentSessionId: currentSessionId,
        sessionListMode: sessionListMode,
        onSessionListModeChanged: onSessionListModeChanged,
        onSelect: (String sessionId) async {
          if (closeOnSelect) {
            Navigator.of(dialogContext).pop();
          }
          await onSelect(sessionId);
        },
        onCreate: () async {
          if (closeOnCreate) {
            Navigator.of(dialogContext).pop();
          }
          await onCreate();
        },
        onRefresh: onRefresh,
        onCopySessionId: onCopySessionId,
        onRename: (SessionModel session) async {
          if (closeOnRename) {
            Navigator.of(dialogContext).pop();
          }
          await onRename(session);
        },
        onSetPinned: onSetPinned,
        onSetArchived: onSetArchived,
        title: title,
        activeDescription: activeDescription,
        archivedDescription: archivedDescription,
      );
    },
  );
}

class ChatSessionDialog extends StatelessWidget {
  const ChatSessionDialog({
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
    this.activeDescription =
        'Switch, pin, or start a conversation without leaving the chat flow.',
    this.archivedDescription =
        'Archived conversations stay readable and can be restored anytime.',
    super.key,
  });

  final List<SessionModel> sessions;
  final String currentSessionId;
  final ChatSessionListMode sessionListMode;
  final ValueChanged<ChatSessionListMode> onSessionListModeChanged;
  final Future<void> Function(String sessionId) onSelect;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRefresh;
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
    final media = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(460.0, media.width - 32.0);
    final dialogHeight = math.min(720.0, media.height * 0.8);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      backgroundColor: chrome.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: LinearRadius.panel,
        side: BorderSide(color: chrome.borderStandard),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ChatSessionList(
          title: title,
          activeDescription: activeDescription,
          archivedDescription: archivedDescription,
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
      ),
    );
  }
}
