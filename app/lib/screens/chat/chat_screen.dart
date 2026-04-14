import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/experience/experience_model.dart';
import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/chat/chat_session_dialog.dart';
import '../../widgets/chat/experience_chip_bar.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';

enum _ActiveConversationAction { rename, togglePin, toggleArchive, copyId }

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final voice = ref.watch(voiceUiStateProvider);
    final voiceReady = ref.watch(voiceAvailableProvider);
    final activeSession = state.sessions
        .where((SessionModel item) => item.sessionId == state.currentSessionId)
        .firstOrNull;
    final canSendMessage = activeSession != null && !activeSession.archived;
    final experience = state.currentExperience;

    Future<void> copySessionId(String sessionId) async {
      await Clipboard.setData(ClipboardData(text: sessionId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session ID copied.')));
      }
    }

    Future<String?> showSessionTitleDialog({
      required String title,
      required String confirmLabel,
      String initialValue = '',
      String hintText = 'New conversation',
    }) async {
      final titleController = TextEditingController(text: initialValue);
      final submitted = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: hintText,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
      final value = submitted == true ? titleController.text.trim() : null;
      titleController.dispose();
      return value;
    }

    Future<void> createSession() async {
      final title = await showSessionTitleDialog(
        title: 'New Conversation',
        confirmLabel: 'Create',
        hintText: 'Leave blank to auto-title later',
      );
      if (title != null) {
        await controller.createSession(title: title);
      }
    }

    Future<void> renameSession(SessionModel session) async {
      final title = await showSessionTitleDialog(
        title: 'Rename Conversation',
        confirmLabel: 'Save',
        initialValue: session.title,
      );
      if (title != null) {
        await controller.renameSession(session.sessionId, title);
      }
    }

    Future<void> showSessionsDialog() async {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return Consumer(
            builder:
                (BuildContext context, WidgetRef dialogRef, Widget? child) {
                  final dialogState = dialogRef.watch(appControllerProvider);
                  final currentListMode = dialogRef.watch(
                    chatSessionListModeProvider,
                  );

                  return ChatSessionDialog(
                    sessions: dialogState.sessions,
                    currentSessionId: dialogState.currentSessionId,
                    sessionListMode: currentListMode,
                    onSessionListModeChanged: (ChatSessionListMode value) {
                      dialogRef
                              .read(chatSessionListModeProvider.notifier)
                              .state =
                          value;
                    },
                    onSelect: (String sessionId) async {
                      Navigator.of(dialogContext).pop();
                      await controller.selectSession(sessionId);
                    },
                    onCreate: () async {
                      Navigator.of(dialogContext).pop();
                      await createSession();
                    },
                    onRefresh: controller.loadSessions,
                    onCopySessionId: copySessionId,
                    onRename: (SessionModel session) async {
                      Navigator.of(dialogContext).pop();
                      await renameSession(session);
                    },
                    onSetPinned: (SessionModel session, bool pinned) =>
                        controller.setSessionPinned(session.sessionId, pinned),
                    onSetArchived: (SessionModel session, bool archived) async {
                      Navigator.of(dialogContext).pop();
                      await controller.setSessionArchived(
                        session.sessionId,
                        archived,
                      );
                    },
                  );
                },
          );
        },
      );
    }

    Future<void> handleConversationAction(
      _ActiveConversationAction action,
    ) async {
      if (activeSession == null) {
        return;
      }
      switch (action) {
        case _ActiveConversationAction.rename:
          await renameSession(activeSession);
          return;
        case _ActiveConversationAction.togglePin:
          await controller.setSessionPinned(
            activeSession.sessionId,
            !activeSession.pinned,
          );
          return;
        case _ActiveConversationAction.toggleArchive:
          await controller.setSessionArchived(
            activeSession.sessionId,
            !activeSession.archived,
          );
          return;
        case _ActiveConversationAction.copyId:
          await copySessionId(activeSession.sessionId);
          return;
      }
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final pageWidth = constraints.maxWidth;
        final targetWidth = pageWidth >= 900
            ? (pageWidth * 0.92).clamp(920.0, 1320.0)
            : pageWidth;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            pageWidth >= 900 ? LinearSpacing.lg : LinearSpacing.sm,
            LinearSpacing.sm,
            pageWidth >= 900 ? LinearSpacing.lg : LinearSpacing.sm,
            LinearSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: targetWidth,
              child: Column(
                children: <Widget>[
                  _ChatHeader(
                    activeSession: activeSession,
                    onCreate: createSession,
                    onShowSessions: showSessionsDialog,
                    onConversationAction: handleConversationAction,
                  ),
                  const SizedBox(height: LinearSpacing.sm),
                  ExperienceChipBar(
                    experience: experience,
                    catalog: state.experienceCatalog,
                    enabled: activeSession != null && !activeSession.archived,
                    onSceneSelected: (String sceneMode) => controller
                        .updateCurrentSessionExperience(sceneMode: sceneMode),
                    onPersonaSelected: (PersonaPresetModel preset) => controller
                        .updateCurrentSessionExperience(personaPreset: preset),
                  ),
                  const SizedBox(height: LinearSpacing.sm),
                  Expanded(
                    child: _ConversationPanel(
                      state: state,
                      activeSession: activeSession,
                      onCreateSession: createSession,
                      onShowSessions: showSessionsDialog,
                      onRefreshConversation: () async {
                        await controller.loadMessages();
                        await controller.loadSessions();
                      },
                      voice: voice,
                      onSend: controller.sendMessage,
                      onVoiceTap: controller.triggerVoiceInput,
                      voiceReady: voiceReady,
                      canSendMessage: canSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.activeSession,
    required this.onCreate,
    required this.onShowSessions,
    required this.onConversationAction,
  });

  final SessionModel? activeSession;
  final Future<void> Function() onCreate;
  final Future<void> Function() onShowSessions;
  final Future<void> Function(_ActiveConversationAction action)
  onConversationAction;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final stacked = constraints.maxWidth < 760;
        final actions = Wrap(
          spacing: LinearSpacing.xs,
          runSpacing: LinearSpacing.xs,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New'),
            ),
            OutlinedButton.icon(
              onPressed: onShowSessions,
              icon: const Icon(Icons.chat_outlined, size: 16),
              label: const Text('Sessions'),
            ),
            if (activeSession != null)
              PopupMenuButton<_ActiveConversationAction>(
                tooltip: 'Conversation actions',
                onSelected: onConversationAction,
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_ActiveConversationAction>>[
                      const PopupMenuItem(
                        value: _ActiveConversationAction.rename,
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: _ActiveConversationAction.togglePin,
                        child: Text(activeSession!.pinned ? 'Unpin' : 'Pin'),
                      ),
                      PopupMenuItem(
                        value: _ActiveConversationAction.toggleArchive,
                        child: Text(
                          activeSession!.archived ? 'Restore' : 'Archive',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ActiveConversationAction.copyId,
                        child: Text('Copy ID'),
                      ),
                    ],
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(
                    horizontal: LinearSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: chrome.surface,
                    borderRadius: LinearRadius.control,
                    border: Border.all(color: chrome.borderStandard),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[Icon(Icons.more_horiz, size: 18)],
                  ),
                ),
              ),
          ],
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              activeSession?.title ?? 'Chat',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_sessionSummary(activeSession) case final String summary)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
                ),
              ),
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              content,
              const SizedBox(height: LinearSpacing.sm),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: content),
            const SizedBox(width: LinearSpacing.md),
            Flexible(child: actions),
          ],
        );
      },
    );
  }

  String? _sessionSummary(SessionModel? session) {
    if (session == null) {
      return null;
    }
    if (session.archived) {
      return 'Archived conversation';
    }
    if (session.summary.isNotEmpty) {
      return session.summary;
    }
    return null;
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.state,
    required this.activeSession,
    required this.onCreateSession,
    required this.onShowSessions,
    required this.onRefreshConversation,
    required this.voice,
    required this.onSend,
    required this.onVoiceTap,
    required this.voiceReady,
    required this.canSendMessage,
  });

  final AppState state;
  final SessionModel? activeSession;
  final Future<void> Function() onCreateSession;
  final Future<void> Function() onShowSessions;
  final Future<void> Function() onRefreshConversation;
  final VoiceUiState voice;
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onVoiceTap;
  final bool voiceReady;
  final bool canSendMessage;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final messageItems = state.currentMessages;
    final notice = _notice;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        children: <Widget>[
          if (state.messagesLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (notice != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LinearSpacing.md,
                LinearSpacing.sm,
                LinearSpacing.md,
                LinearSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  notice,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: activeSession?.archived == true
                        ? chrome.warning
                        : chrome.textQuaternary,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefreshConversation,
              child: messageItems.isEmpty
                  ? _EmptyConversationState(
                      activeSession: activeSession,
                      hasSessions: state.sessions.isNotEmpty,
                      onCreateSession: onCreateSession,
                      onShowSessions: onShowSessions,
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(LinearSpacing.md),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: messageItems.length,
                        itemBuilder: (BuildContext context, int index) {
                          return MessageBubble(message: messageItems[index]);
                        },
                      ),
                    ),
            ),
          ),
          const Divider(height: 1),
          MessageInput(
            onSend: onSend,
            onVoiceTap: onVoiceTap,
            enabled: canSendMessage,
            voiceReady: voiceReady,
            voiceTooltip: activeSession?.archived == true
                ? 'Restore this conversation before continuing it.'
                : activeSession == null
                ? 'Create or select a conversation before speaking.'
                : voice.bridgeDescription,
            embedded: true,
          ),
        ],
      ),
    );
  }

  String? get _notice {
    if (activeSession?.archived == true) {
      return 'This conversation is archived. Restore it from Sessions to reply.';
    }
    if (voice.errorMessage != null && voice.errorMessage!.trim().isNotEmpty) {
      return voice.errorMessage!.trim();
    }
    return null;
  }
}

