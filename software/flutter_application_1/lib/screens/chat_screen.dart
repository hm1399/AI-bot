import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/message.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/chat_provider.dart';
import '../service/ws_service.dart';
import '../widget/chat_bubble.dart';
import '../widget/message_input.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;

    return Scaffold(
      appBar: AppBar(title: Text('对话')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[messages.length - 1 - index];
                return ChatBubble(message: msg);
              },
            ),
          ),
          MessageInput(
            onSend: (text) {
              // 发送消息到 WebSocket
              WebSocketService().sendMessage({
                'type': 'chat',
                'text': text,
              });
              // 同时在本机添加一条 app 消息（乐观更新）
              ref.read(chatProvider.notifier).addMessage(Message(
                id: DateTime.now().toString(),
                text: text,
                sender: MessageSender.app,
                timestamp: DateTime.now(),
              ));
            },
          ),
        ],
      ),
    );
  }
}