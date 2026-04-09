import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/chat/message_model.dart';
import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';
import '../../widgets/chat/chat_session_panel.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/chat/voice_handoff_card.dart';
import '../../widgets/common/status_pill.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final voice = ref.watch(voiceUiStateProvider);
    final currentSession = state.sessions.where(
      (SessionModel item) => item.sessionId == state.currentSessionId,
    );
    final activeSession = currentSession.isEmpty ? null : currentSession.first;

    Future<void> copySessionId(String sessionId) async {
      await Clipboard.setData(ClipboardData(text: sessionId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session ID copied.')));
      }
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final useDesktopShell = constraints.maxWidth >= 1180;
        final conversationView = _ConversationView(
          state: state,
          activeSession: activeSession,
          voice: voice,
          onShowSessions: () => _showSessionSheet(context, ref, state),
          onCopySessionId: copySessionId,
          onRefreshConversation: () async {
            await controller.loadMessages();
            await controller.loadSessions();
          },
        );

        if (!useDesktopShell) {
          return Column(
            children: <Widget>[
              Expanded(child: conversationView),
              MessageInput(
                onSend: controller.sendMessage,
                onVoiceTap: controller.triggerVoiceInput,
                voiceReady: ref.watch(voiceAvailableProvider),
                voiceTooltip: voice.bridgeDescription,
              ),
            ],
          );
        }

        return Row(
          children: <Widget>[
            SizedBox(
              width: 320,
              child: ChatSessionPanel(
                sessions: state.sessions,
                currentSessionId: state.currentSessionId,
                onSelect: controller.selectSession,
                onCreate: () => _showCreateSessionDialog(context, ref),
                onRefresh: controller.loadSessions,
                onCopySessionId: copySessionId,
              ),
            ),
            const SizedBox(width: LinearSpacing.md),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(child: conversationView),
                  MessageInput(
                    onSend: controller.sendMessage,
                    onVoiceTap: controller.triggerVoiceInput,
                    voiceReady: ref.watch(voiceAvailableProvider),
                    voiceTooltip: voice.bridgeDescription,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LinearSpacing.md),
            SizedBox(width: 300, child: VoiceHandoffCard(voice: voice)),
          ],
        );
      },
    );
  }

  Future<void> _showCreateSessionDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('New Conversation'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'New conversation',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (created == true) {
      await ref
          .read(appControllerProvider.notifier)
          .createSession(title: titleController.text.trim());
    }
    titleController.dispose();
  }

  Future<void> _showSessionSheet(
    BuildContext context,
    WidgetRef ref,
    AppState state,
  ) async {
    final controller = ref.read(appControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Conversations',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: controller.loadSessions,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Create conversation',
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _showCreateSessionDialog(context, ref);
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: state.sessions.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No conversations yet.'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: state.sessions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final session = state.sessions[index];
                          final selected =
                              session.sessionId == state.currentSessionId;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(session.title),
                            subtitle: Text(
                              session.summary.isEmpty
                                  ? session.sessionId
                                  : '${session.summary}\n${session.sessionId}',
                            ),
                            isThreeLine: session.summary.isNotEmpty,
                            trailing: Chip(
                              label: Text('${session.messageCount}'),
                            ),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await controller.selectSession(session.sessionId);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationView extends StatelessWidget {
  const _ConversationView({
    required this.state,
    required this.activeSession,
    required this.voice,
    required this.onShowSessions,
    required this.onCopySessionId,
    required this.onRefreshConversation,
  });

  final AppState state;
  final SessionModel? activeSession;
  final VoiceUiState voice;
  final VoidCallback onShowSessions;
  final Future<void> Function(String sessionId) onCopySessionId;
  final Future<void> Function() onRefreshConversation;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final messageItems = state.currentMessages;
    final latestStructuredMessage = _latestStructuredMessage(messageItems);

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(LinearSpacing.md),
          decoration: BoxDecoration(
            color: chrome.surface,
            borderRadius: LinearRadius.card,
            border: Border.all(color: chrome.borderStandard),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      activeSession?.title ?? 'No active conversation',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeSession == null
                          ? 'Create a conversation to start sending app text messages.'
                          : activeSession!.summary.isEmpty
                          ? 'Conversation ready.'
                          : activeSession!.summary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Send natural language instructions here. Structured planning results, normalized times, conflicts, and confirmation requests render inline.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: chrome.textQuaternary,
                      ),
                    ),
                    if (activeSession != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: LinearSpacing.xs,
                        runSpacing: LinearSpacing.xs,
                        children: <Widget>[
                          StatusPill(
                            label: state.isDemoMode
                                ? 'Demo'
                                : state.eventStreamConnected
                                ? 'Events Live'
                                : 'Events Reconnecting',
                            tone: state.isDemoMode
                                ? StatusPillTone.accent
                                : state.eventStreamConnected
                                ? StatusPillTone.success
                                : StatusPillTone.warning,
                          ),
                          StatusPill(
                            label: '${activeSession!.messageCount} messages',
                            icon: Icons.chat_bubble_outline,
                          ),
                          StatusPill(
                            label: latestStructuredMessage == null
                                ? 'Text to plan'
                                : 'Structured result ready',
                            tone: latestStructuredMessage == null
                                ? StatusPillTone.accent
                                : StatusPillTone.success,
                            icon: Icons.account_tree_outlined,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: LinearSpacing.sm),
              if (activeSession != null)
                OutlinedButton.icon(
                  onPressed: () => onCopySessionId(activeSession!.sessionId),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy ID'),
                ),
              const SizedBox(width: LinearSpacing.xs),
              OutlinedButton.icon(
                onPressed: onShowSessions,
                icon: const Icon(Icons.view_sidebar_outlined, size: 16),
                label: const Text('Sessions'),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinearSpacing.md),
        if (MediaQuery.sizeOf(context).width < 1180) ...<Widget>[
          VoiceHandoffCard(voice: voice),
          const SizedBox(height: LinearSpacing.md),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: chrome.surface,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderStandard),
            ),
            child: RefreshIndicator(
              onRefresh: onRefreshConversation,
              child: Column(
                children: <Widget>[
                  if (state.messagesLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (latestStructuredMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LinearSpacing.md,
                        LinearSpacing.md,
                        LinearSpacing.md,
                        0,
                      ),
                      child: _StructuredResultPreview(
                        message: latestStructuredMessage,
                      ),
                    ),
                  Expanded(
                    child: messageItems.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(LinearSpacing.xl),
                            children: const <Widget>[
                              Text(
                                'App text messages are sent from this page. Planning bundles and structured results will appear inline once the assistant returns metadata. Voice interactions still begin with pressing and holding the device, not recording inside the app.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(LinearSpacing.md),
                            itemCount: messageItems.length,
                            itemBuilder: (BuildContext context, int index) {
                              return MessageBubble(
                                message: messageItems[index],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

MessageModel? _latestStructuredMessage(List<MessageModel> messages) {
  for (final message in messages.reversed) {
    if (message.role == 'assistant' && message.hasPlanningMetadata) {
      return message;
    }
  }
  return null;
}

class _StructuredResultPreview extends StatelessWidget {
  const _StructuredResultPreview({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final metadata = message.planningMetadata;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(
          color: metadata.requiresUserConfirmation
              ? chrome.warning
              : chrome.borderStandard,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Latest Structured Result',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (metadata.bundleId?.isNotEmpty == true)
                Chip(label: Text('Bundle ${metadata.bundleId}')),
            ],
          ),
          if (message.text.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              message.text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              if (metadata.resourceType?.isNotEmpty == true)
                Chip(label: Text(metadata.resourceType!)),
              if (metadata.resourceIds.isNotEmpty)
                Chip(label: Text('${metadata.resourceIds.length} resources')),
              if (metadata.normalizedTime?.isNotEmpty == true)
                Chip(label: Text(metadata.normalizedTime!)),
              if (metadata.conflicts.isNotEmpty)
                Chip(label: Text('${metadata.conflicts.length} conflicts')),
              if (metadata.requiresUserConfirmation)
                Chip(
                  label: Text(
                    metadata.confirmationLabel ?? 'Awaiting user confirmation',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
