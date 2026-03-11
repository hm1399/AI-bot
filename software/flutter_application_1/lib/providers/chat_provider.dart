import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/message.dart';

// 状态类
class ChatState {
  final List<Message> messages;
  final bool isLoading;

  ChatState({required this.messages, required this.isLoading});

  ChatState copyWith({List<Message>? messages, bool? isLoading}) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Notifier
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(ChatState(messages: [], isLoading: false));

  void addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void handleWsMessage(Map<String, dynamic> message) {
    if (message['type'] == 'chat') {
      final msg = Message.fromJson(message['data']);
      addMessage(msg);
    } else if (message['type'] == 'tool_result') {
      final resultMsg = Message(
        id: DateTime.now().toString(),
        text: '工具执行结果',
        sender: MessageSender.device,
        timestamp: DateTime.now(),
        toolResult: message['data'],
      );
      addMessage(resultMsg);
    }
  }
}

// Provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

// WebSocket 消息处理器（供 ws_service 注册）
final chatWsHandlerProvider = Provider<Function>((ref) {
  return (Map<String, dynamic> message) {
    ref.read(chatProvider.notifier).handleWsMessage(message);
  };
});