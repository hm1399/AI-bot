import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final messages = state.currentMessages;

    return Column(
      children: <Widget>[
        ListTile(
          title: const Text('Conversation'),
          subtitle: Text(
            'Session: ${state.currentSessionId.isEmpty ? 'No active session' : state.currentSessionId}',
          ),
          trailing: Chip(
            label: Text(
              state.isDemoMode
                  ? 'Demo'
                  : state.eventStreamConnected
                  ? 'Events Live'
                  : 'Events Reconnecting',
            ),
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'User messages are posted once. Assistant progress and completion arrive later through the backend event stream.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    return MessageBubble(message: messages[index]);
                  },
                ),
        ),
        MessageInput(
          onSend: controller.sendMessage,
          onVoiceTap: controller.triggerVoiceInput,
          voiceEnabled: ref.watch(voiceAvailableProvider),
        ),
      ],
    );
  }
}