class _EmptyConversationState extends StatelessWidget {
  const _EmptyConversationState({
    required this.activeSession,
    required this.hasSessions,
    required this.onCreateSession,
    required this.onShowSessions,
  });

  final SessionModel? activeSession;
  final bool hasSessions;
  final Future<void> Function() onCreateSession;
  final Future<void> Function() onShowSessions;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(LinearSpacing.xl),
      children: <Widget>[
        const SizedBox(height: 56),
        Icon(Icons.chat_bubble_outline, size: 36, color: chrome.textTertiary),
        const SizedBox(height: LinearSpacing.md),
        Text(
          _title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: LinearSpacing.sm),
        Text(
          _description,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
        ),
        const SizedBox(height: LinearSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: LinearSpacing.xs,
          runSpacing: LinearSpacing.xs,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onCreateSession,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Conversation'),
            ),
            if (hasSessions)
              OutlinedButton.icon(
                onPressed: onShowSessions,
                icon: const Icon(Icons.chat_outlined, size: 16),
                label: const Text('Browse Sessions'),
              ),
          ],
        ),
      ],
    );
  }

  String get _title {
    if (activeSession == null) {
      return 'No conversation selected';
    }
    if (activeSession!.archived) {
      return 'Archived conversation';
    }
    return 'Conversation ready';
  }

  String get _description {
    if (activeSession == null) {
      return 'Create a new conversation or open Sessions to continue an older thread. Once a session is active, the full message history will appear here.';
    }
    if (activeSession!.archived) {
      return 'This session stays readable, but replies are disabled until you restore it from the Sessions dialog.';
    }
    return 'Send a message to begin. Structured planning results will stay inside the assistant replies instead of taking over the page.';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
