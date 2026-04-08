import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/chat/session_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/app_state.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final messages = state.currentMessages;
    final voice = ref.watch(voiceUiStateProvider);
    final currentSession = state.sessions.where(
      (SessionModel item) => item.sessionId == state.currentSessionId,
    );
    final activeSession = currentSession.isEmpty ? null : currentSession.first;

    return Column(
      children: <Widget>[
        Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                ListTile(
                  title: Text(activeSession?.title ?? 'No active conversation'),
                  subtitle: Text(
                    activeSession == null
                        ? 'Create a conversation to start sending app text messages.'
                        : '${activeSession.summary.isEmpty ? 'Conversation ready.' : activeSession.summary}\n${activeSession.sessionId}',
                  ),
                  isThreeLine: activeSession != null,
                  onTap: () => _showSessionSheet(context, ref, state),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Chip(
                        label: Text(
                          state.isDemoMode
                              ? 'Demo'
                              : state.eventStreamConnected
                              ? 'Events Live'
                              : 'Events Reconnecting',
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh conversations',
                        onPressed: controller.loadSessions,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Create conversation',
                        onPressed: () => _showCreateSessionDialog(context, ref),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Voice Handoff',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _StatusRow(
                  icon: Icons.sensors,
                  label: 'Device online',
                  value: voice.deviceOnline ? 'Ready' : 'Offline',
                  active: voice.deviceOnline,
                ),
                const SizedBox(height: 8),
                _StatusRow(
                  icon: Icons.settings_voice_outlined,
                  label: 'Desktop microphone bridge',
                  value: voice.desktopBridgeReady ? 'Ready' : 'Waiting',
                  active: voice.desktopBridgeReady,
                ),
                const SizedBox(height: 8),
                _StatusRow(
                  icon: Icons.subtitles_outlined,
                  label: 'Current output mode',
                  value: 'Device text/status feedback',
                  active: true,
                ),
                const SizedBox(height: 12),
                Text(voice.primaryDescription),
                const SizedBox(height: 6),
                Text(voice.inputModeLabel),
                const SizedBox(height: 6),
                Text(voice.outputModeLabel),
                if (voice.statusMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(voice.statusMessage!),
                ],
                if (voice.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    voice.errorMessage!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (state.globalMessage != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            color: const Color(0xFFF8FAFC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(state.globalMessage!),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await controller.loadMessages();
              await controller.loadSessions();
            },
            child: messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: const <Widget>[
                      Text(
                        'App text messages are sent from this page. Voice interactions still begin with pressing and holding the device, not recording inside the app.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ListView.builder(
                    reverse: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      return MessageBubble(message: messages[index]);
                    },
                  ),
          ),
        ),
        MessageInput(
          onSend: controller.sendMessage,
          onVoiceTap: controller.triggerVoiceInput,
          voiceReady: ref.watch(voiceAvailableProvider),
          voiceTooltip: voice.bridgeDescription,
        ),
      ],
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color: active ? const Color(0xFF15803D) : const Color(0xFF64748B),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: active ? const Color(0xFF15803D) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
